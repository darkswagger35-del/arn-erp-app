import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../../settings/data/company_app_settings.dart';
import '../data/service_execution_providers.dart';
import '../data/service_execution_repository.dart';
import 'technician_service_pdf.dart';

class TechnicianJobsScreen extends ConsumerStatefulWidget {
  const TechnicianJobsScreen({super.key});

  @override
  ConsumerState<TechnicianJobsScreen> createState() =>
      _TechnicianJobsScreenState();
}

class _TechnicianJobsScreenState extends ConsumerState<TechnicianJobsScreen> {
  late Future<_TechnicianJobsData> _future;
  DateTime _selectedDate = DateTime.now();
  TechnicianJob? _selectedJob;
  final WebviewController _mapController = WebviewController();
  bool _mapReady = false;
  String? _lastMapUrl;
  Position? _currentPosition;
  String? _startPointLabel;
  double? _startPointLatitude;
  double? _startPointLongitude;
  final Map<String, ({double lat, double lon})> _jobPointCache = {};
  List<String> _localRouteOrderIds = const <String>[];
  bool _routeBuilt = false;
  bool _optimizing = false;
  Timer? _yandexRouteSyncTimer;
  StreamSubscription<String>? _mapUrlSub;
  String? _yandexStartText;

  static const String _yandexGeocoderKey =
      String.fromEnvironment('YANDEX_GEOCODER_API_KEY');

  static const _cannotAttendReasons = <String>[
    'Müşteri ulaşılmadı',
    'Müşteri erteledi',
    'Adres sorunu',
    'Araç / teknik sorun',
    'Yoğunluk',
    'Diğer',
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();
    _initMap();
  }

