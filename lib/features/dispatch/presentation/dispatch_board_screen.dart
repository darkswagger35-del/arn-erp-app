import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../customers/presentation/providers/customer_providers.dart';
import '../../service_requests/data/models/service_request_model.dart';
import '../../service_requests/presentation/providers/service_request_providers.dart';
import '../../user_management/data/user_management_repository_provider.dart';
import '../../user_management/domain/user_management_user.dart';
import '../models/route_job.dart';
import '../services/route_distance_service.dart';
import '../services/district_centroid_service.dart';
import '../services/smart_route_planner.dart';

class DispatchBoardScreen extends ConsumerStatefulWidget {
  const DispatchBoardScreen({super.key});

  @override
  ConsumerState<DispatchBoardScreen> createState() => _DispatchBoardScreenState();
}

enum _AddressState { unknown, checking, found, notFound, error }

enum _DispatchListMode { unassigned, assigned }

class _GeoPoint {
  const _GeoPoint(this.longitude, this.latitude);

  final double longitude;
  final double latitude;
}

class _AddressResult {
  const _AddressResult({
    required this.state,
    this.point,
    this.message,
  });

  final _AddressState state;
  final _GeoPoint? point;
  final String? message;
}

class _SmartPlanEntry {
  const _SmartPlanEntry({
    required this.technician,
    required this.jobs,
    this.estimatedKm = 0,
    this.estimatedDriveMinutes = 0,
    this.score = 0,
  });

  final UserManagementUser technician;
  final List<ServiceRequestModel> jobs;
  final double estimatedKm;
  final int estimatedDriveMinutes;
  final double score;
}

class _DispatchBoardScreenState extends ConsumerState<DispatchBoardScreen> {
  static const String _allDistricts = '__ALL_CITY__';
  static const _teal = Color(0xFF11B8C6);
  static const _panel = Color(0xFFFFFFFF);
  static const _panel2 = Color(0xFFF5F8FA);
  static const _border = Color(0xFFD8E2E8);
  static const _muted = Color(0xFF60758A);
  static const _warning = Color(0xFFFFA726);
  static const _danger = Color(0xFFFF5F62);
  static const _success = Color(0xFF22C77A);
  static const _blue = Color(0xFF2C8CFF);

  static const String _yandexGeocoderKey =
      String.fromEnvironment('YANDEX_GEOCODER_API_KEY');
  static const String _yandexStaticKey =
      String.fromEnvironment('YANDEX_STATIC_API_KEY');

