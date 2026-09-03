import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/bootstrap/app_environment.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import 'technician_location_repository.dart';

class TechnicianLocationTrackingState {
  const TechnicianLocationTrackingState({
    this.active = false,
    this.busy = false,
    this.lastSentAt,
    this.message,
  });

  final bool active;
  final bool busy;
  final DateTime? lastSentAt;
  final String? message;

  TechnicianLocationTrackingState copyWith({
    bool? active,
    bool? busy,
    DateTime? lastSentAt,
    String? message,
    bool clearMessage = false,
  }) {
    return TechnicianLocationTrackingState(
      active: active ?? this.active,
      busy: busy ?? this.busy,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class TechnicianLocationTrackingController
    extends StateNotifier<TechnicianLocationTrackingState> {
  TechnicianLocationTrackingController(this._repository)
      : super(const TechnicianLocationTrackingState());

  static const _prefKey = 'motus_technician_location_tracking_enabled';
  static const _prefDateKey = 'motus_technician_location_tracking_date';
  static const MethodChannel _nativeLocationChannel =
      MethodChannel('motus/native_location_service');

  final TechnicianLocationRepository _repository;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeat;
  Position? _lastPosition;
  DateTime? _lastPushAt;

  /// Tekniker oturumu açıldığında konum takibini kullanıcıya düğme göstermeden
  /// otomatik başlatır. İşletim sistemi izni yine kullanıcı tarafından verilmelidir.
  Future<void> ensureActive() async {
    if (state.active || state.busy) return;
    await enable(requestPermission: true);
  }

  /// Eski çağrılarla uyumluluk için bırakıldı; V70'ten itibaren otomatik başlatır.
  Future<void> resumeIfEnabled() => ensureActive();

  Future<bool> enable({
    bool requestPermission = true,
    Position? initialPosition,
  }) async {
    if (state.active) {
      if (initialPosition != null) await publishPosition(initialPosition);
      return true;
    }
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearMessage: true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = state.copyWith(
          active: false,
          busy: false,
          message: 'Konum servisi kapalı.',
        );
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          active: false,
          busy: false,
          message: 'Konum izni gerekli.',
        );
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      await prefs.setString(_prefDateKey, _todayKey());

      final position = initialPosition ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
      _lastPosition = position;
      await _push(position, force: true);

      // Android APK'da takip Flutter ekranına bağlı bırakılmaz.
      // Gerçek native foreground location service başlatılır; uygulama ana
      // ekrana alınsa veya ekran kilitlense bile servis çalışmaya devam eder.
      final nativeStarted = await _startNativeAndroidService();
      if (!nativeStarted) {
        // Native servis başlatılamazsa mevcut Geolocator akışını fallback
        // olarak koru; web/iOS tarafı da bu akışı kullanır.
        _startStream();
        _startHeartbeat();
      } else if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        _startStream();
        _startHeartbeat();
      }

      state = state.copyWith(active: true, busy: false, clearMessage: true);
      return true;
    } catch (error) {
      state = state.copyWith(
        active: false,
        busy: false,
        message: _friendlyError(error),
      );
      return false;
    }
  }

  Future<void> publishPosition(Position position) async {
    _lastPosition = position;
    try {
      await _push(position, force: true);
    } catch (error) {
      state = state.copyWith(message: _friendlyError(error));
    }
  }

  Future<void> disable() async {
    try {
      await _repository.setSharing(false);
    } catch (_) {}
    await _stopNativeAndroidService();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    await prefs.remove(_prefDateKey);
    state = state.copyWith(active: false, busy: false, clearMessage: true);
  }

  Future<void> stopForLogout() async {
    await _stopNativeAndroidService();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    await prefs.remove(_prefDateKey);
    state = const TechnicianLocationTrackingState();
  }

  Future<bool> _startNativeAndroidService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final environment = AppEnvironment.fromEnvironment();
      if (session == null || !environment.isConfigured) return false;

      final result = await _nativeLocationChannel.invokeMethod<bool>(
        'start',
        <String, dynamic>{
          'supabaseUrl': environment.supabaseUrl,
          'apiKey': environment.supabasePublishableKey,
          'accessToken': session.accessToken,
          'refreshToken': session.refreshToken ?? '',
        },
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopNativeAndroidService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _nativeLocationChannel.invokeMethod<void>('stop');
    } catch (_) {
      // Uygulama kapanışında servis zaten durmuş olabilir.
    }
  }

  void _startStream() {
    _positionSubscription?.cancel();

    // Web/PWA tarayıcı açıkken canlı takip yapar. Android native uygulamada
    // foreground location service sayesinde ekran kapalıyken de mesai boyunca
    // konum akışı devam edebilir.
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MOTUS konum takibi aktif',
          notificationText: 'Mesai boyunca canlı konumunuz paylaşılıyor.',
          enableWakeLock: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 20,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 40,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        _lastPosition = position;
        unawaited(_push(position));
      },
      onError: (Object error) {
        state = state.copyWith(message: _friendlyError(error));
      },
    );
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(minutes: 1), (_) async {
      try {
        Position? position = _lastPosition;
        if (position == null ||
            DateTime.now().difference(position.timestamp).inMinutes >= 1) {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
            ),
          );
          _lastPosition = position;
        }
        await _push(position, force: true);
      } catch (_) {
        // Web/PWA arka planda uyutulabilir. Native iOS sürümünde aynı
        // repository arka plan servisi tarafından kullanılacak.
      }
    });
  }

  Future<void> _push(Position position, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastPushAt != null && now.difference(_lastPushAt!) < const Duration(seconds: 15)) {
      return;
    }
    await _repository.pushPosition(
      position,
      source: kIsWeb ? 'web-pwa' : 'flutter-app',
    );
    _lastPushAt = now;
    state = state.copyWith(lastSentAt: now, clearMessage: true);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('technician_push_location_v1') ||
        text.contains('does not exist') ||
        text.contains('pgrst202')) {
      return 'Konum veritabanı kurulumu gerekli.';
    }
    if (text.contains('permission')) return 'Konum izni gerekli.';
    return 'Konum gönderilemedi.';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }
}

final technicianLocationTrackingControllerProvider = StateNotifierProvider<
    TechnicianLocationTrackingController, TechnicianLocationTrackingState>((ref) {
  final controller = TechnicianLocationTrackingController(
    ref.watch(technicianLocationRepositoryProvider),
  );
  ref.listen(authControllerProvider, (previous, next) {
    final leftTechnicianSession = previous?.role == AppRole.technician &&
        (!next.isAuthenticated || next.role != AppRole.technician);
    if (leftTechnicianSession) {
      unawaited(controller.stopForLogout());
    }
  });
  return controller;
});