  @override
  void dispose() {
    _yandexRouteSyncTimer?.cancel();
    _mapUrlSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initMap() async {
    if (!Platform.isWindows) return;
    try {
      await _mapController.initialize();
      _mapUrlSub = _mapController.url.listen((url) {
        if (url.contains('yandex.com.tr/maps') && url.contains('mode=routes')) {
          _lastMapUrl = url;
        }
      });
      if (mounted) setState(() => _mapReady = true);
      await _openNativeYandexStartPlanner(showHint: false);
    } catch (_) {
      if (mounted) setState(() => _mapReady = false);
    }
  }

  bool _sameDay(DateTime? value, DateTime day) {
    if (value == null) return false;
    final local = value.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }

  Future<_TechnicianJobsData> _load() async {
    final repo = ref.read(serviceExecutionRepositoryProvider);
    final results = await Future.wait([
      repo.getTechnicianJobs(''),
      repo.getCompletedJobsForDay(_selectedDate),
      repo.getFailedJobsForDay(_selectedDate),
    ]);
    final active = (results[0] as List<TechnicianJob>)
        .where((job) => _sameDay(job.plannedDate, _selectedDate))
        .toList(growable: true);
    active.sort((a, b) {
      // Rota yeni oluşturulduğunda RPC cevabını bekleyip eski sıraya dönme.
      // Önce bu oturumda hesaplanan kesin sıra, sonra Supabase route_order kullanılır.
      if (_localRouteOrderIds.isNotEmpty) {
        final ai = _localRouteOrderIds.indexOf(a.id);
        final bi = _localRouteOrderIds.indexOf(b.id);
        if (ai >= 0 || bi >= 0) {
          return (ai >= 0 ? ai : 9999).compareTo(bi >= 0 ? bi : 9999);
        }
      }
      final ao = a.routeOrder;
      final bo = b.routeOrder;
      if (ao != null || bo != null) return (ao ?? 9999).compareTo(bo ?? 9999);
      final ad = a.plannedDate ?? DateTime(2100);
      final bd = b.plannedDate ?? DateTime(2100);
      return ad.compareTo(bd);
    });
    return _TechnicianJobsData(
      active: active,
      completed: results[1] as List<TechnicianJob>,
      failed: results[2] as List<TechnicianJob>,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null || _sameDay(picked, _selectedDate)) return;
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _selectedDate = picked;
      _selectedJob = null;
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _localRouteOrderIds = const <String>[];
      _future = _load();
    });
  }

  void _moveDay(int days) {
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );
      _selectedJob = null;
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _localRouteOrderIds = const <String>[];
      _future = _load();
    });
  }

  void _refresh() {
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _selectedJob = null;
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _future = _load();
    });
  }

  Future<void> _openCustomerCard(TechnicianJob job) async {
    await context.push('/technician/customers/${job.customerId}');
    if (!mounted) return;
    // Karttan/düzenlemeden dönünce adres/telefon değişmiş olabilir.
    _jobPointCache.clear();
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _selectedJob = null;
      _future = _load();
    });
  }

  Future<void> _editCustomer(TechnicianJob job) async {
    await context.push('/technician/customers/${job.customerId}/edit');
    if (!mounted) return;
    // Yanlış adres düzeltildiyse eski geocode'u kesinlikle kullanma.
    _jobPointCache.clear();
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _selectedJob = null;
      _future = _load();
    });
  }


  Future<void> _openJob(TechnicianJob job) async {
    final result = await context.push<String>('/technician/jobs/${job.id}');
    if (!mounted) return;
    _refresh();

    // Mesajı kapanmakta olan servis ekranında göstermek yerine burada
    // gösteriyoruz. Böylece route değişimi sırasında snackbar/dialog
    // bağımlılığı kalmıyor ve Flutter framework assertion'ı oluşmuyor.
    if (result == 'could_not_complete') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İş tamamlanamadı olarak kaydedildi. Seçili gün geçmişinde görünmeye devam edecek.',
          ),
        ),
      );
    }
  }

  String _foldAddressText(String input) {
    var value = input.toLowerCase();
    const replacements = <String, String>{
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
    };
    for (final entry in replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    return value.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _canonicalJobAddress(TechnicianJob job) {
    var raw = job.address.trim();
    if (raw.isEmpty) return job.mapQuery.trim();

    // Kat / daire bilgileri geocoder icin faydali degil; tam tersine
    // "11B" gibi ilgisiz bir konuma eslesmeye sebep olabiliyor.
    raw = raw
        .replaceAll(
          RegExp(
            r'\b(?:k|kat|d|daire)\s*[:.]?\s*\d+[a-z]?\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final streetMatch = RegExp(
      r'(\d+(?:/\d+)?)\s*(?:sk\.?|sok\.?|sokak)\b',
      caseSensitive: false,
    ).firstMatch(raw);
    final implicitStreetMatch = streetMatch == null
        ? RegExp(
            r'^\s*(\d+(?:/\d+)?)\s+(?=no\b)',
            caseSensitive: false,
          ).firstMatch(raw)
        : null;
    final numberMatch = RegExp(
      r'\bno\s*[:.]?\s*(\d+[a-z]?(?:/\d+[a-z]?)?)',
      caseSensitive: false,
    ).firstMatch(raw);

    String core;
    final streetNo = streetMatch?.group(1) ?? implicitStreetMatch?.group(1);
    if (streetNo != null && streetNo.trim().isNotEmpty) {
      core = '$streetNo Sokak';
      final houseNo = numberMatch?.group(1);
      if (houseNo != null && houseNo.trim().isNotEmpty) {
        core += ' No:$houseNo';
      }
    } else {
      core = raw;
    }

    final parts = <String>[
      core,
      job.neighborhood.trim(),
      job.district.trim(),
      job.city.trim(),
      'Türkiye',
    ].where((value) => value.isNotEmpty).toList(growable: false);

    // Ayni il/ilce adres metninin icinde zaten varsa tekrar yazmayalim.
    final unique = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      final key = _foldAddressText(part);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      unique.add(part);
    }
    return unique.join(', ');
  }

  String _nativeRoutePointForJob(TechnicianJob job) {
    // Yandex'in kendi rota ekranina mumkun olan en acik adresi veriyoruz.
    // Eski otomatik koordinat/pin kullanilmiyor; mahalle-ilce-il bilgisi de
    // sorguda kalarak ayni sokak adinin baska sehre gitmesi engelleniyor.
    final rawParts = <String>[
      job.address.trim(),
      job.neighborhood.trim(),
      job.district.trim(),
      job.city.trim(),
      'Türkiye',
    ].where((e) => e.isNotEmpty).toList(growable: false);
    final result = <String>[];
    final seen = <String>{};
    for (final part in rawParts) {
      final key = _foldAddressText(part);
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      result.add(part);
    }
    return result.join(', ');
  }

  String _nativeRoutePlannerUrl({String rtext = ''}) {
    return Uri.https(
      'yandex.com.tr',
      '/maps/11505/izmir/',
      {
        'mode': 'routes',
        'rtext': rtext,
        'rtt': 'auto',
      },
    ).toString();
  }

  Future<void> _openNativeYandexStartPlanner({bool showHint = true}) async {
    if (!_mapReady || !Platform.isWindows) return;
    _yandexRouteSyncTimer?.cancel();
    _routeBuilt = false;
    _yandexStartText = null;
    _lastMapUrl = _nativeRoutePlannerUrl();
    try {
      await _mapController.loadUrl(_lastMapUrl!);
      if (showHint && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 6),
            content: Text(
              'Yandex’te “Nereden” alanina baslangic adresini yazip listeden secin veya “Konumum”u kullanin. Sonra Rotayi Olustur’a basin.',
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _readYandexInputs() async {
    if (!_mapReady || !Platform.isWindows) return const [];
    try {
      final value = await _mapController.executeScript(r'''
(() => Array.from(document.querySelectorAll('input')).map((e, i) => ({
  index: String(i),
  value: (e.value || '').trim(),
  placeholder: (e.getAttribute('placeholder') || '').trim(),
  aria: (e.getAttribute('aria-label') || '').trim()
})))()
''');
      dynamic decoded = value;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }
      if (decoded is List) {
        return decoded.whereType<Map>().map((row) {
          final map = Map<String, dynamic>.from(row);
          return <String, String>{
            'index': map['index']?.toString() ?? '',
            'value': map['value']?.toString() ?? '',
            'placeholder': map['placeholder']?.toString() ?? '',
            'aria': map['aria']?.toString() ?? '',
          };
        }).toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Future<String?> _readYandexStartText() async {
    final inputs = await _readYandexInputs();
    for (final input in inputs) {
      final meta = _foldAddressText(
        '${input['placeholder'] ?? ''} ${input['aria'] ?? ''}',
      );
      if (meta.contains('nereden')) {
        final value = (input['value'] ?? '').trim();
        if (value.isNotEmpty) return value;
      }
    }

    // Yandex bazen placeholder metnini degistiriyor. Rota ekranindaki ilk
    // dolu ve genel arama kutusu olmayan degeri baslangic kabul ediyoruz.
    for (final input in inputs) {
      final value = (input['value'] ?? '').trim();
      final placeholder = _foldAddressText(input['placeholder'] ?? '');
      if (value.isNotEmpty && !placeholder.contains('arama')) return value;
    }
    return null;
  }

  String _jobRouteSignature(TechnicianJob job) {
    final raw = _foldAddressText(job.address);
    final street = RegExp(r'(^|\s)(\d{2,5}(?:\s+\d+)?)\s*(?:sk|sok|sokak)?\b')
        .firstMatch(raw)
        ?.group(2)
        ?.replaceAll(' ', '/');
    final explicitNo = RegExp(r'\bno\s*(\d+[a-z]?)\b')
        .firstMatch(raw)
        ?.group(1);
    if (street == null || street.isEmpty) return '';
    return '$street#${explicitNo ?? ''}';
  }

  String _yandexValueSignature(String value) {
    final raw = _foldAddressText(value);
    final street = RegExp(r'(^|\s)(\d{2,5}(?:\s+\d+)?)\s*(?:sk|sok|sokak)\b')
        .firstMatch(raw)
        ?.group(2)
        ?.replaceAll(' ', '/');
    if (street == null || street.isEmpty) return '';
    final afterStreet = RegExp(
      r'\b(?:sk|sok|sokak)\b[^0-9]{0,8}(\d+[a-z]?)\b',
    ).firstMatch(raw)?.group(1);
    return '$street#${afterStreet ?? ''}';
  }

  Future<List<String>> _readYandexRtextValues() async {
    if (!_mapReady || !Platform.isWindows) return const [];
    try {
      final href = await _mapController.executeScript('window.location.href');
      final text = href?.toString() ?? '';
      if (text.isEmpty) return const [];
      final uri = Uri.tryParse(text);
      final rtext = uri?.queryParameters['rtext'];
      if (rtext == null || rtext.trim().isEmpty) return const [];
      return rtext
          .split('~')
          .map(Uri.decodeComponent)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _syncOrderFromYandexPlanner(List<TechnicianJob> jobs) async {
    if (!_routeBuilt || jobs.length < 2 || !mounted) return;
    final inputs = await _readYandexInputs();
    if (inputs.isEmpty) return;

    final bySignature = <String, TechnicianJob>{};
    final duplicateSignatures = <String>{};
    for (final job in jobs) {
      final signature = _jobRouteSignature(job);
      if (signature.isEmpty) continue;
      if (bySignature.containsKey(signature)) duplicateSignatures.add(signature);
      bySignature[signature] = job;
    }
    for (final key in duplicateSignatures) {
      bySignature.remove(key);
    }

    final candidateValues = <String>[
      ...inputs.map((e) => (e['value'] ?? '').trim()),
      ...await _readYandexRtextValues(),
    ].where((e) => e.isNotEmpty).toList(growable: false);

    final ordered = <TechnicianJob>[];
    for (final value in candidateValues) {
      final signature = _yandexValueSignature(value);
      final job = bySignature[signature];
      if (job != null && !ordered.any((e) => e.id == job.id)) {
        ordered.add(job);
      }
    }
    if (ordered.length != jobs.length) return;

    final ids = ordered.map((e) => e.id).toList(growable: false);
    final unchanged = _localRouteOrderIds.length == ids.length &&
        List.generate(ids.length, (i) => _localRouteOrderIds[i] == ids[i])
            .every((e) => e);
    if (unchanged) return;

    try {
      await ref
          .read(serviceExecutionRepositoryProvider)
          .saveTechnicianRouteOrder(ids);
    } catch (_) {
      // Kalici kayit basarisiz olsa bile ekrandaki sira Yandex ile esitlensin.
    }
    if (!mounted) return;
    setState(() {
      _localRouteOrderIds = ids;
      final selectedId = _selectedJob?.id;
      if (selectedId != null) {
        for (final item in ordered) {
          if (item.id == selectedId) {
            _selectedJob = item;
            break;
          }
        }
      }
      _future = _load();
    });
  }

  void _startYandexOrderSync(List<TechnicianJob> jobs) {
    _yandexRouteSyncTimer?.cancel();
    _yandexRouteSyncTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _syncOrderFromYandexPlanner(jobs),
    );
  }

  Future<bool> _clickYandexOptimizeIfAvailable() async {
    if (!_mapReady || !Platform.isWindows) return false;
    try {
      final result = await _mapController.executeScript(r'''
(() => {
  const nodes = Array.from(document.querySelectorAll('button, [role="button"]'));
  const target = nodes.find((e) => {
    const t = (e.textContent || '').replace(/\s+/g, ' ').trim().toLocaleLowerCase('tr-TR');
    return t === 'optimize et' || t.includes('optimize et');
  });
  if (!target) return false;
  target.click();
  return true;
})()
''');
      return result == true || result?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _buildRouteWithNativeYandex(List<TechnicianJob> jobs) async {
    if (jobs.isEmpty || _optimizing) return;
    if (!_mapReady || !Platform.isWindows) {
      await _launchYandex(jobs);
      return;
    }

    setState(() => _optimizing = true);
    try {
      final start = (await _readYandexStartText())?.trim();
      if (start == null || start.isEmpty) {
        await _openNativeYandexStartPlanner(showHint: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 7),
              content: Text(
                'Once Yandex’te “Nereden” alanina baslangic adresini yazin ve cikan listeden secin. Haritaya tiklamaniz gerekmiyor.',
              ),
            ),
          );
        }
        return;
      }

      _yandexStartText = start;
      final routeJobs = List<TechnicianJob>.from(jobs);
      if (_localRouteOrderIds.isNotEmpty) {
        routeJobs.sort((a, b) {
          final ai = _localRouteOrderIds.indexOf(a.id);
          final bi = _localRouteOrderIds.indexOf(b.id);
          return (ai < 0 ? 9999 : ai).compareTo(bi < 0 ? 9999 : bi);
        });
      }

      final points = <String>[
        start,
        ...routeJobs.map(_nativeRoutePointForJob).where((e) => e.isNotEmpty),
      ];
      final url = _nativeRoutePlannerUrl(rtext: points.join('~'));
      _lastMapUrl = url;
      _routeBuilt = true;
      _startPointLabel = start;
      await _mapController.loadUrl(url);
      _startYandexOrderSync(routeJobs);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      final optimizedAutomatically = await _clickYandexOptimizeIfAvailable();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              optimizedAutomatically
                  ? 'Yandex rotasi optimize edildi. Yandex sirasi soldaki is listesine otomatik aktariliyor.'
                  : 'Isler Yandex rota ekranina yuklendi. “Optimize et” gorunuyorsa bir kez basin; soldaki liste Yandex sirasi ile otomatik eslesir.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  String _routeUrl(List<TechnicianJob> jobs) {
    if (_lastMapUrl != null && _lastMapUrl!.contains('mode=routes')) {
      return _lastMapUrl!;
    }
    return _nativeRoutePlannerUrl();
  }

  Future<void> _syncMap(List<TechnicianJob> jobs) async {
    // Yandex rota ekraninin kendi Nereden secimini ve Optimize et siralamasini
    // tekrar loadUrl yaparak ezmiyoruz.
    if (!_mapReady || !Platform.isWindows || _lastMapUrl != null) return;
    await _openNativeYandexStartPlanner(showHint: false);
  }

  Future<void> _launchYandex(List<TechnicianJob> jobs) async {
    await launchUrl(
      Uri.parse(_routeUrl(jobs)),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _launchMap(TechnicianJob job) async {
    final query = job.mapQuery.trim().isNotEmpty
        ? job.mapQuery.trim()
        : job.locationText.trim();
    if (query.isEmpty) return;
    await launchUrl(
      Uri.https('yandex.com.tr', '/maps/', {
        'mode': 'search',
        'text': query,
      }),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _sendOnMyWay(String phone, String customerName) async {
    var cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) cleaned = '90${cleaned.substring(1)}';
    if (cleaned.isEmpty) return;

    final settings = await ref.read(companyAppSettingsProvider.future);
    final message = settings.onMyWayTemplate
        .replaceAll('{{musteri}}', customerName)
        .replaceAll('{{müşteri}}', customerName);
    final opened = await launchUrl(
      Uri.https('wa.me', '/$cleaned', {'text': message}),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp açılamadı.')),
      );
    }
  }

  Future<void> _launchPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return;
    await launchUrl(Uri.parse('tel:$cleaned'));
  }

  String _timeLabel(TechnicianJob job) {
    final range = RegExp(
      r'\[Aralık:(\d{2}):(\d{2})-(\d{2}):(\d{2})\]',
      caseSensitive: false,
    ).firstMatch(job.description);
    if (range != null) {
      return '${range.group(1)}:${range.group(2)} - ${range.group(3)}:${range.group(4)}';
    }
    final exact = RegExp(
      r'\[Saat:(\d{2}):(\d{2})\]',
      caseSensitive: false,
    ).firstMatch(job.description);
    if (exact != null) return '${exact.group(1)}:${exact.group(2)}';
    return 'Gün içinde';
  }

  ({int? start, int? end}) _appointmentWindow(TechnicianJob job) {
    final range = RegExp(
      r'\[Aralık:(\d{2}):(\d{2})-(\d{2}):(\d{2})\]',
      caseSensitive: false,
    ).firstMatch(job.description);
    if (range != null) {
      final start = int.parse(range.group(1)!) * 60 + int.parse(range.group(2)!);
      final end = int.parse(range.group(3)!) * 60 + int.parse(range.group(4)!);
      return (start: start, end: end);
    }
    final exact = RegExp(r'\[Saat:(\d{2}):(\d{2})\]', caseSensitive: false)
        .firstMatch(job.description);
    if (exact != null) {
      final minute = int.parse(exact.group(1)!) * 60 + int.parse(exact.group(2)!);
      return (start: minute, end: minute + 20);
    }
    return (start: null, end: null);
  }

  Future<Position?> _readCurrentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum servisini açıp tekrar deneyin.')),
          );
        }
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rota optimizasyonu için konum izni gerekli.')),
          );
        }
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum alınamadı: $error')),
        );
      }
      return null;
    }
  }

  Future<void> _useCurrentLocation(List<TechnicianJob> jobs) async {
    final position = await _readCurrentPosition();
    if (position == null || !mounted) return;
    setState(() {
      _currentPosition = position;
      _startPointLabel = 'Mevcut Konum';
      _startPointLatitude = position.latitude;
      _startPointLongitude = position.longitude;
      _lastMapUrl = null;
      _routeBuilt = false;
    });
    await _syncMap(jobs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Başlangıç noktası mevcut konumunuz olarak ayarlandı.')),
    );
  }

  Future<({double lat, double lon})?> _geocodeAddress(
    String address, {
    String expectedCity = '',
    String expectedDistrict = '',
  }) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;

    final cityKey = _foldAddressText(expectedCity);
    final districtKey = _foldAddressText(expectedDistrict);

    bool candidateMatchesExpectedArea(String label) {
      final folded = _foldAddressText(label);
      if (cityKey.isNotEmpty && !folded.contains(cityKey)) return false;
      // "Merkez" bir cok servis sonucunda ayri bir idari ad olarak gecmeyebilir.
      if (districtKey.isNotEmpty &&
          districtKey != 'merkez' &&
          !folded.contains(districtKey)) {
        return false;
      }
      return true;
    }

    if (_yandexGeocoderKey.trim().isNotEmpty) {
      final client = HttpClient();
      try {
        final uri = Uri.https('geocode-maps.yandex.ru', '/v1/', {
          'apikey': _yandexGeocoderKey,
          'geocode': clean,
          'lang': 'tr_TR',
          'format': 'json',
          'results': '5',
        });
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        if (response.statusCode == 200) {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            final responseMap = decoded['response'];
            final collection = responseMap is Map
                ? responseMap['GeoObjectCollection']
                : null;
            final members = collection is Map ? collection['featureMember'] : null;
            if (members is List) {
              for (final member in members) {
                final geoObject = member is Map ? member['GeoObject'] : null;
                if (geoObject is! Map) continue;
                final meta = geoObject['metaDataProperty'];
                final geocoderMeta = meta is Map ? meta['GeocoderMetaData'] : null;
                final label = geocoderMeta is Map
                    ? '${geocoderMeta['text'] ?? ''} ${geocoderMeta['Address'] ?? ''}'
                    : '';
                if ((cityKey.isNotEmpty || districtKey.isNotEmpty) &&
                    !candidateMatchesExpectedArea(label)) {
                  continue;
                }
                final point = geoObject['Point'];
                final pos = point is Map ? point['pos']?.toString() : null;
                if (pos == null) continue;
                final parts = pos.trim().split(RegExp(r'\s+'));
                if (parts.length < 2) continue;
                final lon = double.tryParse(parts[0]);
                final lat = double.tryParse(parts[1]);
                if (lat != null && lon != null) return (lat: lat, lon: lon);
              }
            }
          }
        }
      } catch (_) {
        // Yandex API anahtari yoksa/asagi dusmusse kontrollu fallback denenir.
      } finally {
        client.close(force: true);
      }
    }

    final client = HttpClient();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': clean,
        'format': 'jsonv2',
        'limit': '8',
        'countrycodes': 'tr',
        'addressdetails': '1',
      });
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'MOTUS-ERP/1.0 technician-route',
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty) return null;

      Map? best;
      var bestScore = -1;
      final cleanKey = _foldAddressText(clean);
      final numberToken = RegExp(r'\bno\s*(\d+[a-z]?)\b')
          .firstMatch(cleanKey)
          ?.group(1);
      final streetToken = RegExp(r'\b(\d+(?:\s+\d+)?)\s+sokak\b')
          .firstMatch(cleanKey)
          ?.group(1)
          ?.replaceAll(' ', '/');

      for (final candidate in decoded) {
        if (candidate is! Map) continue;
        final display = candidate['display_name']?.toString() ?? '';
        if (display.isEmpty) continue;
        if ((cityKey.isNotEmpty || districtKey.isNotEmpty) &&
            !candidateMatchesExpectedArea(display)) {
          continue;
        }

        final folded = _foldAddressText(display);
        var score = 0;
        if (cityKey.isNotEmpty && folded.contains(cityKey)) score += 10;
        if (districtKey.isNotEmpty && folded.contains(districtKey)) score += 12;
        if (numberToken != null && folded.contains(numberToken)) score += 4;
        if (streetToken != null) {
          final flatStreet = streetToken.replaceAll('/', ' ');
          // Sokak numarası uyuşmuyorsa ilçe merkezini veya benzer isimli başka
          // bir yolu kesin konum diye kabul etmiyoruz.
          if (!folded.contains(flatStreet)) continue;
          score += 20;
        }
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      if (best == null) return null;
      final lat = double.tryParse(best['lat']?.toString() ?? '');
      final lon = double.tryParse(best['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;
      return (lat: lat, lon: lon);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  ({double lat, double lon}) _cityCenter(String city) {
    final key = _foldAddressText(city);
    if (key.contains('aydin')) return (lat: 37.8444, lon: 27.8458);
    if (key.contains('manisa')) return (lat: 38.6191, lon: 27.4289);
    if (key.contains('antalya')) return (lat: 36.8969, lon: 30.7133);
    if (key.contains('ankara')) return (lat: 39.9334, lon: 32.8597);
    return (lat: 38.4237, lon: 27.1428);
  }

  Future<({double lat, double lon})?> _showMapPointPicker({
    required String title,
    required double initialLat,
    required double initialLon,
    String subtitle = 'Haritada istediğiniz noktaya tıklayın.',
  }) async {
    if (!Platform.isWindows) return null;
    return showDialog<({double lat, double lon})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MapPointPickerDialog(
        title: title,
        subtitle: subtitle,
        initialLat: initialLat,
        initialLon: initialLon,
      ),
    );
  }

  Future<void> _chooseStartPoint(List<TechnicianJob> jobs) async {
    if (!Platform.isWindows) {
      await _useCurrentLocation(jobs);
      return;
    }

    var initial = jobs.isNotEmpty ? _cityCenter(jobs.first.city) : _cityCenter('İzmir');
    if (_startPointLatitude != null && _startPointLongitude != null) {
      initial = (lat: _startPointLatitude!, lon: _startPointLongitude!);
    } else {
      final position = await _readCurrentPosition();
      if (position != null) {
        initial = (lat: position.latitude, lon: position.longitude);
      }
    }

    if (!mounted) return;
    final picked = await _showMapPointPicker(
      title: 'Başlangıç Noktasını Haritadan Seç',
      subtitle: 'Teknikerin rotaya başlayacağı noktaya haritada bir kez tıklayın.',
      initialLat: initial.lat,
      initialLon: initial.lon,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _currentPosition = null;
      _startPointLabel = 'Haritadan Seçildi';
      _startPointLatitude = picked.lat;
      _startPointLongitude = picked.lon;
      _lastMapUrl = null;
      _routeBuilt = false;
    });
    await _syncMap(jobs);
  }

  Future<void> _pickCustomerMapPoint(TechnicianJob job) async {
    var initial = _cityCenter(job.city);
    if (job.mapsUrl?.startsWith('motus-pin:') == true &&
        job.hasUsableTurkeyCoordinates) {
      initial = (lat: job.latitude!, lon: job.longitude!);
    } else {
      final approx = await _geocodeAddress(
        _canonicalJobAddress(job),
        expectedCity: job.city,
        expectedDistrict: job.district,
      );
      if (approx != null) initial = approx;
    }
    if (!mounted) return;

    final picked = await _showMapPointPicker(
      title: '${job.customerName} - Konumu Düzelt',
      subtitle: 'Müşterinin gerçek bina/kapı noktasına tıklayın. Bundan sonra rota bu pini kullanır.',
      initialLat: initial.lat,
      initialLon: initial.lon,
    );
    if (picked == null || !mounted) return;

    try {
      await ref.read(serviceExecutionRepositoryProvider).saveCustomerMapPoint(
            customerId: job.customerId,
            latitude: picked.lat,
            longitude: picked.lon,
          );
      _jobPointCache[job.id] = picked;
      setState(() {
        _lastMapUrl = null;
        _routeBuilt = false;
        _future = _load();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Müşteri konumu haritadan kaydedildi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum kaydedilemedi: $error')),
        );
      }
    }
  }

  Future<({double lat, double lon})?> _jobPoint(TechnicianJob job) async {
    final cached = _jobPointCache[job.id];
    if (cached != null) return cached;

    // Teknikerin haritadan seçtiği pin en güvenilir kaynaktır.
    if (job.mapsUrl?.startsWith('motus-pin:') == true &&
        job.hasUsableTurkeyCoordinates) {
      final point = (lat: job.latitude!, lon: job.longitude!);
      _jobPointCache[job.id] = point;
      return point;
    }

    // Rota siralamasi icin de once acik adresi yeniden cozmeye calisiyoruz.
    // Boylece veritabaninda kalmis eski/yanlis koordinatlar siralamayi bozmaz.
    final geocoded = await _geocodeAddress(
      _canonicalJobAddress(job),
      expectedCity: job.city,
      expectedDistrict: job.district,
    );
    if (geocoded != null) {
      _jobPointCache[job.id] = geocoded;
      return geocoded;
    }

    // Eski otomatik koordinata körlemesine geri dönmüyoruz. Yanlış eski
    // koordinat rotayı başka ile götürmektense kullanıcıdan haritada pin isteriz.
    return null;
  }

  double _pointDistanceMeters(
    double lat,
    double lon,
    ({double lat, double lon})? point,
  ) {
    if (point == null) return double.infinity;
    return Geolocator.distanceBetween(lat, lon, point.lat, point.lon);
  }

  Future<void> _optimizeRoute(List<TechnicianJob> jobs) async {
    await _buildRouteWithNativeYandex(jobs);
  }

  Future<void> _shareCompletedPdf(TechnicianCompletedDetail detail) async {
    final profile = ref.read(authControllerProvider).profile;
    final technicianName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Tekniker';
    final itemMaps = detail.items
        .map(
          (item) => <String, dynamic>{
            'product_name': item.productName,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
          },
        )
        .toList(growable: false);
    final productTotal = detail.items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final serviceAmount = math.max(0, detail.job.price - productTotal).toDouble();

    final formSettings = await ref.read(companyAppSettingsProvider.future);
    await TechnicianServicePdf.share(
      job: detail.job,
      technicianName: technicianName,
      serviceTypeLabel: _serviceTypeLabel(detail.job.serviceType),
      description: detail.job.description,
      completionNote: detail.job.completionNote,
      items: itemMaps,
      serviceAmount: serviceAmount,
      extraAmount: 0,
      totalAmount: detail.job.price,
      paymentMethodLabel: detail.paymentMethod.isEmpty
          ? '-'
          : _paymentMethodLabel(detail.paymentMethod),
      serviceFormConfig: formSettings.serviceFormConfig,
      formValues: detail.job.formValues,
    );
  }

  Future<void> _showCompletedDetail(TechnicianJob job) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(child: CircularProgressIndicator()),
    );
    TechnicianCompletedDetail? detail;
    try {
      detail = await ref
          .read(serviceExecutionRepositoryProvider)
          .getCompletedJobDetail(job.id);
    } finally {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
    if (!mounted || detail == null) return;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF169B55)),
            const SizedBox(width: 8),
            Expanded(child: Text(detail!.job.customerName)),
          ],
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.job.locationText),
                const SizedBox(height: 8),
                Text('Servis: ${_serviceTypeLabel(detail.job.serviceType)}'),
                if (detail.job.completionNote.trim().isNotEmpty)
                  Text('Yapılan işlem: ${detail.job.completionNote.trim()}'),
                if (detail.job.completedAt != null)
                  Text('Tamamlanma: ${DateFormat('dd.MM.yyyy HH:mm').format(detail.job.completedAt!.toLocal())}'),
                const Divider(height: 24),
                const Text('Kullanılan Ürünler', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (detail.items.isEmpty)
                  const Text('Ürün kaydı yok.')
                else
                  ...detail.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text('${item.productName} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}')),
                            Text(money.format(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      )),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(child: Text('Toplam', style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(money.format(detail.job.price), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                if (detail.collectedAmount > 0)
                  Row(
                    children: [
                      const Expanded(child: Text('Tahsilat')),
                      Text(money.format(detail.collectedAmount)),
                    ],
                  ),
                if (detail.paymentMethod.isNotEmpty)
                  Text('Ödeme: ${_paymentMethodLabel(detail.paymentMethod)}'),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _openCustomerCard(detail!.job);
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Müşteri Kartı'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await _shareCompletedPdf(detail!);
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PDF paylaşılamadı: $error')),
                  );
                }
              }
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF Paylaş'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  String _paymentMethodLabel(String value) => switch (value) {
        'cash' => 'Nakit',
        'card' => 'Kart',
        'transfer' => 'Havale / EFT',
        'open_account' => 'Açık Hesap',
        _ => value,
      };

  Future<void> _showCannotAttendDialog(TechnicianJob job) async {
    String reason = _cannotAttendReasons.first;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.report_problem_outlined, color: Color(0xFFE67E22)),
              SizedBox(width: 10),
              Text('Bu işe gidemiyorum'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.address,
                    style: const TextStyle(color: Color(0xFF65778A)),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(
                      labelText: 'Sebep',
                      prefixIcon: Icon(Icons.rule_outlined),
                    ),
                    items: _cannotAttendReasons
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => reason = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (isteğe bağlı)',
                      hintText: 'Sekreter ve yöneticiye iletilecek not',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bu işlem işi “İptal Edildi” durumuna alır. Kayıt silinmez; seçili gün geçmişinizde kalır ve sebep/not sekreter ile yönetici tarafından görülebilir.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF65778A)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Gidemiyorum Olarak Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    try {
      await ref.read(serviceExecutionRepositoryProvider).reportCannotAttend(
            serviceRequestId: job.id,
            reason: reason,
            note: noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İş “İptal Edildi” olarak kaydedildi. Seçili gün geçmişinizde görünmeye devam edecek.',
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem tamamlanamadı: $error')),
      );
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _rescheduleJob(TechnicianJob job) async {
    final now = DateTime.now();
    final initial = job.plannedDate?.toLocal().isAfter(now) == true
        ? job.plannedDate!.toLocal()
        : now.add(const Duration(hours: 1));
    DateTime selected = initial;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('İşi İleri Saate / Tarihe Ertele'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selected,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: DateTime(2035),
                      locale: const Locale('tr', 'TR'),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selected),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      selected = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(DateFormat('dd.MM.yyyy HH:mm').format(selected)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Erteleme notu (isteğe bağlı)',
                    hintText: 'Örn. müşteri 16:30 sonrası uygun',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'İş sizde kalır. Sadece planlanan tarih/saat değişir ve rota sırası yeniden hesaplanabilir.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF65778A)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.schedule_send_rounded),
              label: const Text('Ertele'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }
    if (!selected.isAfter(DateTime.now())) {
      noteController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yeni tarih/saat ileri bir zaman olmalı.')),
        );
      }
      return;
    }

    try {
      await ref.read(serviceExecutionRepositoryProvider).rescheduleOwnJob(
            serviceRequestId: job.id,
            plannedAt: selected,
            note: noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İş ${DateFormat('dd.MM.yyyy HH:mm').format(selected)} tarihine ertelendi.',
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İş ertelenemedi: $error')),
        );
      }
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _sendJobToSecretary(TechnicianJob job) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sekretere Aktar'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              const Text(
                'Bu iş aktif rotanızdan çıkarılır ancak geçmişinizden silinmez. Sekretere yeniden planlanacak bir taslak gönderilir.',
                style: TextStyle(color: Color(0xFF65778A)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Sekretere not',
                  hintText: 'Örn. müşteri bugün uygun değil, yarına alınsın',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: const Text('Sekretere Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    try {
      final secretary = await ref
          .read(serviceExecutionRepositoryProvider)
          .sendOwnJobToSecretary(
            serviceRequestId: job.id,
            note: noteController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İş $secretary sekretere yeniden planlama için gönderildi.')),
      );
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sekretere aktarılamadı: $error')),
        );
      }
    } finally {
      noteController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ManagementShell(
        role: AppRole.technician,
        title: 'Günlük İşlerim',
        subtitle:
            'Seçtiğiniz günün aktif, tamamlanan ve yapılamayan servislerini; rotanızı ve müşteri detaylarını yönetin.',
        actions: [
          IconButton(tooltip: 'Önceki gün', onPressed: () => _moveDay(-1), icon: const Icon(Icons.chevron_left_rounded)),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
          ),
          IconButton(tooltip: 'Sonraki gün', onPressed: () => _moveDay(1), icon: const Icon(Icons.chevron_right_rounded)),
          OutlinedButton.icon(
            onPressed: _optimizing
                ? null
                : () => _openNativeYandexStartPlanner(),
            icon: const Icon(Icons.location_searching_rounded),
            label: Text(
              _yandexStartText == null
                  ? 'Başlangıcı Yandex’ten Seç'
                  : 'Başlangıç: ${_yandexStartText!}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          FilledButton.icon(
            onPressed: _optimizing
                ? null
                : () async {
                    final data = await _future;
                    await _buildRouteWithNativeYandex(data.active);
                  },
            icon: _optimizing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.route_rounded),
            label: const Text('Rotayı Oluştur'),
          ),
          IconButton(
            onPressed: _refresh,
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        child: FutureBuilder<_TechnicianJobsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('İşler yüklenemedi: ${snapshot.error}'));
            }

            final data = snapshot.data ?? const _TechnicianJobsData();
            final jobs = data.active;
            final completedJobs = data.completed;
            final failedJobs = data.failed;
            if (_selectedJob == null && jobs.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedJob == null) {
                  setState(() => _selectedJob = jobs.first);
                }
              });
            }
            WidgetsBinding.instance.addPostFrameCallback((_) => _syncMap(jobs));

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 1100) {
                  return ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _launchYandex(jobs),
                          icon: const Icon(Icons.map_outlined),
                          label: Text('Haritayı Aç (${jobs.length} iş)'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...jobs.asMap().entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _jobCard(
                                entry.value,
                                entry.key,
                                compact: true,
                              ),
                            ),
                          ),
                      if (completedJobs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('Tamamlanan (${completedJobs.length})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 8),
                        ...completedJobs.map(_completedJobCard),
                      ],
                      if (failedJobs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Yapılamayan / İptal (${failedJobs.length})',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        ...failedJobs.map(_failedJobCard),
                      ],
                    ],
                  );
                }

                // ManagementShell bu alanı zaten Expanded ile sınırlar. SizedBox
                // kullanmak WebView/Column kombinasyonunun sonsuz yükseklik üretmesini
                // ve debug modundaki dev sarı-siyah overflow şeridini engeller.
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 350, child: _jobsList(jobs, completedJobs, failedJobs)),
                              const SizedBox(width: 12),
                              Expanded(flex: 7, child: _mapPanel(jobs)),
                              const SizedBox(width: 12),
                              SizedBox(width: 330, child: _detailPanel()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _summary(jobs, completedJobs, failedJobs),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

  Widget _jobsList(
    List<TechnicianJob> jobs,
    List<TechnicianJob> completedJobs,
    List<TechnicianJob> failedJobs,
  ) => Container(
        decoration: _panelDecoration(),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.today_outlined, color: Color(0xFF10B8C4)),
                  SizedBox(width: 8),
                  Text(
                    'Seçili Gün İşlerim',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  if (jobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Bu tarihte aktif servis yok.'),
                    )
                  else
                    ...jobs.asMap().entries.map(
                      (entry) => Column(
                        children: [
                          _jobCard(entry.value, entry.key, compact: false),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Text(
                      'Tamamlanan (${completedJobs.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (completedJobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('Bu tarihte tamamlanan servis yok.'),
                    )
                  else
                    ...completedJobs.map(_completedJobCard),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                    child: Text(
                      'Yapılamayan / İptal (${failedJobs.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (failedJobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Text('Bu tarihte yapılamayan veya iptal edilen servis yok.'),
                    )
                  else
                    ...failedJobs.map(_failedJobCard),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _jobCard(
    TechnicianJob job,
    int index, {
    required bool compact,
  }) {
    final selected = _selectedJob?.id == job.id;
    return Material(
      color: selected ? const Color(0xFFE7F8FA) : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedJob = job),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFF10B8C4),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      job.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (index == 0) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F8EF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Sıradaki',
                        style: TextStyle(
                          color: Color(0xFF169B55),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    _timeLabel(job),
                    style: const TextStyle(
                      color: Color(0xFF0A99A7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                job.address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF65778A), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _serviceTypeLabel(job.serviceType),
                style: const TextStyle(
                  color: Color(0xFF334E68),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (compact) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: job.phone.isEmpty
                          ? null
                          : () => _launchPhone(job.phone),
                      icon: const Icon(Icons.phone_outlined),
                      label: const Text('Ara'),
                    ),
                    OutlinedButton.icon(
                      onPressed: job.phone.isEmpty
                          ? null
                          : () => _sendOnMyWay(job.phone, job.customerName),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Geliyorum'),
                    ),
                    OutlinedButton.icon(
                      onPressed: job.status == 'assigned' ? () => _rescheduleJob(job) : null,
                      icon: const Icon(Icons.schedule_rounded),
                      label: const Text('Ertele'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showCannotAttendDialog(job),
                      icon: const Icon(Icons.report_problem_outlined),
                      label: const Text('Gidemiyorum'),
                    ),
                    FilledButton(
                      onPressed: () => _openJob(job),
                      child: const Text('İşi Aç'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _completedJobCard(TechnicianJob job) => InkWell(
        onTap: () => _showCompletedDetail(job),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 15,
                backgroundColor: Color(0xFFE5F8EF),
                child: Icon(Icons.check_rounded, size: 18, color: Color(0xFF169B55)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(_serviceTypeLabel(job.serviceType), style: const TextStyle(fontSize: 12, color: Color(0xFF65778A))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      );

  Widget _failedJobCard(TechnicianJob job) {
    final cancelled = job.status == 'cancelled';
    final transferred = job.status == 'deferred';
    final accent = transferred
        ? const Color(0xFF7C5CE5)
        : cancelled
            ? const Color(0xFFE75454)
            : const Color(0xFFE67E22);
    final background = transferred
        ? const Color(0xFFF3EFFF)
        : cancelled
            ? const Color(0xFFFFF1F1)
            : const Color(0xFFFFF5E8);
    final label = transferred
        ? 'Sekretere Aktarıldı'
        : cancelled
            ? 'İptal Edildi'
            : 'Tamamlanamadı';
    return InkWell(
      onTap: () => _showFailedDetail(job),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: background,
              child: Icon(
                transferred
                    ? Icons.forward_to_inbox_outlined
                    : cancelled
                        ? Icons.cancel_outlined
                        : Icons.report_problem_outlined,
                size: 18,
                color: accent,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${_serviceTypeLabel(job.serviceType)} • $label',
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Future<void> _showFailedDetail(TechnicianJob job) async {
    final cancelled = job.status == 'cancelled';
    final transferred = job.status == 'deferred';
    final reason = cancelled
        ? (job.technicianUnavailableReason.trim().isNotEmpty
            ? job.technicianUnavailableReason.trim()
            : job.cancellationReason.trim())
        : job.completionNote.trim();
    final note = job.technicianUnavailableNote.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              transferred
                  ? Icons.forward_to_inbox_outlined
                  : cancelled
                      ? Icons.cancel_outlined
                      : Icons.report_problem_outlined,
              color: transferred
                  ? const Color(0xFF7C5CE5)
                  : cancelled
                      ? const Color(0xFFE75454)
                      : const Color(0xFFE67E22),
            ),
            const SizedBox(width: 10),
            Text(transferred
                ? 'Sekretere Aktarılan İş'
                : cancelled
                    ? 'İptal Edilen İş'
                    : 'Tamamlanamayan İş'),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.customerName, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(job.locationText, style: const TextStyle(color: Color(0xFF65778A))),
              const SizedBox(height: 12),
              Text('Servis: ${_serviceTypeLabel(job.serviceType)}'),
              if (job.plannedDate != null)
                Text(
                  'Planlama: ${DateFormat('dd.MM.yyyy HH:mm').format(job.plannedDate!.toLocal())}',
                ),
              const Divider(height: 26),
              const Text('Sonuç / Sebep', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(reason.isEmpty ? 'Sebep belirtilmedi.' : reason),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Not: $note'),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _openCustomerCard(job);
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Müşteri Kartı'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _mapPanel(List<TechnicianJob> jobs) => Container(
        decoration: _panelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFF10B8C4)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Yandex Harita',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _launchYandex(jobs),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Yandex’te Aç'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Platform.isWindows && _mapReady
                  ? Webview(_mapController)
                  : Center(
                      child: FilledButton.icon(
                        onPressed: () => _launchYandex(jobs),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Haritayı Aç'),
                      ),
                    ),
            ),
          ],
        ),
      );

  Widget _detailPanel() {
    final job = _selectedJob;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: job == null
          ? const Center(child: Text('Soldan bir iş seçin.'))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.customerName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          job.locationText,
                          style: const TextStyle(color: Color(0xFF65778A)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Planlama: ${_timeLabel(job)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (job.plannedDate != null)
                          Text(
                            DateFormat('dd.MM.yyyy')
                                .format(job.plannedDate!.toLocal()),
                          ),
                        const Divider(height: 28),
                        Text(
                          _serviceTypeLabel(job.serviceType),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (job.plannedProductName.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${job.plannedProductName} × ${job.plannedQuantity.toStringAsFixed(job.plannedQuantity % 1 == 0 ? 0 : 1)}',
                          ),
                          Text(
                            NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
                                .format(job.price),
                            style: const TextStyle(
                              color: Color(0xFF0A99A7),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                        if (job.description
                            .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')
                            .trim()
                            .isNotEmpty) ...[
                          const Divider(height: 28),
                          const Text(
                            'Not',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            job.description.replaceAll(
                              RegExp(r'^\[[^\]]+\]\s*'),
                              '',
                            ),
                          ),
                        ],
                        const Divider(height: 28),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _openCustomerCard(job),
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text('Müşteri Kartı'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _editCustomer(job),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Bilgileri Düzenle'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openJob(job),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('İşe Başla'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: job.phone.isEmpty
                            ? null
                            : () => _launchPhone(job.phone),
                        icon: const Icon(Icons.phone_outlined),
                        label: const Text('Ara'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: job.phone.isEmpty
                            ? null
                            : () => _sendOnMyWay(job.phone, job.customerName),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Geliyorum'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: job.mapQuery.isEmpty
                            ? null
                            : () => _launchMap(job),
                        icon: const Icon(Icons.navigation_outlined),
                        label: const Text('Harita'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD35D17),
                        ),
                        onPressed: () => _showCannotAttendDialog(job),
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('Gidemiyorum'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: job.status == 'assigned'
                        ? () => _rescheduleJob(job)
                        : null,
                    icon: const Icon(Icons.schedule_rounded),
                    label: const Text('Ertele'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summary(
    List<TechnicianJob> jobs,
    List<TechnicianJob> completedJobs,
    List<TechnicianJob> failedJobs,
  ) {
    final done = completedJobs.length;
    final progress = jobs.where((j) => j.status == 'in_progress').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: _panelDecoration(),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 24,
        runSpacing: 8,
        children: [
          Text(
            'Toplam İş: ${jobs.length + completedJobs.length + failedJobs.length}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Tamamlanan: $done',
            style: const TextStyle(
              color: Color(0xFF169B55),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Devam Eden: $progress',
            style: const TextStyle(
              color: Color(0xFF2979FF),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Kalan: ${jobs.length}',
            style: const TextStyle(
              color: Color(0xFFF59E0B),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Yapılamayan / İptal: ${failedJobs.length}',
            style: const TextStyle(
              color: Color(0xFFE67E22),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAF0)),
      );
}


class _MapPointPickerDialog extends StatefulWidget {
  const _MapPointPickerDialog({
    required this.title,
    required this.subtitle,
    required this.initialLat,
    required this.initialLon,
  });

  final String title;
  final String subtitle;
  final double initialLat;
  final double initialLon;

  @override
  State<_MapPointPickerDialog> createState() => _MapPointPickerDialogState();
}

class _MapPointPickerDialogState extends State<_MapPointPickerDialog> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<dynamic>? _messageSub;
  bool _ready = false;
  double? _lat;
  double? _lon;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      _messageSub = _controller.webMessage.listen(_handleMessage);
      await _controller.loadStringContent(_html());
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  void _handleMessage(dynamic message) {
    dynamic value = message;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {}
    }
    if (value is! Map) return;
    final lat = value['lat'];
    final lon = value['lon'];
    if (lat is num && lon is num && mounted) {
      setState(() {
        _lat = lat.toDouble();
        _lon = lon.toDouble();
      });
    }
  }

  String _html() => '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
<style>
html,body,#map{height:100%;margin:0;padding:0;background:#eef3f7}
.tip{position:absolute;z-index:1000;top:12px;left:50%;transform:translateX(-50%);background:white;padding:9px 14px;border-radius:12px;box-shadow:0 2px 12px #0003;font:600 13px Arial;color:#183247}
</style>
</head>
<body>
<div id="map"></div><div class="tip">Haritada gerçek noktaya tıklayın</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const map=L.map('map').setView([${widget.initialLat},${widget.initialLon}],15);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap'}).addTo(map);
let marker=null;
function selectPoint(lat,lon){
 if(marker) marker.setLatLng([lat,lon]); else marker=L.marker([lat,lon]).addTo(map);
 window.chrome.webview.postMessage({lat:lat,lon:lon});
}
map.on('click', e=>selectPoint(e.latlng.lat,e.latlng.lng));
</script>
</body>
</html>
''';

  @override
  void dispose() {
    _messageSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 920,
        height: 610,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subtitle),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _ready
                    ? Webview(_controller)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lat == null
                  ? 'Henüz nokta seçilmedi.'
                  : 'Seçilen nokta: ${_lat!.toStringAsFixed(6)}, ${_lon!.toStringAsFixed(6)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _lat == null || _lon == null
              ? null
              : () => Navigator.of(context).pop((lat: _lat!, lon: _lon!)),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Bu Noktayı Kullan'),
        ),
      ],
    );
  }
}

class _TechnicianJobsData {
  const _TechnicianJobsData({
    this.active = const <TechnicianJob>[],
    this.completed = const <TechnicianJob>[],
    this.failed = const <TechnicianJob>[],
  });
  final List<TechnicianJob> active;
  final List<TechnicianJob> completed;
  final List<TechnicianJob> failed;
}

String _serviceTypeLabel(String value) => switch (value) {
      'new_installation' => 'Yeni Kurulum',
      'filter_change' => 'Filtre Değişimi',
      'fault' => 'Arıza',
      _ => 'Servis',
    };