  bool _loading = true;
  bool _assigning = false;
  bool _validating = false;
  String? _error;
  List<ServiceRequestModel> _requests = const [];
  List<UserManagementUser> _technicians = const [];
  String? _selectedCity;
  String? _selectedDistrict;
  final Set<String> _selectedDistricts = <String>{};
  DateTime? _selectedPlanDate;
  String? _selectedTechnicianId; // Toplu atama hedefi
  String? _filterTechnicianId; // Harita ve iş listesi filtresi
  String _routeSearch = '';
  String _routeSort = 'route';
  final Set<String> _smartTechnicianIds = <String>{};
  _DispatchListMode _listMode = _DispatchListMode.unassigned;
  final Set<String> _selectedRequestIds = <String>{};
  final Map<String, _AddressResult> _addressCache = <String, _AddressResult>{};
  final SmartRoutePlanner _routePlanner = SmartRoutePlanner();
  static const DistrictCentroidService _districtCentroids = DistrictCentroidService();
  static const RouteDistanceService _routeDistance = RouteDistanceService();
  final WebviewController _yandexWebController = WebviewController();
  bool _yandexWebReady = false;
  String? _lastEmbeddedYandexUrl;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _initYandexWebView();
      await _load();
    });
  }

  @override
  void dispose() {
    _yandexWebController.dispose();
    super.dispose();
  }

  Future<void> _initYandexWebView() async {
    if (!Platform.isWindows) return;
    try {
      await _yandexWebController.initialize();
      if (!mounted) return;
      setState(() => _yandexWebReady = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _yandexWebReady = false);
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        ref.read(serviceRequestRepositoryProvider).getServiceRequests(),
        ref
            .read(userManagementRepositoryProvider)
            .listUsers(includeArchived: false),
      ]);

      final requests = (results[0] as List<ServiceRequestModel>)
          .where((r) =>
              (r.status == ServiceRequestStatus.approved ||
               r.status == ServiceRequestStatus.assigned) &&
              r.plannedDate != null)
          .toList(growable: false);
      final technicians = (results[1] as List<UserManagementUser>)
          .where((u) => u.role == AppRole.technician && u.isActive)
          .toList(growable: false);

      final cities = requests
          .map((r) => r.customerCity.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _requests = requests;
        _technicians = technicians;
        if (_filterTechnicianId != null &&
            !technicians.any((tech) => tech.id == _filterTechnicianId)) {
          _filterTechnicianId = null;
        }
        final validSmartIds = _smartTechnicianIds
            .where((id) => technicians.any((tech) => tech.id == id))
            .toSet();
        _smartTechnicianIds
          ..clear()
          ..addAll(validSmartIds);
        if (_smartTechnicianIds.isEmpty) {
          _smartTechnicianIds.addAll(
            technicians.take(math.min(3, technicians.length)).map((e) => e.id),
          );
        }
        if (_selectedCity == null || !cities.contains(_selectedCity)) {
          _selectedCity = cities.contains('İzmir')
              ? 'İzmir'
              : (cities.isNotEmpty ? cities.first : null);
        }
        final districts = _districts;
        if (_selectedCity == null) {
          _selectedDistrict = null;
          _selectedDistricts.clear();
        } else {
          _selectedDistrict = _allDistricts;
          final validSelected = _selectedDistricts.where(districts.contains).toSet();
          _selectedDistricts
            ..clear()
            ..addAll(validSelected.isEmpty ? districts : validSelected);
        }
        _selectedRequestIds.clear();
        _selectedTechnicianId = null;
        _loading = false;
      });
      await _validateVisibleAddresses();
      await _refreshEmbeddedYandex();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<String> get _cities {
    final values = _requests
        .map((r) => r.customerCity.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<ServiceRequestModel> get _cityRequests {
    if (_selectedCity == null) return const [];
    return _requests.where((r) {
      if (r.customerCity.trim() != _selectedCity) return false;
      if (_selectedPlanDate == null) return true;
      final planned = r.plannedDate?.toLocal();
      if (planned == null) return false;
      return planned.year == _selectedPlanDate!.year &&
          planned.month == _selectedPlanDate!.month &&
          planned.day == _selectedPlanDate!.day;
    }).toList(growable: false);
  }

  List<String> get _districts {
    final values = _cityRequests
        .map((r) => r.customerDistrict.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<ServiceRequestModel> get _visibleJobs {
    if (_selectedCity == null) return const [];
    final values = (_selectedDistricts.isEmpty || _selectedDistricts.length == _districts.length
            ? _cityRequests
            : _cityRequests
                .where((r) => _selectedDistricts.contains(r.customerDistrict.trim()))
                .toList(growable: false))
        .toList(growable: true);
    values.sort((a, b) {
      final ao = a.routeOrder;
      final bo = b.routeOrder;
      if (ao != null || bo != null) return (ao ?? 9999).compareTo(bo ?? 9999);
      return 0;
    });
    return values;
  }

  bool _isAssigned(ServiceRequestModel job) {
    final techId = job.assignedTechnicianId?.trim() ?? '';
    return job.status == ServiceRequestStatus.assigned || techId.isNotEmpty;
  }

  List<ServiceRequestModel> get _unassignedVisibleJobs => _visibleJobs
      .where((job) => !_isAssigned(job))
      .toList(growable: false);

  List<ServiceRequestModel> get _assignedVisibleJobs => _visibleJobs
      .where(_isAssigned)
      .toList(growable: false);

  List<ServiceRequestModel> get _displayedJobs {
    var values = _visibleJobs.toList(growable: true);
    final filterTech = _filterTechnicianId?.trim() ?? '';
    if (filterTech.isNotEmpty) {
      values = values
          .where((job) => job.assignedTechnicianId?.trim() == filterTech)
          .toList(growable: true);
    }
    final query = _routeSearch.trim().toLowerCase();
    if (query.isNotEmpty) {
      values = values.where((job) {
        return job.customerName.toLowerCase().contains(query) ||
            job.customerPhone.toLowerCase().contains(query) ||
            job.customerAddress.toLowerCase().contains(query) ||
            job.customerCity.toLowerCase().contains(query) ||
            job.customerDistrict.toLowerCase().contains(query) ||
            job.serviceType.label.toLowerCase().contains(query);
      }).toList(growable: true);
    }
    switch (_routeSort) {
      case 'customer':
        values.sort((a, b) => a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase()));
        break;
      case 'district':
        values.sort((a, b) => a.customerDistrict.toLowerCase().compareTo(b.customerDistrict.toLowerCase()));
        break;
      case 'route':
      default:
        values.sort((a, b) {
          final ao = a.routeOrder ?? 9999;
          final bo = b.routeOrder ?? 9999;
          if (ao != bo) return ao.compareTo(bo);
          final ad = a.plannedDate;
          final bd = b.plannedDate;
          if (ad != null && bd != null) return ad.compareTo(bd);
          return a.customerName.compareTo(b.customerName);
        });
    }
    return values;
  }

  UserManagementUser? get _filterTechnician {
    final id = _filterTechnicianId;
    if (id == null) return null;
    for (final tech in _technicians) {
      if (tech.id == id) return tech;
    }
    return null;
  }

  double get _displayedRouteKm {
    final routeJobs = _uniqueVisits(_displayedJobs).map(_toRouteJob).toList(growable: false);
    return _routeDistance.routeKm(routeJobs) * 1.30;
  }

  int get _displayedDriveMinutes {
    final straightKm = _displayedRouteKm / 1.30;
    return _routeDistance.estimatedDriveMinutes(straightKm);
  }

  List<UserManagementUser> get _smartTechnicians {
    final selected = _technicians
        .where((tech) => _smartTechnicianIds.contains(tech.id))
        .toList(growable: false);
    if (selected.isNotEmpty) return selected;
    return _technicians
        .take(math.min(3, _technicians.length))
        .toList(growable: false);
  }

  String get _selectedAreaLabel {
    if (_selectedCity == null) return 'Bölge';
    if (_selectedDistricts.isEmpty || _selectedDistricts.length == _districts.length) {
      return 'Tüm $_selectedCity';
    }
    if (_selectedDistricts.length <= 3) return _selectedDistricts.join(' + ');
    return '${_selectedDistricts.length} ilçe';
  }

  List<ServiceRequestModel> get _uniqueVisibleCustomers {
    final byCustomer = <String, ServiceRequestModel>{};
    for (final job in _displayedJobs) {
      final key = job.customerId.isNotEmpty
          ? job.customerId
          : '${job.customerName}|${_fullAddress(job)}';
      byCustomer.putIfAbsent(key, () => job);
    }
    return byCustomer.values.toList(growable: false);
  }

  int _districtJobCount(String district) => _cityRequests
      .where((r) => r.customerDistrict.trim() == district)
      .length;

  int _todayCountForTechnician(String technicianId) {
    final now = DateTime.now();
    return _requests.where((r) {
      if (r.assignedTechnicianId != technicianId) return false;
      final date = r.plannedDate;
      if (date == null) return true;
      final local = date.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).length;
  }

  double _sum(List<ServiceRequestModel> requests) =>
      requests.fold<double>(0, (sum, r) => sum + r.price);

  String _money(double value) {
    final rounded = value.toStringAsFixed(0);
    final chars = rounded.split('');
    final b = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && (chars.length - i) % 3 == 0) b.write('.');
      b.write(chars[i]);
    }
    return '₺${b.toString()}';
  }

  String _fullAddress(ServiceRequestModel job) {
    final parts = <String>[
      job.customerAddress.trim(),
      job.customerDistrict.trim(),
      job.customerCity.trim(),
      'Türkiye',
    ].where((e) => e.isNotEmpty).toList();
    return parts.join(', ');
  }

  String _addressKey(ServiceRequestModel job) =>
      '${job.customerId}|${_fullAddress(job).toLowerCase()}';

  List<String> _addressVariants(ServiceRequestModel job) {
    final raw = job.customerAddress.trim();
    final district = job.customerDistrict.trim();
    final city = job.customerCity.trim();
    final variants = <String>{};

    void add(String value) {
      final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.isNotEmpty) variants.add(cleaned);
    }

    // Önce müşterinin kayıtlı tam adresini dene.
    add([raw, district, city, 'Türkiye'].where((e) => e.isNotEmpty).join(', '));
    add([raw, district, city].where((e) => e.isNotEmpty).join(', '));

    // Yandex/Nominatim bazı eski kayıtlardaki "sk", "sok", "no" yazımlarında
    // farklı sonuç verebildiği için normalize edilmiş sürümü de dene.
    var normalized = raw
        .replaceAll(RegExp(r'\bsk\.?\b', caseSensitive: false), 'Sokak')
        .replaceAll(RegExp(r'\bsok\.?\b', caseSensitive: false), 'Sokak')
        .replaceAll(RegExp(r'\bmah\.?\b', caseSensitive: false), 'Mahallesi')
        .replaceAll(RegExp(r'\bmh\.?\b', caseSensitive: false), 'Mahallesi')
        .replaceAll(RegExp(r'\bno\.?\s*:?\s*', caseSensitive: false), 'No:');
    add([normalized, district, city, 'Türkiye'].where((e) => e.isNotEmpty).join(', '));

    // Son çare: ilçe bilgisini iki kez içeriyorsa sadeleştirerek dene.
    if (district.isNotEmpty &&
        normalized.toLowerCase().contains(district.toLowerCase())) {
      add([normalized, city, 'Türkiye'].where((e) => e.isNotEmpty).join(', '));
    }
    return variants.toList(growable: false);
  }

  Future<_AddressResult> _resolveAddress(ServiceRequestModel job) async {
    _AddressResult? last;
    for (final candidate in _addressVariants(job)) {
      if (_yandexGeocoderKey.trim().isNotEmpty) {
        final yandex = await _geocode(candidate);
        if (yandex.state == _AddressState.found) {
          return _AddressResult(
            state: _AddressState.found,
            point: yandex.point,
            message: 'Yandex adresi doğruladı.',
          );
        }
        last = yandex;
      }

      final fallback = await _geocodeFallback(candidate);
      if (fallback.state == _AddressState.found) {
        return _AddressResult(
          state: _AddressState.found,
          point: fallback.point,
          message: _yandexGeocoderKey.trim().isEmpty
              ? 'Adres koordinatı bulundu; Yandex rotasına gönderilebilir.'
              : 'Alternatif adres çözümlemesiyle koordinat bulundu.',
        );
      }
      last = fallback;
    }

    // Yandex anahtarı yokken başka bir servisin bulamaması, Yandex Haritalar'ın
    // da bulamadığı anlamına gelmez. Bu yüzden yanlış kırmızı uyarı üretme.
    if (_yandexGeocoderKey.trim().isEmpty) {
      return const _AddressResult(
        state: _AddressState.unknown,
        message: 'Adres Yandex rotasına gönderilecek; kesin bulunamadı sayılmadı.',
      );
    }
    return last ?? const _AddressResult(
      state: _AddressState.notFound,
      message: 'Adres doğrulanamadı.',
    );
  }

  bool _basicAddressLooksUsable(ServiceRequestModel job) {
    final address = job.customerAddress.trim();
    return address.length >= 5 &&
        job.customerCity.trim().isNotEmpty &&
        job.customerDistrict.trim().isNotEmpty;
  }

  _AddressResult _resultFor(ServiceRequestModel job) {
    if (!_basicAddressLooksUsable(job)) {
      return const _AddressResult(
        state: _AddressState.notFound,
        message: 'Açık adres / ilçe / şehir eksik.',
      );
    }
    return _addressCache[_addressKey(job)] ??
        const _AddressResult(state: _AddressState.unknown);
  }

  Future<void> _changeCity(String? city) async {
    setState(() {
      _selectedCity = city;
      _selectedDistrict = city == null ? null : _allDistricts;
      _selectedDistricts
        ..clear()
        ..addAll(city == null ? const <String>[] : _districts);
      _selectedRequestIds.clear();
      _selectedTechnicianId = null;
      _listMode = _DispatchListMode.unassigned;
    });
    await _validateVisibleAddresses();
    await _refreshEmbeddedYandex();
  }

  Future<void> _chooseDistricts() async {
    if (_selectedCity == null || _districts.isEmpty) return;
    final draft = Set<String>.from(
      _selectedDistricts.isEmpty ? _districts : _selectedDistricts,
    );
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$_selectedCity • İlçeleri Seç'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: draft.length == _districts.length,
                    title: Text('Tüm $_selectedCity (${_cityRequests.length} iş)'),
                    onChanged: (v) => setDialogState(() {
                      draft.clear();
                      if (v == true) draft.addAll(_districts);
                    }),
                  ),
                  const Divider(),
                  ..._districts.map((district) => CheckboxListTile(
                    dense: true,
                    value: draft.contains(district),
                    title: Text(district),
                    subtitle: Text('${_districtJobCount(district)} iş'),
                    onChanged: (v) => setDialogState(() {
                      if (v == true) {
                        draft.add(district);
                      } else {
                        draft.remove(district);
                      }
                    }),
                  )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: draft.isEmpty ? null : () => Navigator.pop(dialogContext, Set<String>.from(draft)),
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDistricts
        ..clear()
        ..addAll(selected);
      _selectedDistrict = selected.length == _districts.length
          ? _allDistricts
          : (selected.length == 1 ? selected.first : _allDistricts);
      _selectedRequestIds.clear();
      _selectedTechnicianId = null;
    });
    await _validateVisibleAddresses();
    await _refreshEmbeddedYandex();
  }

  Future<void> _pickPlanDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedPlanDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPlanDate = picked;
      _selectedDistricts
        ..clear()
        ..addAll(_districts);
      _selectedRequestIds.clear();
    });
    await _validateVisibleAddresses();
    await _refreshEmbeddedYandex();
  }

  Future<void> _clearPlanDate() async {
    setState(() {
      _selectedPlanDate = null;
      _selectedDistricts
        ..clear()
        ..addAll(_districts);
      _selectedRequestIds.clear();
    });
    await _validateVisibleAddresses();
    await _refreshEmbeddedYandex();
  }

  Future<void> _validateVisibleAddresses({bool force = false}) async {
    final customers = _uniqueVisibleCustomers;
    if (customers.isEmpty || _validating) return;

    if (_yandexGeocoderKey.trim().isEmpty) {
      // Eksik adresleri yine işaretle; gerçek Yandex doğrulaması API anahtarı
      // eklendiğinde otomatik çalışır.
      if (mounted) setState(() {});
      return;
    }

    final pending = customers.where((job) {
      if (!_basicAddressLooksUsable(job)) return false;
      final cached = _addressCache[_addressKey(job)];
      return force || cached == null || cached.state == _AddressState.error;
    }).toList(growable: false);

    if (pending.isEmpty) return;

    setState(() => _validating = true);
    try {
      for (final job in pending) {
        if (!mounted) return;
        final key = _addressKey(job);
        setState(() {
          _addressCache[key] =
              const _AddressResult(state: _AddressState.checking);
        });
        final result = await _resolveAddress(job);
        if (!mounted) return;
        setState(() => _addressCache[key] = result);
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Future<_AddressResult> _geocode(String address) async {
    final client = HttpClient();
    try {
      final uri = Uri.https('geocode-maps.yandex.ru', '/v1/', {
        'apikey': _yandexGeocoderKey,
        'geocode': address,
        'lang': 'tr_TR',
        'format': 'json',
        'results': '1',
      });
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return _AddressResult(
          state: _AddressState.error,
          message: 'Yandex ${response.statusCode}: ${_apiMessage(body)}',
        );
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final responseMap = decoded['response'];
      final collection = responseMap is Map<String, dynamic>
          ? responseMap['GeoObjectCollection']
          : null;
      final members = collection is Map<String, dynamic>
          ? collection['featureMember']
          : null;
      if (members is! List || members.isEmpty) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Yandex bu adresi bulamadı.',
        );
      }
      final first = members.first;
      final geoObject = first is Map<String, dynamic> ? first['GeoObject'] : null;
      final point = geoObject is Map<String, dynamic> ? geoObject['Point'] : null;
      final pos = point is Map<String, dynamic> ? point['pos']?.toString() : null;
      if (pos == null || pos.trim().isEmpty) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Adres bulundu ancak koordinat alınamadı.',
        );
      }
      final parts = pos.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Koordinat biçimi geçersiz.',
        );
      }
      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lon == null || lat == null) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Koordinat okunamadı.',
        );
      }
      return _AddressResult(
        state: _AddressState.found,
        point: _GeoPoint(lon, lat),
      );
    } catch (e) {
      return _AddressResult(
        state: _AddressState.error,
        message: 'Yandex adres kontrolü başarısız: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _apiMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return 'Adres kontrol servisi yanıt vermedi.';
  }

  Future<void> _hydrateStoredCoordinates(List<ServiceRequestModel> jobs) async {
    final repository = ref.read(customerRepositoryProvider);
    for (final job in jobs) {
      if (!_basicAddressLooksUsable(job)) continue;
      final key = _addressKey(job);
      final cached = _addressCache[key];
      if (cached?.state == _AddressState.found) continue;
      try {
        final customer = await repository.getCustomer(job.customerId);
        final lat = customer?.latitude;
        final lon = customer?.longitude;
        if (lat != null && lon != null) {
          _addressCache[key] = _AddressResult(
            state: _AddressState.found,
            point: _GeoPoint(lon, lat),
            message: 'Kayıtlı müşteri koordinatı kullanıldı.',
          );
        }
      } catch (_) {
        // Kayıtlı koordinat okunamazsa otomatik geocoding aşamasına devam et.
      }
    }
    if (mounted) setState(() {});
  }

  Future<_AddressResult> _geocodeFallback(String address) async {
    final client = HttpClient();
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': address,
        'format': 'jsonv2',
        'limit': '1',
        'countrycodes': 'tr',
      });
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ARN-ERP/1.0 route-planner');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        return _AddressResult(
          state: _AddressState.error,
          message: 'Otomatik adres servisi ${response.statusCode} hatası verdi.',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! List || decoded.isEmpty) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Adres otomatik olarak koordinata çevrilemedi.',
        );
      }
      final first = decoded.first;
      if (first is! Map) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Adres sonucu okunamadı.',
        );
      }
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lon = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lon == null) {
        return const _AddressResult(
          state: _AddressState.notFound,
          message: 'Adres koordinatı okunamadı.',
        );
      }
      return _AddressResult(
        state: _AddressState.found,
        point: _GeoPoint(lon, lat),
        message: 'Otomatik koordinat bulundu.',
      );
    } catch (e) {
      return _AddressResult(
        state: _AddressState.error,
        message: 'Otomatik adres kontrolü başarısız: $e',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _ensureAddressPoints(List<ServiceRequestModel> jobs) async {
    if (_validating) return;
    await _hydrateStoredCoordinates(jobs);
    if (!mounted) return;

    final pending = jobs.where((job) {
      if (!_basicAddressLooksUsable(job)) return false;
      return _resultFor(job).state != _AddressState.found;
    }).toList(growable: false);
    if (pending.isEmpty) return;

    setState(() => _validating = true);
    try {
      for (var i = 0; i < pending.length; i++) {
        final job = pending[i];
        if (!mounted) return;
        final key = _addressKey(job);
        setState(() {
          _addressCache[key] = const _AddressResult(
            state: _AddressState.checking,
            message: 'Adres otomatik doğrulanıyor...',
          );
        });

        final result = await _resolveAddress(job);
        if (!mounted) return;
        setState(() => _addressCache[key] = result);

        // Kamu geocoder'ını zorlamamak için çağrıları seyrek tut.
        if (_yandexGeocoderKey.trim().isEmpty && i < pending.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 1050));
        }
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  RouteJob _toRouteJob(ServiceRequestModel job, {String? routeId}) {
    final resolved = _resultFor(job).point;
    final fallback = resolved == null
        ? _districtCentroids.resolve(job.customerCity, job.customerDistrict)
        : null;
    final point = resolved ?? (fallback == null
        ? null
        : _GeoPoint(fallback.longitude, fallback.latitude));
    return RouteJob(
      id: routeId ?? job.id ?? job.customerId,
      customerName: job.customerName,
      city: job.customerCity,
      district: job.customerDistrict,
      point: point == null
          ? null
          : RoutePoint(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
      plannedDate: job.plannedDate,
    );
  }

  String _visitKey(ServiceRequestModel job) {
    final customerId = job.customerId.trim();
    if (customerId.isNotEmpty) return 'customer:$customerId';
    final phone = job.customerPhone.replaceAll(RegExp(r'\D'), '');
    if (phone.isNotEmpty) return 'phone:$phone';
    return 'request:${job.id ?? job.customerName.trim().toLowerCase()}';
  }

  List<ServiceRequestModel> _uniqueVisits(List<ServiceRequestModel> jobs) {
    final byVisit = <String, ServiceRequestModel>{};
    for (final job in jobs) {
      final key = _visitKey(job);
      final current = byVisit[key];
      if (current == null) {
        byVisit[key] = job;
        continue;
      }
      // Aynı müşteriye aynı plan gününde birden fazla servis kaydı varsa
      // tekniker rotasında tek durak olarak göster. En güncel kaydı temsilci yap.
      final currentUpdated = current.updatedAt ?? current.createdAt ?? DateTime(1970);
      final nextUpdated = job.updatedAt ?? job.createdAt ?? DateTime(1970);
      if (nextUpdated.isAfter(currentUpdated)) byVisit[key] = job;
    }
    return byVisit.values.toList(growable: false);
  }

  _SmartPlanEntry _entryFromOrderedJobs(
    UserManagementUser technician,
    List<ServiceRequestModel> ordered,
  ) {
    final routeJobs = ordered.map(_toRouteJob).toList(growable: false);
    final straightKm = _routeDistance.routeKm(routeJobs);
    return _SmartPlanEntry(
      technician: technician,
      jobs: ordered,
      estimatedKm: straightKm * 1.30,
      estimatedDriveMinutes: _routeDistance.estimatedDriveMinutes(straightKm),
      score: straightKm,
    );
  }

  List<_SmartPlanEntry> _buildSmartPlan(List<ServiceRequestModel> jobs) {
    final technicians = List<UserManagementUser>.from(_smartTechnicians)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (technicians.isEmpty) return const <_SmartPlanEntry>[];

    // Rota bir servis kaydı listesi değil, fiziksel müşteri ziyareti listesidir.
    // Aynı müşterinin aynı güne ait iki açık servis kaydı tek durak olarak planlanır.
    final visits = _uniqueVisits(jobs);
    final jobByVisit = <String, ServiceRequestModel>{};
    final routeJobs = <RouteJob>[];
    for (final job in visits) {
      final visitKey = _visitKey(job);
      jobByVisit[visitKey] = job;
      routeJobs.add(_toRouteJob(job, routeId: visitKey));
    }
    if (routeJobs.isEmpty) return const <_SmartPlanEntry>[];

    final routePlans = _routePlanner.buildPlan(
      jobs: routeJobs,
      technicianIds: technicians.map((e) => e.id).toList(growable: false),
    );
    final techById = {for (final tech in technicians) tech.id: tech};

    return routePlans.map((plan) {
      final tech = techById[plan.technicianId]!;
      final ordered = plan.jobIds
          .map((id) => jobByVisit[id])
          .whereType<ServiceRequestModel>()
          .toList(growable: false);
      return _SmartPlanEntry(
        technician: tech,
        jobs: ordered,
        estimatedKm: plan.estimatedKm,
        estimatedDriveMinutes: plan.estimatedDriveMinutes,
        score: plan.score,
      );
    }).where((entry) => entry.jobs.isNotEmpty).toList(growable: false);
  }

  List<_SmartPlanEntry> _planFromAssignments(
    List<ServiceRequestModel> jobs,
    Map<String, String> assignments,
  ) {
    final techs = List<UserManagementUser>.from(_smartTechnicians);
    final visits = _uniqueVisits(jobs);
    return techs.map((tech) {
      final rows = visits.where((job) => assignments[_visitKey(job)] == tech.id)
          .toList(growable: false);

      final routeJobs = rows
          .map((job) => _toRouteJob(job, routeId: _visitKey(job)))
          .toList(growable: false);
      final orderedIds = _routePlanner.orderRoute(routeJobs).map((e) => e.id).toList();
      final byVisit = {for (final row in rows) _visitKey(row): row};
      final ordered = orderedIds
          .map((id) => byVisit[id])
          .whereType<ServiceRequestModel>()
          .toList(growable: false);
      return _entryFromOrderedJobs(tech, ordered);
    }).where((entry) => entry.jobs.isNotEmpty).toList(growable: false);
  }

  List<_SmartPlanEntry> _planFromAssignmentsWithManualOrder(
    List<ServiceRequestModel> jobs,
    Map<String, String> assignments,
    Map<String, List<String>> manualOrderByTechnician,
  ) {
    final techs = List<UserManagementUser>.from(_smartTechnicians);
    final visits = _uniqueVisits(jobs);
    return techs.map((tech) {
      final rows = visits
          .where((job) => assignments[_visitKey(job)] == tech.id)
          .toList(growable: false);
      if (rows.isEmpty) {
        return _SmartPlanEntry(
          technician: tech,
          jobs: const [],
          estimatedKm: 0,
          estimatedDriveMinutes: 0,
          score: 0,
        );
      }

      final routeJobs = rows
          .map((job) => _toRouteJob(job, routeId: _visitKey(job)))
          .toList(growable: false);
      final automaticIds =
          _routePlanner.orderRoute(routeJobs).map((e) => e.id).toList();
      final byVisit = {for (final row in rows) _visitKey(row): row};
      final manual = manualOrderByTechnician[tech.id] ?? const <String>[];
      final orderedIds = <String>[
        ...manual.where(byVisit.containsKey),
        ...automaticIds.where((id) => !manual.contains(id)),
      ];
      final ordered = orderedIds
          .map((id) => byVisit[id])
          .whereType<ServiceRequestModel>()
          .toList(growable: false);
      return _entryFromOrderedJobs(tech, ordered);
    }).where((entry) => entry.jobs.isNotEmpty).toList(growable: false);
  }

  Future<void> _smartPlan() async {
    if (_validating || _assigning) return;
    final selectedUnassigned = _unassignedVisibleJobs
        .where((j) => j.id != null && _selectedRequestIds.contains(j.id))
        .toList(growable: false);
    final source = selectedUnassigned.isNotEmpty
        ? selectedUnassigned
        : _unassignedVisibleJobs;
    if (source.isEmpty) {
      _snack('Planlanacak servis bulunamadı.');
      return;
    }

    _snack('Adresler doğrulanıyor; mesafe odaklı rota planı hazırlanıyor...');
    await _ensureAddressPoints(source);
    if (!mounted) return;

    final invalid = source.where((j) {
      if (_resultFor(j).state == _AddressState.found) return false;
      return _districtCentroids.resolve(j.customerCity, j.customerDistrict) == null;
    }).toList(growable: false);

    // Koordinat sonucu yalnızca rota kalitesini etkiler; atamayı asla engellemez.
    final initialPlan = _buildSmartPlan(source);
    if (initialPlan.isEmpty) {
      _snack('Aktif tekniker bulunamadı.');
      return;
    }

    final assignments = <String, String>{};
    for (final entry in initialPlan) {
      for (final job in entry.jobs) {
        assignments[_visitKey(job)] = entry.technician.id;
      }
    }
    final availableTechs = List<UserManagementUser>.from(_smartTechnicians)
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final manualOrderByTechnician = <String, List<String>>{
      for (final entry in initialPlan)
        entry.technician.id: entry.jobs.map(_visitKey).toList(growable: true),
    };
    Map<String, List<String>> acceptedManualOrder = const {};

    final acceptedAssignments = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final draft = Map<String, String>.from(assignments);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final previewPlan = _planFromAssignmentsWithManualOrder(
              source,
              draft,
              manualOrderByTechnician,
            );
            return AlertDialog(
              title: const Row(children: [
                Icon(Icons.auto_awesome_rounded, color: _teal),
                SizedBox(width: 8),
                Text('MOTUS Akıllı Plan • Önizleme'),
              ]),
              content: SizedBox(
                width: 820,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'İşler iş sayısına göre değil rota koridoruna göre planlandı. İzmir merkezinde Batı, Kuzey/Kuzeydoğu ve Merkez/Güney koridorları korunur; koridor içi sıralama gerçek koordinat mesafesine göre yapılır.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Henüz hiçbir gerçek atama değişmedi. Teknikeri listeden değiştirebilir; soldaki tutamaçtan müşteriyi yukarı/aşağı sürükleyerek rota sırasını elle düzenleyebilirsin.',
                        style: TextStyle(color: _muted),
                      ),
                      if (invalid.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _warning.withValues(alpha: .08),
                            border: Border.all(color: _warning.withValues(alpha: .35)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${invalid.length} iş için ne müşteri koordinatı ne de ilçe merkezi bulunabildi. Bu kayıtlar en yakın mevcut kümeye fallback olarak eklenir.',
                            style: const TextStyle(color: _warning, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ...previewPlan.map((entry) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                        '${entry.technician.fullName} • ${entry.jobs.length} iş',
                                        style: const TextStyle(fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                    Text(
                                      '~${entry.estimatedKm.toStringAsFixed(0)} km • ${_driveLabel(entry.estimatedDriveMinutes)}',
                                      style: TextStyle(color: _teal.withValues(alpha: .9), fontSize: 12, fontWeight: FontWeight.w800),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  ReorderableListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    buildDefaultDragHandles: false,
                                    itemCount: entry.jobs.length,
                                    onReorder: (oldIndex, newIndex) {
                                      setDialogState(() {
                                        final current = entry.jobs
                                            .map(_visitKey)
                                            .toList(growable: true);
                                        if (newIndex > oldIndex) newIndex -= 1;
                                        final moved = current.removeAt(oldIndex);
                                        current.insert(newIndex, moved);
                                        manualOrderByTechnician[entry.technician.id] = current;
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      final job = entry.jobs[index];
                                      final visitKey = _visitKey(job);
                                      final neighborhood = job.customerNeighborhood.trim();
                                      final neighborhoodLabel = neighborhood.isEmpty
                                          ? ''
                                          : (neighborhood.toLowerCase().contains('mah')
                                              ? neighborhood
                                              : '$neighborhood Mah.');
                                      final locationText = neighborhoodLabel.isEmpty
                                          ? job.customerDistrict
                                          : '${job.customerDistrict} • $neighborhoodLabel';
                                      return Container(
                                        key: ValueKey('${entry.technician.id}-$visitKey'),
                                        margin: const EdgeInsets.only(bottom: 7),
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(children: [
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: const Padding(
                                              padding: EdgeInsets.only(right: 8),
                                              child: Icon(
                                                Icons.drag_indicator_rounded,
                                                color: _muted,
                                                size: 21,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 26, child: Text('${index + 1}.')),
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  job.customerName,
                                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                                ),
                                                Text(
                                                  locationText,
                                                  style: const TextStyle(color: _muted, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (availableTechs.length > 1)
                                            SizedBox(
                                              width: 170,
                                              child: DropdownButtonFormField<String>(
                                                value: draft[visitKey],
                                                isExpanded: true,
                                                isDense: true,
                                                decoration: const InputDecoration(
                                                  labelText: 'Tekniker',
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                ),
                                                items: availableTechs
                                                    .map((tech) => DropdownMenuItem(
                                                          value: tech.id,
                                                          child: Text(
                                                            tech.fullName,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ))
                                                    .toList(),
                                                onChanged: (value) {
                                                  if (value == null || value == draft[visitKey]) return;
                                                  setDialogState(() {
                                                    final oldTechId = draft[visitKey];
                                                    draft[visitKey] = value;
                                                    if (oldTechId != null) {
                                                      manualOrderByTechnician[oldTechId]?.remove(visitKey);
                                                    }
                                                    for (final ids in manualOrderByTechnician.values) {
                                                      ids.remove(visitKey);
                                                    }
                                                    manualOrderByTechnician
                                                        .putIfAbsent(value, () => <String>[])
                                                        .add(visitKey);
                                                  });
                                                },
                                              ),
                                            ),
                                        ]),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Vazgeç'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    acceptedManualOrder = {
                      for (final entry in manualOrderByTechnician.entries)
                        entry.key: List<String>.from(entry.value),
                    };
                    Navigator.pop(
                      dialogContext,
                      Map<String, String>.from(draft),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Planı Uygula'),
                ),
              ],
            );
          },
        );
      },
    );
    if (acceptedAssignments == null || !mounted) return;

    final finalPlan = _planFromAssignmentsWithManualOrder(
      source,
      acceptedAssignments,
      acceptedManualOrder,
    );
    if (finalPlan.isEmpty) return;

    setState(() => _assigning = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final dated = source
          .map((e) => e.plannedDate?.toLocal())
          .whereType<DateTime>()
          .toList(growable: false);
      final base = dated.isNotEmpty ? dated.first : DateTime.now();
      final planDate = DateTime(base.year, base.month, base.day);
      for (final entry in finalPlan) {
        for (final row in entry.jobs.asMap().entries) {
          final visitKey = _visitKey(row.value);
          final sameVisitRequests = source
              .where((request) => _visitKey(request) == visitKey)
              .toList(growable: false);
          for (final request in sameVisitRequests) {
            final id = request.id;
            if (id == null) continue;
            await repo.updateRoutePlan(
              serviceRequestId: id,
              technicianId: entry.technician.id,
              routeOrder: row.key + 1,
              routePlanDate: planDate,
            );
          }
        }
      }
      if (!mounted) return;
      _snack(
        'Plan uygulandı: ${_uniqueVisits(source).length} müşteri durağı (${source.length} servis kaydı) ${finalPlan.length} teknikere rota olarak atandı.'
        '${invalid.isEmpty ? '' : ' ${invalid.length} iş koordinat olmadan da atandı.'}',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _snack('Akıllı rota kaydedilemedi: $error');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  String _driveLabel(int minutes) {
    if (minutes < 60) return '~$minutes dk yol';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '~$hours sa yol' : '~$hours sa $rest dk yol';
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _assignSelected() async {
    if (_selectedTechnicianId == null || _selectedRequestIds.isEmpty) return;
    setState(() => _assigning = true);
    try {
      final repository = ref.read(serviceRequestRepositoryProvider);
      for (final requestId in _selectedRequestIds) {
        await repository.assignTechnician(
          serviceRequestId: requestId,
          technicianId: _selectedTechnicianId!,
          // Servis türü, tarih, ürün ve diğer bilgiler aynen korunur.
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_selectedRequestIds.length} iş teknikere atandı.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Atama yapılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _setSelectedDate() async {
    if (_selectedRequestIds.isEmpty || _assigning) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() => _assigning = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final selected = _requests
          .where((r) => r.id != null && _selectedRequestIds.contains(r.id))
          .toList(growable: false);
      for (final r in selected) {
        final old = r.plannedDate?.toLocal();
        final date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          old?.hour ?? 0,
          old?.minute ?? 0,
        );
        await repo.updateServiceRequest(r.copyWith(plannedDate: date));
      }
      _snack('${selected.length} işin tarihi güncellendi.');
      await _load();
    } catch (e) {
      _snack('Tarih güncellenemedi: $e');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _unassignSelected() async {
    if (_selectedRequestIds.isEmpty || _assigning) return;
    setState(() => _assigning = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final ids = Set<String>.from(_selectedRequestIds);
      for (final id in ids) {
        await repo.unassignTechnician(serviceRequestId: id);
      }
      _snack('${ids.length} işin ataması kaldırıldı. Tarihleri korundu.');
      await _load();
    } catch (e) {
      _snack('Atama kaldırılamadı: $e');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _unassignOne(ServiceRequestModel job) async {
    if (job.id == null || _assigning) return;
    setState(() => _assigning = true);
    try {
      await ref
          .read(serviceRequestRepositoryProvider)
          .unassignTechnician(serviceRequestId: job.id!);
      _snack('${job.customerName} tekrar Atama Bekleyenler bölümüne alındı.');
      await _load();
    } catch (e) {
      _snack('Atama kaldırılamadı: $e');
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _setOneDate(ServiceRequestModel job) async {
    if (job.id == null) return;
    final old = job.plannedDate?.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: old ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    final date = DateTime(
      picked.year,
      picked.month,
      picked.day,
      old?.hour ?? 0,
      old?.minute ?? 0,
    );
    try {
      await ref
          .read(serviceRequestRepositoryProvider)
          .updateServiceRequest(job.copyWith(plannedDate: date));
      await _load();
    } catch (e) {
      _snack('Tarih güncellenemedi: $e');
    }
  }

  Uri _buildYandexUri(List<ServiceRequestModel> source) {
    final byCustomer = <String, ServiceRequestModel>{};
    for (final job in source) {
      if (!_basicAddressLooksUsable(job)) continue;
      final key = job.customerId.isEmpty ? _fullAddress(job) : job.customerId;
      byCustomer.putIfAbsent(key, () => job);
    }
    final jobs = byCustomer.values.toList(growable: false);

    if (jobs.isEmpty) {
      return Uri.https('yandex.com.tr', '/maps/', {
        'text': [_selectedCity, _selectedDistricts.length == 1 ? _selectedDistricts.first : null]
            .whereType<String>()
            .where((e) => e.trim().isNotEmpty)
            .join(' '),
      });
    }
    if (jobs.length == 1) {
      return Uri.https('yandex.com.tr', '/maps/', {'text': _fullAddress(jobs.first)});
    }
    return Uri.https('yandex.com.tr', '/maps/', {
      'mode': 'routes',
      'rtext': jobs.map(_fullAddress).join('~'),
      'rtt': 'auto',
    });
  }

  Future<void> _refreshEmbeddedYandex() async {
    if (!_yandexWebReady || !Platform.isWindows) return;
    final url = _buildYandexUri(_displayedJobs).toString();
    if (url == _lastEmbeddedYandexUrl) return;
    _lastEmbeddedYandexUrl = url;
    try {
      await _yandexWebController.loadUrl(url);
    } catch (_) {}
  }

  Future<void> _openInYandex({bool selectedOnly = false}) async {
    final source = selectedOnly
        ? _displayedJobs
            .where((j) => j.id != null && _selectedRequestIds.contains(j.id))
            .toList(growable: false)
        : _displayedJobs;
    final uri = _buildYandexUri(source);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yandex Haritalar açılamadı.')),
      );
    }
  }

  Future<void> _editCustomer(ServiceRequestModel job) async {
    if (job.customerId.isEmpty) return;
    await context.push('/manager/customers/${job.customerId}/edit');
    if (mounted) await _load();
  }

  String? get _staticMapUrl {
    if (_yandexStaticKey.trim().isEmpty) return null;
    final points = <_GeoPoint>[];
    final seen = <String>{};
    for (final job in _uniqueVisibleCustomers) {
      if (!seen.add(job.customerId.isEmpty ? _addressKey(job) : job.customerId)) {
        continue;
      }
      final result = _resultFor(job);
      if (result.state == _AddressState.found && result.point != null) {
        points.add(result.point!);
      }
    }
    if (points.isEmpty) return null;

    final placemarks = points
        .map((p) => '${p.longitude},${p.latitude},pm2blm')
        .join('~');
    return Uri.https('static-maps.yandex.ru', '/v1', {
      'apikey': _yandexStaticKey,
      'lang': 'tr_TR',
      'size': '650,420',
      'theme': 'light',
      'pt': placemarks,
    }).toString();
  }

  int get _foundAddressCount => _uniqueVisibleCustomers
      .where((job) => _resultFor(job).state == _AddressState.found)
      .length;

  int get _badAddressCount => _uniqueVisibleCustomers.where((job) {
        final state = _resultFor(job).state;
        return state == _AddressState.notFound || state == _AddressState.error;
      }).length;

  int get _uncheckedAddressCount => _uniqueVisibleCustomers.where((job) {
        final state = _resultFor(job).state;
        return state == _AddressState.unknown || state == _AddressState.checking;
      }).length;

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.manager,
      title: 'Bölgeler & Rota',
      subtitle: 'Servisleri bölgeye göre görün, haritada kontrol edin ve teknikerlere atayın.',
      dark: false,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Yenile'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : _content(),
    );
  }

  Widget _errorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'Toplu atama verileri yüklenemedi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(_error ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1120;
        final padding = constraints.maxWidth < 700 ? 10.0 : 14.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 10, padding, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _locationPanel(),
              const SizedBox(height: 12),
              if (isWide)
                SizedBox(
                  height: 760,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 440, child: _jobsPanel()),
                      const SizedBox(width: 12),
                      Expanded(child: _yandexPanel()),
                    ],
                  ),
                )
              else ...[
                SizedBox(height: 600, child: _jobsPanel()),
                const SizedBox(height: 12),
                SizedBox(height: 600, child: _yandexPanel()),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _chooseSmartTechnicians() async {
    if (_technicians.isEmpty) return;
    final draft = Set<String>.from(_smartTechnicianIds);
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Otomatik Dağıtım Teknikerleri'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'En fazla 3 tekniker seçin. MOTUS işleri sayıya göre değil, gerçek mesafe ve rota yakınlığına göre kümeler.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 12),
                ..._technicians.map((tech) {
                  final checked = draft.contains(tech.id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    title: Text(tech.fullName),
                    subtitle: Text('Bugünkü iş: ${_todayCountForTechnician(tech.id)}'),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          if (draft.length < 3) draft.add(tech.id);
                        } else {
                          draft.remove(tech.id);
                        }
                      });
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: draft.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, Set<String>.from(draft)),
              child: const Text('Seçimi Uygula'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _smartTechnicianIds
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _changeListMode(_DispatchListMode mode) async {
    if (_listMode == mode) return;
    setState(() {
      _listMode = mode;
      _selectedRequestIds.clear();
      _selectedTechnicianId = null;
    });
    await _validateVisibleAddresses();
    await _refreshEmbeddedYandex();
  }

  Widget _locationPanel() {
    final filteredTech = _filterTechnician;
    final districtLabel = _selectedDistricts.isEmpty ||
            _selectedDistricts.length == _districts.length
        ? 'Tümü (${_districts.length} ilçe)'
        : '${_selectedDistricts.length} ilçe seçili';
    final dateLabel = _selectedPlanDate == null
        ? 'Tüm Tarihler'
        : '${_selectedPlanDate!.day.toString().padLeft(2, '0')}.${_selectedPlanDate!.month.toString().padLeft(2, '0')}.${_selectedPlanDate!.year}';
    final summaryName = filteredTech?.fullName ?? 'Tüm Teknisyenler';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1180;

          final city = SizedBox(
            width: compact ? double.infinity : 180,
            child: DropdownButtonFormField<String>(
              value: _selectedCity,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'İl',
                prefixIcon: Icon(Icons.location_city_outlined, size: 19),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: _cities
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(growable: false),
              onChanged: _changeCity,
            ),
          );

          final district = SizedBox(
            width: compact ? double.infinity : 235,
            child: OutlinedButton.icon(
              onPressed: _selectedCity == null ? null : _chooseDistricts,
              icon: const Icon(Icons.location_on_outlined, size: 19),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(districtLabel, overflow: TextOverflow.ellipsis),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
            ),
          );

          final date = SizedBox(
            width: compact ? double.infinity : 170,
            child: OutlinedButton.icon(
              onPressed: _pickPlanDate,
              icon: const Icon(Icons.calendar_month_outlined, size: 19),
              label: Text(dateLabel, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
            ),
          );

          final technicianFilter = SizedBox(
            width: compact ? double.infinity : 235,
            child: DropdownButtonFormField<String?>(
              value: _filterTechnicianId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Teknisyen',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Tüm Teknisyenler')),
                ..._technicians.map((tech) => DropdownMenuItem<String?>(
                      value: tech.id,
                      child: Text(tech.fullName, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (value) async {
                setState(() {
                  _filterTechnicianId = value;
                  _selectedRequestIds.clear();
                });
                await _validateVisibleAddresses();
                await _refreshEmbeddedYandex();
              },
            ),
          );

          final summary = Container(
            constraints: const BoxConstraints(minWidth: 155),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5DFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(summaryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${_displayedJobs.length} iş • ${_uniqueVisibleCustomers.length} haritada',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ],
            ),
          );

          final smartPlan = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: _assigning ||
                        _validating ||
                        _unassignedVisibleJobs.isEmpty ||
                        _smartTechnicians.isEmpty
                    ? null
                    : _smartPlan,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Akıllı Rota Planla'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0797A9),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 1),
              FilledButton(
                onPressed: _assigning ? null : _chooseSmartTechnicians,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0797A9),
                  minimumSize: const Size(44, 52),
                  padding: EdgeInsets.zero,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(right: Radius.circular(10)),
                  ),
                ),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Expanded(child: city), const SizedBox(width: 8), Expanded(child: district)]),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: date), const SizedBox(width: 8), Expanded(child: technicianFilter)]),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: summary), const SizedBox(width: 8), smartPlan]),
              ],
            );
          }

          return Row(
            children: [
              city,
              const SizedBox(width: 8),
              district,
              const SizedBox(width: 8),
              date,
              if (_selectedPlanDate != null) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Tarih filtresini temizle',
                  onPressed: _clearPlanDate,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
              const SizedBox(width: 6),
              technicianFilter,
              const SizedBox(width: 8),
              Expanded(child: summary),
              const SizedBox(width: 8),
              smartPlan,
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickAssignmentTechnicianAndAssign() async {
    if (_selectedRequestIds.isEmpty || _assigning) return;
    String? pickedId = _selectedTechnicianId;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Teknisyen Değiştir / Ata'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<String>(
              value: pickedId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Teknisyen',
                prefixIcon: Icon(Icons.engineering_outlined),
              ),
              items: _technicians
                  .map((tech) => DropdownMenuItem(
                        value: tech.id,
                        child: Text(tech.fullName, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(growable: false),
              onChanged: (value) => setDialogState(() => pickedId = value),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: pickedId == null ? null : () => Navigator.pop(dialogContext, pickedId),
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selectedTechnicianId = result);
    await _assignSelected();
  }

  String _routeTimeLabel(ServiceRequestModel job) {
    final local = job.plannedDate?.toLocal();
    if (local == null) return 'Tarih yok';
    if (local.hour == 0 && local.minute == 0) return 'Gün içinde';
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _jobsPanel() {
    final jobs = _displayedJobs;
    final filteredTech = _filterTechnician;
    final allIds = jobs.map((e) => e.id).whereType<String>().toSet();
    final allSelected = allIds.isNotEmpty && _selectedRequestIds.containsAll(allIds);

    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    filteredTech == null
                        ? '$_selectedAreaLabel • İşler (${jobs.length})'
                        : '${filteredTech.fullName} • Atanan İşler (${jobs.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 118,
                  child: DropdownButtonFormField<String>(
                    value: _routeSort,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                    ),
                    selectedItemBuilder: (context) => const [
                      Align(alignment: Alignment.centerLeft, child: Text('Rota Sırası', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11))),
                      Align(alignment: Alignment.centerLeft, child: Text('Müşteri A-Z', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11))),
                      Align(alignment: Alignment.centerLeft, child: Text('İlçe A-Z', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11))),
                    ],
                    items: const [
                      DropdownMenuItem(value: 'route', child: Text('Rota Sırası')),
                      DropdownMenuItem(value: 'customer', child: Text('Müşteri A-Z')),
                      DropdownMenuItem(value: 'district', child: Text('İlçe A-Z')),
                    ],
                    onChanged: (value) => setState(() => _routeSort = value ?? 'route'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              onChanged: (value) async {
                setState(() => _routeSearch = value);
                await _refreshEmbeddedYandex();
              },
              decoration: const InputDecoration(
                hintText: 'Müşteri adı, adres veya telefon ara...',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1, color: _border),
          if (jobs.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Seçilen bölge ve teknisyene uygun servis yok.', style: TextStyle(color: _muted)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: jobs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: _border),
                itemBuilder: (context, index) => _jobRow(jobs[index], index),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFBFCFD),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: allIds.isEmpty
                      ? null
                      : (value) => setState(() {
                            if (value == true) {
                              _selectedRequestIds.addAll(allIds);
                            } else {
                              _selectedRequestIds.removeAll(allIds);
                            }
                          }),
                ),
                Text('${_selectedRequestIds.length} iş seçildi', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                OutlinedButton(
                  onPressed: _selectedRequestIds.isEmpty ? null : _pickAssignmentTechnicianAndAssign,
                  child: const Text('Teknisyen Değiştir'),
                ),
                OutlinedButton(
                  onPressed: _selectedRequestIds.isEmpty || _assigning ? null : _setSelectedDate,
                  child: const Text('Tarihi Değiştir'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedRequestIds.isEmpty || _assigning ? null : _unassignSelected,
                  icon: const Icon(Icons.delete_outline_rounded, size: 17),
                  label: const Text('Atamadan Çıkar'),
                  style: OutlinedButton.styleFrom(foregroundColor: _danger),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Expanded(child: _routeStat('Toplam İş', '${jobs.length}', 'Seçili görünüm')),
                Container(width: 1, height: 42, color: _border),
                Expanded(child: _routeStat('Tahmini Süre', _driveLabel(_displayedDriveMinutes), 'Rota sürüşü')),
                Container(width: 1, height: 42, color: _border),
                Expanded(child: _routeStat('Toplam Mesafe', '${_displayedRouteKm.toStringAsFixed(0)} km', 'Tahmini rota')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeStat(String title, String value, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _jobRow(ServiceRequestModel job, int index) {
    final id = job.id;
    final checked = id != null && _selectedRequestIds.contains(id);
    final order = job.routeOrder ?? (index + 1);
    final serviceLabel = job.plannedProductName.trim().isEmpty
        ? job.serviceType.label
        : '${job.serviceType.label} • ${job.plannedProductName.trim()}';

    return InkWell(
      onTap: id == null
          ? null
          : () async {
              setState(() {
                _selectedRequestIds
                  ..clear()
                  ..add(id);
              });
              await _refreshEmbeddedYandex();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: checked,
              onChanged: id == null
                  ? null
                  : (value) => setState(() {
                        if (value == true) {
                          _selectedRequestIds.add(id);
                        } else {
                          _selectedRequestIds.remove(id);
                        }
                      }),
            ),
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F0FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5DFFF)),
              ),
              child: Text('$order', style: const TextStyle(color: Color(0xFF7653D6), fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.customerName.isEmpty ? 'Müşteri' : job.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _serviceChip(serviceLabel),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.customerAddress.trim().isEmpty
                        ? '${job.customerDistrict} / ${job.customerCity}'
                        : job.customerAddress.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: _muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text('${job.customerDistrict} / ${job.customerCity}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 10)),
                      ),
                      if (job.customerPhone.trim().isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.phone_outlined, size: 12, color: _muted),
                        const SizedBox(width: 3),
                        Text(job.customerPhone, style: const TextStyle(color: _muted, fontSize: 10)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: Text(
                _routeTimeLabel(job),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF526277)),
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              tooltip: 'İşlemler',
              onSelected: (value) async {
                if (value == 'date') {
                  await _setOneDate(job);
                } else if (value == 'unassign') {
                  await _unassignOne(job);
                } else if (value == 'select') {
                  if (id != null) {
                    setState(() {
                      _selectedRequestIds
                        ..clear()
                        ..add(id);
                    });
                    await _pickAssignmentTechnicianAndAssign();
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'date', child: Row(children: [Icon(Icons.event_rounded), SizedBox(width: 10), Text('Tarihi Değiştir')])),
                if (_isAssigned(job))
                  const PopupMenuItem(value: 'unassign', child: Row(children: [Icon(Icons.undo_rounded), SizedBox(width: 10), Text('Atamayı Kaldır')])),
                const PopupMenuItem(value: 'select', child: Row(children: [Icon(Icons.swap_horiz_rounded), SizedBox(width: 10), Text('Teknisyen Değiştir')])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceChip(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 148),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: _panel2,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _border),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }

  Widget _addressChip(_AddressResult result) {
    late final IconData icon;
    late final Color color;
    late final String text;

    switch (result.state) {
      case _AddressState.found:
        icon = Icons.location_on_rounded;
        color = _success;
        text = 'Adres bulundu';
        break;
      case _AddressState.notFound:
        icon = Icons.location_off_outlined;
        color = _danger;
        text = 'Adres bulunamadı';
        break;
      case _AddressState.error:
        icon = Icons.warning_amber_rounded;
        color = _warning;
        text = 'Adres kontrol hatası';
        break;
      case _AddressState.checking:
        icon = Icons.sync_rounded;
        color = _blue;
        text = 'Kontrol ediliyor';
        break;
      case _AddressState.unknown:
        icon = Icons.help_outline_rounded;
        color = _muted;
        text = _yandexGeocoderKey.trim().isEmpty
            ? 'Haritaya gönderilecek'
            : 'Kontrol bekliyor';
        break;
    }

    return Tooltip(
      message: result.message ?? text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _rightColumn() {
    return Column(
      children: [
        _technicianPanel(),
        const SizedBox(height: 14),
        _yandexPanel(),
      ],
    );
  }

  Widget _technicianPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.engineering_outlined, color: _teal),
              SizedBox(width: 8),
              Text('Tekniker Seç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedTechnicianId,
            decoration: const InputDecoration(
              labelText: 'Tekniker',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            items: _technicians.map((tech) {
              final today = _todayCountForTechnician(tech.id);
              return DropdownMenuItem(
                value: tech.id,
                child: Text('${tech.fullName} • Bugünkü iş: $today'),
              );
            }).toList(growable: false),
            onChanged: (value) =>
                setState(() => _selectedTechnicianId = value),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _panel2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toplu atama sadece teknikeri değiştirir. Sekreterin girdiği servis türü, planlanan tarih, ürünler, tutar ve açıklamalar değiştirilmez.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 430;
              final clearButton = OutlinedButton.icon(
                onPressed: () => setState(() {
                  _selectedRequestIds.clear();
                  _selectedTechnicianId = null;
                }),
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Seçimi Temizle'),
              );
              final assignButton = FilledButton.icon(
                onPressed: _assigning ||
                        _selectedTechnicianId == null ||
                        _selectedRequestIds.isEmpty
                    ? null
                    : _assignSelected,
                icon: _assigning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _selectedRequestIds.isEmpty
                      ? 'İş Seçin'
                      : '${_selectedRequestIds.length} İşi Ata',
                ),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    clearButton,
                    const SizedBox(height: 8),
                    assignButton,
                  ],
                );
              }
              return Row(
                children: [
                  clearButton,
                  const SizedBox(width: 10),
                  Expanded(child: assignButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _yandexPanel() {
    Widget mapBody() {
      if (Platform.isWindows && _yandexWebReady) {
        return _embeddedYandexMap(expand: true);
      }
      final staticUrl = _staticMapUrl;
      if (staticUrl != null) {
        return Image.network(
          staticUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _embeddedYandexMap(expand: true),
        );
      }
      return _embeddedYandexMap(expand: true);
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: mapBody()),
          Positioned(
            left: 14,
            top: 14,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border),
                boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 10)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_rounded, color: Color(0xFF7653D6), size: 18),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      '$_selectedAreaLabel • ${_displayedJobs.length} iş • ${_uniqueVisibleCustomers.length} nokta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: Row(
              children: [
                Material(
                  color: Colors.white.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(10),
                  child: IconButton(
                    tooltip: 'Haritayı Yenile',
                    onPressed: _displayedJobs.isEmpty
                        ? null
                        : () async {
                            if (_yandexGeocoderKey.trim().isNotEmpty) {
                              await _validateVisibleAddresses(force: true);
                            }
                            _lastEmbeddedYandexUrl = null;
                            await _refreshEmbeddedYandex();
                          },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const SizedBox(width: 7),
                Material(
                  color: Colors.white.withValues(alpha: .95),
                  borderRadius: BorderRadius.circular(10),
                  child: TextButton.icon(
                    onPressed: _displayedJobs.isEmpty ? null : () => _openInYandex(selectedOnly: false),
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Yandex’te Aç'),
                  ),
                ),
              ],
            ),
          ),
          if (_validating)
            const Positioned(
              right: 18,
              bottom: 18,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Adresler kontrol ediliyor...'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _embeddedYandexMap({bool expand = false}) {
    Widget content;
    if (Platform.isWindows && _yandexWebReady) {
      content = Webview(_yandexWebController);
    } else {
      content = _mapPlaceholder(
        'Yandex haritası Windows uygulamasında otomatik açılır. '
        'Bu platformda Yandex’te Aç düğmesini kullanabilirsiniz.',
      );
    }
    return expand ? SizedBox.expand(child: content) : SizedBox(height: 520, child: content);
  }

  Widget _mapPlaceholder(String text) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      color: const Color(0xFF0B1721),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_outlined, size: 48, color: _muted),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _bottomStats() {
    final unassigned =
        _cityRequests.where((r) => r.assignedTechnicianId == null).length;
    final assigned =
        _cityRequests.where((r) => r.assignedTechnicianId != null).length;
    final stats = [
      (Icons.assignment_late_outlined, 'Atanmamış İş', '$unassigned', _blue),
      (Icons.payments_outlined, 'Tahmini Ciro', _money(_sum(_cityRequests)), _success),
      (Icons.engineering_outlined, 'Aktif Tekniker', '${_technicians.length}', const Color(0xFF9A67FF)),
      (Icons.assignment_turned_in_outlined, 'Atanmış İş', '$assigned', _warning),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: stats
          .map(
            (s) => Container(
              width: 220,
              height: 92,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: s.$4.withValues(alpha: .13),
                    child: Icon(s.$1, color: s.$4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.$2,
                            style: const TextStyle(color: _muted, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(s.$3,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
