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
  bool _optimizing = false;

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
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initMap() async {
    if (!Platform.isWindows) return;
    try {
      await _mapController.initialize();
      if (mounted) setState(() => _mapReady = true);
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
    setState(() {
      _selectedDate = picked;
      _selectedJob = null;
      _lastMapUrl = null;
      _future = _load();
    });
  }

  void _moveDay(int days) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );
      _selectedJob = null;
      _lastMapUrl = null;
      _future = _load();
    });
  }

  void _refresh() {
    setState(() {
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

  String _routeUrl(List<TechnicianJob> jobs) {
    final addresses = jobs
        .where((j) => j.mapQuery.trim().isNotEmpty)
        .map((j) => j.mapQuery.trim())
        .take(10)
        .toList(growable: false);
    if (addresses.isEmpty) {
      return 'https://yandex.com.tr/maps/11505/izmir/';
    }

    final manualStart = _startPointLabel?.trim() ?? '';
    final points = <String>[
      if (manualStart.isNotEmpty)
        manualStart
      else if (_currentPosition != null)
        '${_currentPosition!.latitude.toStringAsFixed(6)},${_currentPosition!.longitude.toStringAsFixed(6)}',
      ...addresses,
    ];

    return Uri.https(
      'yandex.com.tr',
      '/maps/',
      {'mode': 'routes', 'rtext': points.join('~'), 'rtt': 'auto'},
    ).toString();
  }

  Future<void> _syncMap(List<TechnicianJob> jobs) async {
    if (!_mapReady || !Platform.isWindows) return;
    final url = _routeUrl(jobs);
    if (_lastMapUrl == url) return;
    _lastMapUrl = url;
    try {
      await _mapController.loadUrl(url);
    } catch (_) {}
  }

  Future<void> _launchYandex(List<TechnicianJob> jobs) async {
    await launchUrl(
      Uri.parse(_routeUrl(jobs)),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _launchMap(TechnicianJob job) async {
    if (job.mapQuery.isEmpty) return;
    await launchUrl(
      Uri.https('yandex.com.tr', '/maps/', {
        'mode': 'search',
        'text': job.mapQuery,
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
    });
    await _syncMap(jobs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Başlangıç noktası mevcut konumunuz olarak ayarlandı.')),
    );
  }

  Future<({double lat, double lon})?> _geocodeAddress(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;

    if (_yandexGeocoderKey.trim().isNotEmpty) {
      final client = HttpClient();
      try {
        final uri = Uri.https('geocode-maps.yandex.ru', '/v1/', {
          'apikey': _yandexGeocoderKey,
          'geocode': clean,
          'lang': 'tr_TR',
          'format': 'json',
          'results': '1',
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
            if (members is List && members.isNotEmpty) {
              final first = members.first;
              final geoObject = first is Map ? first['GeoObject'] : null;
              final point = geoObject is Map ? geoObject['Point'] : null;
              final pos = point is Map ? point['pos']?.toString() : null;
              if (pos != null) {
                final parts = pos.trim().split(RegExp(r'\s+'));
                if (parts.length >= 2) {
                  final lon = double.tryParse(parts[0]);
                  final lat = double.tryParse(parts[1]);
                  if (lat != null && lon != null) return (lat: lat, lon: lon);
                }
              }
            }
          }
        }
      } catch (_) {
        // Yandex başarısız olursa Türkiye fallback'i denenir.
      } finally {
        client.close(force: true);
      }
    }

    final client = HttpClient();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': clean,
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'tr',
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
      if (decoded is! List || decoded.isEmpty || decoded.first is! Map) {
        return null;
      }
      final first = decoded.first as Map;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) return null;
      return (lat: lat, lon: lon);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _chooseStartPoint(List<TechnicianJob> jobs) async {
    final controller = TextEditingController(
      text: (_startPointLabel == null || _startPointLabel == 'Mevcut Konum')
          ? ''
          : _startPointLabel,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Başlangıç Noktası Seç'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tekniker rotaya nereden başlayacaksa adresi yazın. '
                'Rota bu noktadan başlayarak sıralanır ve iş listesi de aynı sıraya geçer.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(dialogContext).pop(value.trim());
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Başlangıç adresi',
                  hintText: 'Örn: 1921 Sokak No:19/A Bayraklı, İzmir',
                  prefixIcon: Icon(Icons.trip_origin_rounded),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop('__CURRENT__'),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Mevcut Konumumu Kullan'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            icon: const Icon(Icons.check_rounded),
            label: const Text('Başlangıcı Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    if (result == '__CURRENT__') {
      await _useCurrentLocation(jobs);
      return;
    }

    setState(() => _optimizing = true);
    final point = await _geocodeAddress('$result, Türkiye');
    if (!mounted) return;
    if (point == null) {
      setState(() => _optimizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Başlangıç adresi bulunamadı. İlçe ve şehir ile daha açık yazıp tekrar deneyin.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _currentPosition = null;
      _startPointLabel = result;
      _startPointLatitude = point.lat;
      _startPointLongitude = point.lon;
      _lastMapUrl = null;
      _optimizing = false;
    });
    await _syncMap(jobs);
  }

  Future<({double lat, double lon})?> _jobPoint(TechnicianJob job) async {
    final cached = _jobPointCache[job.id];
    if (cached != null) return cached;

    if (job.hasUsableTurkeyCoordinates) {
      final point = (lat: job.latitude!, lon: job.longitude!);
      _jobPointCache[job.id] = point;
      return point;
    }

    final geocoded = await _geocodeAddress(job.mapQuery);
    if (geocoded != null) _jobPointCache[job.id] = geocoded;
    return geocoded;
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
    if (jobs.length < 2 || _optimizing) return;

    if (_startPointLatitude == null || _startPointLongitude == null) {
      await _chooseStartPoint(jobs);
      if (!mounted ||
          _startPointLatitude == null ||
          _startPointLongitude == null) {
        return;
      }
    }

    setState(() => _optimizing = true);
    try {
      final points = <String, ({double lat, double lon})?>{};
      for (final job in jobs) {
        points[job.id] = await _jobPoint(job);
      }

      final remaining = List<TechnicianJob>.from(jobs);
      final ordered = <TechnicianJob>[];
      var lat = _startPointLatitude!;
      var lon = _startPointLongitude!;
      final today = DateTime.now();
      var cursorMinutes = _sameDay(today, _selectedDate)
          ? today.hour * 60 + today.minute
          : 8 * 60;

      while (remaining.isNotEmpty) {
        final scheduled = remaining
            .where((job) => _appointmentWindow(job).start != null)
            .toList(growable: false)
          ..sort(
            (a, b) => _appointmentWindow(a)
                .start!
                .compareTo(_appointmentWindow(b).start!),
          );

        TechnicianJob? chosen;
        if (scheduled.isNotEmpty) {
          final next = scheduled.first;
          final window = _appointmentWindow(next);
          final distance = _pointDistanceMeters(lat, lon, points[next.id]);
          final travelMinutes = distance.isFinite
              ? math.max(5, (distance / 1000 / 35 * 60).round())
              : 45;
          if ((window.start ?? 9999) <=
              cursorMinutes + travelMinutes + 45) {
            chosen = next;
          }
        }

        if (chosen == null) {
          final dayJobs = remaining
              .where((job) => _appointmentWindow(job).start == null)
              .toList(growable: false);
          final pool = dayJobs.isNotEmpty ? dayJobs : remaining;
          pool.sort(
            (a, b) => _pointDistanceMeters(lat, lon, points[a.id])
                .compareTo(_pointDistanceMeters(lat, lon, points[b.id])),
          );
          chosen = pool.first;
        }

        remaining.remove(chosen);
        ordered.add(chosen);
        final point = points[chosen.id];
        final distance = _pointDistanceMeters(lat, lon, point);
        if (distance.isFinite && point != null) {
          cursorMinutes +=
              math.max(5, (distance / 1000 / 35 * 60).round()) + 30;
          lat = point.lat;
          lon = point.lon;
        } else {
          cursorMinutes += 45;
        }

        final window = _appointmentWindow(chosen);
        if (window.start != null && cursorMinutes < window.start!) {
          cursorMinutes = window.start! + 30;
        }
      }

      await ref.read(serviceExecutionRepositoryProvider).saveTechnicianRouteOrder(
            ordered.map((e) => e.id).toList(growable: false),
          );
      if (!mounted) return;
      setState(() {
        _lastMapUrl = null;
        _selectedJob = ordered.isEmpty ? null : ordered.first;
        _future = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rota ${_startPointLabel ?? 'başlangıç noktası'} konumundan oluşturuldu. '
            'İş listesi rota sırasına göre güncellendi.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
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
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/technician/customers/${detail!.job.customerId}');
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
                : () async {
                    final data = await _future;
                    await _chooseStartPoint(data.active);
                  },
            icon: const Icon(Icons.trip_origin_rounded),
            label: Text(
              _startPointLabel == null
                  ? 'Başlangıç Noktası'
                  : 'Başlangıç: ${_startPointLabel!}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          FilledButton.icon(
            onPressed: _optimizing
                ? null
                : () async {
                    final data = await _future;
                    await _optimizeRoute(data.active);
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
            onPressed: () {
              Navigator.pop(dialogContext);
              context.push('/technician/customers/${job.customerId}');
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
                              onPressed: () => context.push('/technician/customers/${job.customerId}'),
                              icon: const Icon(Icons.badge_outlined),
                              label: const Text('Müşteri Kartı'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.push('/technician/customers/${job.customerId}/edit'),
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
