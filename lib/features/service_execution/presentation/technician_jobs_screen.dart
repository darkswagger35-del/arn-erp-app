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
  List<String> _localRouteOrderIds = const <String>[];
  bool _routeBuilt = false;
  bool _optimizing = false;
  bool _syncingYandexOrder = false;
  Timer? _yandexRouteSyncTimer;
  StreamSubscription<String>? _mapUrlSub;
  String? _yandexStartText;
  Set<String> _invalidAddressJobIds = <String>{};
  Map<String, String> _invalidAddressResolvedText = <String, String>{};


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
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
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
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
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
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
      _future = _load();
    });
  }

  Future<void> _openCustomerCard(TechnicianJob job) async {
    await context.push('/technician/customers/${job.customerId}');
    if (!mounted) return;
    // Karttan/düzenlemeden dönünce adres/telefon değişmiş olabilir.
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _selectedJob = null;
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
      _future = _load();
    });
  }

  Future<void> _editCustomer(TechnicianJob job) async {
    await context.push('/technician/customers/${job.customerId}/edit');
    if (!mounted) return;
    // Yanlış adres düzeltildiyse rota yeniden doğrulansın.
    _yandexRouteSyncTimer?.cancel();
    setState(() {
      _lastMapUrl = null;
      _routeBuilt = false;
      _yandexStartText = null;
      _selectedJob = null;
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
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
    if (raw.isEmpty) return '';

    // Yandex'e müşterinin sokak/cadde metnini DEĞİŞTİRMEDEN gönderiyoruz.
    // Sadece rota için anlam taşımayan kat/daire bilgisini çıkarıyoruz.
    // Örnek: "7467/1 sok No:1 k:2 d:4" ->
    // "7467/1 sok No:1, Karşıyaka, İzmir, Türkiye".
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

    final parts = <String>[
      raw,
      job.district.trim(),
      job.city.trim(),
      'Türkiye',
    ].where((value) => value.isNotEmpty).toList(growable: false);

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
    // Koordinat, yaklaşık nokta, ilçe merkezi veya başka sokak fallback'i YOK.
    // Veritabanındaki açık adres neyse Yandex'e o gider.
    return _canonicalJobAddress(job);
  }

  bool _routeValueMatchesJob(TechnicianJob job, String yandexValue) {
    final expectedSignature = _jobRouteSignature(job);
    if (expectedSignature.isNotEmpty) {
      // Sayısal sokaklarda hem sokak hem kapı numarası birebir uyuşmalı.
      // 7467/1 -> 1731 veya 542 No:44 -> yalnızca mahalle gibi sonuçlar
      // kesinlikle kabul edilmez.
      return _yandexValueSignature(yandexValue) == expectedSignature;
    }

    final expected = _foldAddressText(job.address);
    final actual = _foldAddressText(yandexValue);
    if (expected.isEmpty || actual.isEmpty) return false;

    final houseNo = RegExp(r'\bno\s*(\d+[a-z]?)\b')
        .firstMatch(expected)
        ?.group(1);
    if (houseNo != null && !actual.split(' ').contains(houseNo)) {
      return false;
    }

    const ignored = <String>{
      'mah', 'mahalle', 'mahallesi', 'sok', 'sokak', 'sk', 'cad', 'cadde',
      'caddesi', 'cd', 'bulvar', 'bulvari', 'blv', 'no', 'kat', 'daire',
      'apartmani', 'apartman', 'apt', 'blok', 'turkiye',
    };
    final words = expected
        .split(' ')
        .where((w) => w.length >= 4 && !ignored.contains(w) && !RegExp(r'^\d+$').hasMatch(w))
        .toList(growable: false);
    if (words.isEmpty) return false;

    // İsme dayalı cadde/sokaklarda en az iki ayırt edici kelime varsa ikisini,
    // tek kelime varsa o kelimeyi Yandex sonucunda görmek zorundayız.
    final requiredCount = words.length >= 2 ? 2 : 1;
    var matched = 0;
    for (final word in words) {
      if (actual.split(' ').contains(word)) matched++;
    }
    return matched >= requiredCount;
  }

  Future<List<String>?> _waitForResolvedRouteValues({
    required int jobCount,
    required String startText,
  }) async {
    // Yandex önce gönderdiğimiz ham metni inputlara koyup birkaç yüz ms sonra
    // kendi bulduğu adresle değiştirebiliyor. Bu yüzden ilk görünen değeri
    // kabul etmiyoruz; alanların en az 3 tur sabit kalmasını bekliyoruz.
    List<String>? lastValues;
    var stableRounds = 0;

    for (var attempt = 0; attempt < 22; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final inputs = await _readYandexInputs();
      if (inputs.isEmpty) continue;

      final values = <String>[];
      var skippedStartByMetadata = false;
      for (final input in inputs) {
        final value = (input['value'] ?? '').trim();
        if (value.isEmpty) continue;
        final meta = _foldAddressText(
          '${input['placeholder'] ?? ''} ${input['aria'] ?? ''}',
        );
        if (!skippedStartByMetadata && meta.contains('nereden')) {
          skippedStartByMetadata = true;
          continue;
        }
        values.add(value);
      }

      if (!skippedStartByMetadata) {
        final foldedStart = _foldAddressText(startText);
        final startIndex = values.indexWhere(
          (value) => _foldAddressText(value) == foldedStart,
        );
        if (startIndex >= 0) {
          values.removeAt(startIndex);
        } else if (values.length == jobCount + 1) {
          values.removeAt(0);
        }
      }

      if (values.length < jobCount) {
        stableRounds = 0;
        lastValues = null;
        continue;
      }

      final current = values.take(jobCount).toList(growable: false);
      final sameAsLast = lastValues != null &&
          lastValues!.length == current.length &&
          List.generate(current.length, (i) => lastValues![i] == current[i])
              .every((e) => e);
      if (sameAsLast) {
        stableRounds++;
      } else {
        lastValues = current;
        stableRounds = 1;
      }

      // En az ~1.7 sn bekle ve sonrasında 3 ardışık okumada aynı sonucu gör.
      if (attempt >= 4 && stableRounds >= 3) return current;
    }
    return null;
  }

  Future<List<TechnicianJob>?> _validateResolvedAddresses(
    List<TechnicianJob> jobs,
    String startText,
  ) async {
    final values = await _waitForResolvedRouteValues(
      jobCount: jobs.length,
      startText: startText,
    );
    if (values == null) return null;

    final invalid = <TechnicianJob>[];
    final resolvedText = <String, String>{};
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      final value = values[i];
      if (!_routeValueMatchesJob(job, value)) {
        invalid.add(job);
        resolvedText[job.id] = value;
      }
    }

    if (mounted) {
      setState(() {
        _invalidAddressJobIds = invalid.map((e) => e.id).toSet();
        _invalidAddressResolvedText = resolvedText;
      });
    }
    return invalid;
  }

  String _commonRouteCity(List<TechnicianJob> jobs) {
    final cities = jobs
        .map((job) => job.city.trim())
        .where((city) => city.isNotEmpty)
        .toSet();
    return cities.length == 1 ? cities.first : '';
  }

  String _startPointWithCityContext(
    String start,
    List<TechnicianJob> jobs,
  ) {
    final raw = start.trim();
    if (raw.isEmpty) return raw;

    final city = _commonRouteCity(jobs);
    if (city.isEmpty) return raw;

    final foldedStart = _foldAddressText(raw);
    final foldedCity = _foldAddressText(city);
    if (foldedCity.isNotEmpty && foldedStart.contains(foldedCity)) {
      return raw;
    }

    return '$raw, $city, Türkiye';
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

  String _routeUrl(List<TechnicianJob> jobs) {
    final points = jobs
        .map(_nativeRoutePointForJob)
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    return _nativeRoutePlannerUrl(rtext: points.join('~'));
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
    final raw = job.address.toLowerCase();
    final streetMatch = RegExp(
      r'(^|[^0-9])(\d{2,5}(?:\s*/\s*\d+)?)\s*\.?\s*(?:sk|sok|sokak)\b',
      caseSensitive: false,
    ).firstMatch(raw);
    final street = streetMatch
        ?.group(2)
        ?.replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'/+'), '/');
    final explicitNo = RegExp(
      r'\bno\s*[:.]?\s*(\d+[a-z]?)\b',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    if (street == null || street.isEmpty) return '';
    return '$street#${explicitNo ?? ''}';
  }

  String _yandexValueSignature(String value) {
    final raw = value.toLowerCase();
    final streetMatch = RegExp(
      r'(^|[^0-9])(\d{2,5}(?:\s*/\s*\d+)?)\s*\.?\s*(?:sk|sok|sokak)\b',
      caseSensitive: false,
    ).firstMatch(raw);
    final street = streetMatch
        ?.group(2)
        ?.replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'/+'), '/');
    if (streetMatch == null || street == null || street.isEmpty) return '';

    // Yandex aynı doğru adresi iki biçimde gösterebiliyor:
    //   "924/1 Sok., 13"  veya  "13, 924/1 Sok."
    // Sokak numarasını slash'ı KORUYARAK okuyoruz; böylece
    // "44, 542 Sok." içindeki 44 kapı numarası yanlışlıkla sokağın
    // parçası sayılmıyor.
    final explicitNo = RegExp(
      r'\bno\s*[:.]?\s*(\d+[a-z]?)\b',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);

    final afterText = raw.substring(streetMatch.end);
    final afterStreet = RegExp(
      r'^[\s,.;:-]*(\d+[a-z]?)\b',
      caseSensitive: false,
    ).firstMatch(afterText)?.group(1);

    final beforeText = raw.substring(0, streetMatch.start).trimRight();
    final beforeStreet = RegExp(
      r'(\d+[a-z]?)\s*[,.;:-]*\s*$',
      caseSensitive: false,
    ).firstMatch(beforeText)?.group(1);

    final houseNo = explicitNo ?? afterStreet ?? beforeStreet;
    return '$street#${houseNo ?? ''}';
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
    if (!_routeBuilt || jobs.length < 2 || !mounted || _syncingYandexOrder) {
      return;
    }

    _syncingYandexOrder = true;
    try {
      final inputs = await _readYandexInputs();
      if (inputs.isEmpty) return;

      // Yandex optimize işleminden sonra rota alanlarının ekrandaki sırası
      // değişiyor. Burada SAAT / plannedDate kullanılmaz; yalnızca Yandex'in
      // gösterdiği durak sırası uygulamaya aktarılır.
      final inputValues = inputs
          .map((e) => (e['value'] ?? '').trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: true);

      // İlk dolu rota alanı başlangıç noktasıdır. Başlangıcı müşteriyle
      // karıştırmamak için listeden yalnızca ilk eşleşmesini çıkar.
      final startText = (await _readYandexStartText())?.trim() ?? '';
      if (startText.isNotEmpty) {
        final foldedStart = _foldAddressText(startText);
        final startIndex = inputValues.indexWhere(
          (value) => _foldAddressText(value) == foldedStart,
        );
        if (startIndex >= 0) inputValues.removeAt(startIndex);
      }

      // Önce ekrandaki gerçek (optimize edilmiş) alanları kullan. rtext sadece
      // Yandex bazı alanları input olarak sunmazsa yedek kaynak olsun.
      final candidateValues = <String>[
        ...inputValues,
        ...await _readYandexRtextValues(),
      ];

      TechnicianJob? strictAddressMatch(
        String value,
        Set<String> usedIds,
      ) {
        final matches = jobs.where((job) {
          return !usedIds.contains(job.id) && _routeValueMatchesJob(job, value);
        }).toList(growable: false);
        return matches.length == 1 ? matches.first : null;
      }

      final ordered = <TechnicianJob>[];
      final usedIds = <String>{};
      for (final value in candidateValues) {
        final job = strictAddressMatch(value, usedIds);
        if (job == null) continue;
        ordered.add(job);
        usedIds.add(job.id);
        if (ordered.length == jobs.length) break;
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
        // Kalıcı kayıt başarısız olsa bile ekrandaki sıra Yandex ile eşitlensin.
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Yandex optimize sırası uygulamaya aktarıldı.'),
        ),
      );
    } finally {
      _syncingYandexOrder = false;
    }
  }

  void _startYandexOrderSync(List<TechnicianJob> jobs) {
    _yandexRouteSyncTimer?.cancel();
    _yandexRouteSyncTimer = Timer.periodic(
      const Duration(seconds: 1),
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

  Future<List<String>> _readYandexRouteInputValues() async {
    if (!_mapReady || !Platform.isWindows) return const [];
    try {
      final value = await _mapController.executeScript(r'''
(() => {
  const fold = (v) => (v || '')
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i').replace(/ş/g, 's').replace(/ğ/g, 'g')
    .replace(/ü/g, 'u').replace(/ö/g, 'o').replace(/ç/g, 'c');
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const st = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  return Array.from(document.querySelectorAll('input'))
    .filter(visible)
    .filter((e) => {
      const meta = fold(`${e.getAttribute('placeholder') || ''} ${e.getAttribute('aria-label') || ''}`);
      if (meta.includes('rota uzerinde ara')) return false;
      if (meta.includes('arama ve yer secimi')) return false;
      if (meta.includes('haritada ara')) return false;
      return true;
    })
    .map((e) => (e.value || '').trim());
})()
''');
      dynamic decoded = value;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }
      if (decoded is List) {
        return decoded.map((e) => e?.toString() ?? '').toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> _clickYandexAddRoutePoint() async {
    if (!_mapReady || !Platform.isWindows) return false;
    try {
      final result = await _mapController.executeScript(r'''
(() => {
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const st = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  const nodes = Array.from(document.querySelectorAll('button, a, [role="button"], div, span'));
  const target = nodes
    .filter(visible)
    .filter((e) => (e.textContent || '').replace(/\s+/g, ' ').trim().toLocaleLowerCase('tr-TR') === 'ekle')
    .sort((a, b) => (a.textContent || '').length - (b.textContent || '').length)[0];
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

  Future<bool> _ensureYandexRouteInput(int index) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final values = await _readYandexRouteInputValues();
      if (values.length > index) return true;
      await _clickYandexAddRoutePoint();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<bool> _fillYandexRouteInput(int index, String text) async {
    if (!_mapReady || !Platform.isWindows) return false;
    if (!await _ensureYandexRouteInput(index)) return false;
    final encoded = jsonEncode(text);
    try {
      // Önce alanı normal kullanıcı tıklamış gibi aktif et. Yandex bazı
      // sürümlerde bu tıklamadan sonra rota arama katmanını yeniden çiziyor.
      final activated = await _mapController.executeScript('''
(() => {
  const fold = (v) => (v || '').toLocaleLowerCase('tr-TR');
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const st = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  const inputs = Array.from(document.querySelectorAll('input')).filter(visible).filter((e) => {
    const meta = fold(`\${e.getAttribute('placeholder') || ''} \${e.getAttribute('aria-label') || ''}`);
    return !meta.includes('rota üzerinde ara') && !meta.includes('arama ve yer seçimi') && !meta.includes('haritada ara');
  });
  const input = inputs[$index];
  if (!input) return false;
  input.click();
  input.focus();
  return true;
})()
''');
      if (!(activated == true || activated?.toString() == 'true')) return false;
      await Future<void>.delayed(const Duration(milliseconds: 220));

      // Tıklama sonrası DOM değişebileceği için input'u tekrar bulup yazıyoruz.
      final result = await _mapController.executeScript('''
(() => {
  const fold = (v) => (v || '').toLocaleLowerCase('tr-TR');
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const st = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  const inputs = Array.from(document.querySelectorAll('input')).filter(visible).filter((e) => {
    const meta = fold(`\${e.getAttribute('placeholder') || ''} \${e.getAttribute('aria-label') || ''}`);
    return !meta.includes('rota üzerinde ara') && !meta.includes('arama ve yer seçimi') && !meta.includes('haritada ara');
  });
  const input = inputs[$index];
  if (!input) return false;
  input.focus();
  try { input.select(); } catch (_) {}
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
  if (setter) setter.call(input, $encoded); else input.value = $encoded;
  input.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'insertText', data:$encoded}));
  input.dispatchEvent(new Event('change', {bubbles:true}));
  return true;
})()
''');
      return result == true || result?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _readYandexSuggestionCandidates() async {
    if (!_mapReady || !Platform.isWindows) return const [];
    try {
      final value = await _mapController.executeScript(r'''
(() => {
  const visible = (e) => {
    const r = e.getBoundingClientRect();
    const st = getComputedStyle(e);
    return r.width > 2 && r.height > 2 && st.display !== 'none' && st.visibility !== 'hidden';
  };
  const seen = new Set();
  const nodes = [];
  const add = (e) => {
    if (!e || !visible(e)) return;
    const text = (e.innerText || e.textContent || '').replace(/\s+/g, ' ').trim();
    if (text.length < 4 || text.length > 320) return;
    if (seen.has(text)) return;
    seen.add(text);
    nodes.push(e);
  };

  document.querySelectorAll(
    '[role="option"], [class*="suggest-item"], [class*="suggest__item"], [class*="search-suggest"], li[class*="suggest"]'
  ).forEach(add);

  const roots = Array.from(document.querySelectorAll('[role="listbox"], [class*="suggest"], [class*="popup"]')).filter(visible);
  roots.forEach((root) => Array.from(root.children || []).forEach(add));

  // Yandex sınıf adlarını değiştirse bile öneriler sol arama panelinde görünür.
  // Sol taraftaki küçük metin bloklarını da aday havuzuna alıyoruz; Dart tarafı
  // sokak + kapı + ilçe + il tam eşleşmesi yapacağı için yanlış UI öğesi seçilmez.
  const leftLimit = Math.min(620, window.innerWidth * 0.48);
  Array.from(document.querySelectorAll('div, li, a, button'))
    .filter(visible)
    .filter((e) => {
      const r = e.getBoundingClientRect();
      return r.left >= 0 && r.left < leftLimit && r.top >= 0 && r.top < window.innerHeight * 0.85;
    })
    .forEach(add);

  nodes.sort((a, b) => {
    const at = (a.innerText || a.textContent || '').trim().length;
    const bt = (b.innerText || b.textContent || '').trim().length;
    return at - bt;
  });
  window.__motusYandexSuggestionNodes = nodes;
  return nodes.map((e) => (e.innerText || e.textContent || '').replace(/\s+/g, ' ').trim());
})()
''');
      dynamic decoded = value;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }
      if (decoded is List) {
        return decoded.map((e) => e?.toString() ?? '').toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> _clickYandexSuggestionCandidate(int index) async {
    if (!_mapReady || !Platform.isWindows) return false;
    try {
      final result = await _mapController.executeScript('''
(() => {
  const nodes = window.__motusYandexSuggestionNodes || [];
  const node = nodes[$index];
  if (!node || !document.contains(node)) return false;
  try { node.scrollIntoView({block:'nearest'}); } catch (_) {}
  node.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, cancelable:true, view:window}));
  node.dispatchEvent(new MouseEvent('mouseup', {bubbles:true, cancelable:true, view:window}));
  node.click();
  return true;
})()
''');
      return result == true || result?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  bool _suggestionTextMatchesJob(TechnicianJob job, String value) {
    if (!_routeValueMatchesJob(job, value)) return false;
    final actual = _foldAddressText(value);
    final city = _foldAddressText(job.city);
    final district = _foldAddressText(job.district);
    if (city.isNotEmpty && !actual.contains(city)) return false;
    if (district.isNotEmpty && !actual.contains(district)) return false;
    return true;
  }

  Future<String?> _addJobFromYandexSuggestions(
    TechnicianJob job,
    int routeInputIndex,
  ) async {
    final query = _nativeRoutePointForJob(job).trim();
    if (query.isEmpty) return null;

    for (var fillAttempt = 0; fillAttempt < 2; fillAttempt++) {
      if (!await _fillYandexRouteInput(routeInputIndex, query)) return null;

      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final candidates = await _readYandexSuggestionCandidates();
        if (candidates.isEmpty) continue;

        for (var i = 0; i < candidates.length; i++) {
          final candidate = candidates[i];
          if (!_suggestionTextMatchesJob(job, candidate)) continue;
          if (!await _clickYandexSuggestionCandidate(i)) continue;

          // V38: Yandex doğru öneri seçildikten sonra bazı duraklarda rota
          // gerçekten oluşmasına rağmen input alanında kullanıcının yazdığı ham
          // sorguyu bırakabiliyor (özellikle son durakta). V37 bu input metnini
          // ikinci kez doğrulamaya çalıştığı için, haritada oluşmuş doğru durağı
          // yanlışlıkla "Adres Hatalı" sayıyordu.
          //
          // Buraya gelmeden önce candidate zaten sokak + kapı no + ilçe + il
          // olarak _suggestionTextMatchesJob ile kesin eşleşmiştir. Yandex'in
          // kendi önerisine başarılı tıklama, bu akışta adres doğrulamasıdır.
          // Koordinat/fallback/tahmin kullanılmaz.
          await Future<void>.delayed(const Duration(milliseconds: 850));
          return candidate.trim();
        }
      }
    }
    return null;
  }

  Future<void> _buildRouteWithNativeYandex(List<TechnicianJob> jobs) async {
    if (jobs.isEmpty || _optimizing) return;
    if (!_mapReady || !Platform.isWindows) {
      await _launchYandex(jobs);
      return;
    }

    setState(() {
      _optimizing = true;
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};
    });
    try {
      final start = (await _readYandexStartText())?.trim();
      if (start == null || start.isEmpty) {
        await _openNativeYandexStartPlanner(showHint: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 6),
              content: Text(
                'Once Yandex’te baslangic noktasini secin. Sonra Rotayi Olustur’a basin.',
              ),
            ),
          );
        }
        return;
      }

      _yandexStartText = start;
      final startForRoute = _startPointWithCityContext(start, jobs);

      final missingAddressJobs = jobs
          .where((job) => _nativeRoutePointForJob(job).trim().isEmpty)
          .toList(growable: false);
      if (missingAddressJobs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _invalidAddressJobIds = missingAddressJobs.map((e) => e.id).toSet();
            _invalidAddressResolvedText = <String, String>{};
            _selectedJob = missingAddressJobs.first;
          });
          final names = missingAddressJobs.map((e) => e.customerName).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              content: Text(
                'Adres eksik: $names. Müşteriyi arayıp adresi düzeltmeden rota oluşturulamaz.',
              ),
            ),
          );
        }
        return;
      }

      // V36: müşterileri rtext ile topluca Yandex'e bırakmıyoruz. Önce yalnızca
      // başlangıcı açıyoruz; sonra her müşterinin yazılı adresini Yandex rota
      // alanına TEK TEK yazıp Yandex'in kendi önerilerinden sokak + kapı +
      // ilçe + il olarak tam eşleşen sonucu tıklıyoruz.
      // Koordinat / fallback / başka sokak tahmini kesinlikle yok.
      final url = _nativeRoutePlannerUrl(rtext: startForRoute);
      _lastMapUrl = url;
      _routeBuilt = false;
      _startPointLabel = start;
      await _mapController.loadUrl(url);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      if (!await _ensureYandexRouteInput(0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Yandex rota alanı hazırlanamadı. Tekrar deneyin.'),
            ),
          );
        }
        return;
      }

      final failed = <TechnicianJob>[];
      for (var i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        final resolved = await _addJobFromYandexSuggestions(job, i + 1);
        if (resolved == null) {
          failed.add(job);
          break;
        }
      }

      if (failed.isNotEmpty) {
        _yandexRouteSyncTimer?.cancel();
        if (mounted) {
          setState(() {
            _routeBuilt = false;
            _invalidAddressJobIds = failed.map((e) => e.id).toSet();
            _invalidAddressResolvedText = <String, String>{};
            _selectedJob = failed.first;
          });
          final names = failed.map((e) => e.customerName).join(', ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 9),
              content: Text(
                'Yandex’te tam adres bulunamadı: $names. Müşteriyi arayıp adresi düzeltin.',
              ),
            ),
          );
        }
        return;
      }

      // Her durak Yandex'in kendi önerisinden seçildi. Bu noktada başka bir
      // geocoder/tahmin kontrolü çalıştırmıyoruz; seçilen gerçek Yandex sonucu
      // rota için tek doğruluk kaynağıdır.
      _routeBuilt = true;
      _invalidAddressJobIds = <String>{};
      _invalidAddressResolvedText = <String, String>{};

      _localRouteOrderIds = jobs.map((job) => job.id).toList(growable: false);
      _startYandexOrderSync(jobs);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              '${jobs.length} müşteri Yandex’in kendi adres önerilerinden seçilerek rotaya eklendi.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _optimizing = false);
    }
  }

  Future<void> _syncMap(List<TechnicianJob> jobs) async {
    // Yandex rota ekraninin kendi Nereden secimini ve Optimize et siralamasini
    // tekrar loadUrl yaparak ezmiyoruz.
    if (!_mapReady || !Platform.isWindows || _lastMapUrl != null) return;
    await _openNativeYandexStartPlanner(showHint: false);
  }

  Future<void> _launchYandex(List<TechnicianJob> jobs) async {
    final points = jobs
        .map(_nativeRoutePointForJob)
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (points.isEmpty) return;
    await launchUrl(
      Uri.parse(_nativeRoutePlannerUrl(rtext: points.join('~'))),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _launchMap(TechnicianJob job) async {
    final query = _canonicalJobAddress(job).trim();
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
    final invalidAddress = _invalidAddressJobIds.contains(job.id);
    return Material(
      color: invalidAddress
          ? const Color(0xFFFFF1F1)
          : selected
              ? const Color(0xFFE7F8FA)
              : Colors.transparent,
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
                  if (invalidAddress) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE2E2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Adres Hatalı',
                        style: TextStyle(
                          color: Color(0xFFC83E3E),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  if (index == 0 && !invalidAddress) ...[
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
              if (invalidAddress) ...[
                const SizedBox(height: 4),
                Text(
                  _invalidAddressResolvedText[job.id]?.trim().isNotEmpty == true
                      ? 'Yandex farklı buldu: ${_invalidAddressResolvedText[job.id]}'
                      : 'Yandex bu adresi doğrulayamadı. Müşteriyi arayıp adresi düzeltin.',
                  style: const TextStyle(
                    color: Color(0xFFC83E3E),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
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
                      onPressed: invalidAddress ? null : () => _openJob(job),
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
                  ? Stack(
                      children: [
                        Positioned.fill(child: Webview(_mapController)),
                        if (_invalidAddressJobIds.isNotEmpty)
                          Positioned(
                            left: 16,
                            right: 16,
                            top: 16,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFECEC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFFB8B8)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Color(0xFFC83E3E)),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'ROTA GEÇERSİZ — adresi hatalı görünen müşteriyi arayıp adresi düzeltin.',
                                        style: TextStyle(
                                          color: Color(0xFF9C2F2F),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_routeBuilt && jobs.isNotEmpty)
                          Positioned(
                            right: 18,
                            bottom: 18,
                            child: IgnorePointer(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 210),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD8E4EA)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: jobs.asMap().entries.map((entry) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        '${entry.key + 1}  ${entry.value.customerName}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF12304A),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    );
                                  }).toList(growable: false),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
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
    final invalidAddress = job != null && _invalidAddressJobIds.contains(job.id);
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
                        if (invalidAddress) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFFCACA)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Adres Yandex tarafından doğrulanamadı',
                                  style: TextStyle(
                                    color: Color(0xFFC83E3E),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Müşteriyi arayın, doğru adresi isteyin ve Bilgileri Düzenle bölümünden kaydedin.',
                                  style: TextStyle(
                                    color: Color(0xFF8B3A3A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_invalidAddressResolvedText[job.id]?.trim().isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Yandex’in bulduğu: ${_invalidAddressResolvedText[job.id]}',
                                    style: const TextStyle(
                                      color: Color(0xFF8B3A3A),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
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
                        if (job.secretaryName.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Talebi açan: ${job.secretaryName.trim()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF65778A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
                            'Sekreter Notu',
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
                    onPressed: invalidAddress ? null : () => _openJob(job),
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
                        onPressed: invalidAddress || job.phone.isEmpty
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
                        onPressed: invalidAddress || job.mapQuery.isEmpty
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
