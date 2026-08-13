import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/app_role.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../settings/data/company_app_settings.dart';
import '../../data/models/customer_model.dart';
import '../controllers/customer_controller.dart';
import '../providers/customer_providers.dart';
import 'customer_module_shell.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  static final Map<AppRole, String?> _lastSelectedCustomerByRole = <AppRole, String?>{};

  final _nameSearch = TextEditingController();
  final _phoneSearch = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  Timer? _filterDebounce;

  bool? _active = true;
  CustomerModel? _selectedCustomer;
  int? _activeCustomerCount;
  bool _loadingCount = true;
  List<String> _cities = const <String>[];
  Map<String, List<String>> _districtsByCity = const <String, List<String>>{};

  String _prefix() {
    if (widget.role == AppRole.secretary) return '/secretary';
    if (widget.role == AppRole.technician) return '/technician';
    return '/manager';
  }

  @override
  void initState() {
    super.initState();
    final saved = ref.read(customerControllerProvider).state;
    _nameSearch.text = saved.search;
    _phoneSearch.text = saved.phone;
    _city.text = saved.city;
    _district.text = saved.district;
    final hasSavedListState = saved.customers.isNotEmpty ||
        saved.search.isNotEmpty ||
        saved.phone.isNotEmpty ||
        saved.city.isNotEmpty ||
        saved.district.isNotEmpty ||
        saved.page > 1;
    _active = hasSavedListState ? saved.isActive : true;

    if (saved.customers.isNotEmpty) {
      final wantedId = _lastSelectedCustomerByRole[widget.role];
      _selectedCustomer = saved.customers.cast<CustomerModel?>().firstWhere(
            (customer) => customer?.id == wantedId,
            orElse: () => saved.customers.first,
          );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(customerControllerProvider);
      if (controller.state.customers.isEmpty && !controller.state.isLoading) {
        await _applyFilters();
      }
      if (!mounted) return;
      await Future.wait<void>([
        _refreshActiveCustomerCount(),
        _loadLocationOptions(),
      ]);
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _nameSearch.dispose();
    _phoneSearch.dispose();
    _city.dispose();
    _district.dispose();
    super.dispose();
  }

  void _scheduleFilters([Duration delay = const Duration(milliseconds: 280)]) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(delay, () {
      if (mounted) _applyFilters();
    });
  }

  Future<void> _applyFilters() async {
    final controller = ref.read(customerControllerProvider);
    await controller.loadCustomers(
      search: _nameSearch.text,
      phone: _phoneSearch.text,
      city: _city.text,
      district: _district.text,
      isActive: _active,
      resetPage: true,
    );
    if (!mounted) return;
    _syncSelectedCustomer(controller.state.customers);
  }

  Future<void> _clearFilters() async {
    _nameSearch.clear();
    _phoneSearch.clear();
    _city.clear();
    _district.clear();
    setState(() => _active = true);
    await _applyFilters();
  }

  Future<void> _refreshAll() async {
    final controller = ref.read(customerControllerProvider);
    await Future.wait<void>([
      controller.loadCustomers(
        search: _nameSearch.text,
        phone: _phoneSearch.text,
        city: _city.text,
        district: _district.text,
        isActive: _active,
        resetPage: false,
      ),
      _refreshActiveCustomerCount(),
      _loadLocationOptions(),
    ]);
    if (!mounted) return;
    _syncSelectedCustomer(controller.state.customers);
  }

  Future<void> _goToPage(int page) async {
    final controller = ref.read(customerControllerProvider);
    await controller.loadPage(page);
    if (!mounted) return;
    _syncSelectedCustomer(controller.state.customers);
  }

  void _syncSelectedCustomer(List<CustomerModel> customers) {
    if (!mounted) return;
    if (customers.isEmpty) {
      setState(() => _selectedCustomer = null);
      return;
    }
    final selectedId = _lastSelectedCustomerByRole[widget.role];
    CustomerModel? selected;
    if (selectedId != null) {
      for (final customer in customers) {
        if (customer.id == selectedId) {
          selected = customer;
          break;
        }
      }
    }
    selected ??= customers.first;
    _lastSelectedCustomerByRole[widget.role] = selected.id;
    setState(() => _selectedCustomer = selected);
  }

  void _selectCustomer(CustomerModel customer) {
    _lastSelectedCustomerByRole[widget.role] = customer.id;
    setState(() => _selectedCustomer = customer);
  }

  Future<Map<String, String?>> _viewerContext() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return const <String, String?>{'id': null, 'role': null, 'companyId': null};
    try {
      final row = await client
          .from('profiles')
          .select('id, role, company_id')
          .eq('id', user.id)
          .maybeSingle();
      return <String, String?>{
        'id': row?['id']?.toString() ?? user.id,
        'role': row?['role']?.toString(),
        'companyId': row?['company_id']?.toString(),
      };
    } catch (_) {
      return <String, String?>{'id': user.id, 'role': null, 'companyId': null};
    }
  }

  Future<void> _refreshActiveCustomerCount() async {
    if (mounted) setState(() => _loadingCount = true);
    try {
      final client = Supabase.instance.client;
      final viewer = await _viewerContext();
      const pageSize = 1000;
      var offset = 0;
      var total = 0;
      while (true) {
        dynamic query = client
            .from('customers')
            .select('id')
            .eq('is_active', true)
            .filter('deleted_at', 'is', null);
        if (viewer['companyId'] != null && viewer['companyId']!.isNotEmpty) {
          query = query.eq('company_id', viewer['companyId']!);
        }
        if (viewer['role'] == 'secretary' && viewer['id'] != null) {
          query = query.eq('created_by', viewer['id']!);
        }
        final rows = List<Map<String, dynamic>>.from(
          await query.range(offset, offset + pageSize - 1),
        );
        total += rows.length;
        if (rows.length < pageSize) break;
        offset += pageSize;
      }
      if (!mounted) return;
      setState(() {
        _activeCustomerCount = total;
        _loadingCount = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCount = false);
    }
  }

  Future<void> _loadLocationOptions() async {
    try {
      final client = Supabase.instance.client;
      final viewer = await _viewerContext();
      final cities = <String>{};
      final districts = <String, Set<String>>{};
      const pageSize = 1000;
      var offset = 0;
      while (true) {
        dynamic query = client
            .from('customers')
            .select('city, district')
            .filter('deleted_at', 'is', null);
        if (viewer['companyId'] != null && viewer['companyId']!.isNotEmpty) {
          query = query.eq('company_id', viewer['companyId']!);
        }
        if (viewer['role'] == 'secretary' && viewer['id'] != null) {
          query = query.eq('created_by', viewer['id']!);
        }
        final rows = List<Map<String, dynamic>>.from(
          await query.range(offset, offset + pageSize - 1),
        );
        for (final row in rows) {
          final city = row['city']?.toString().trim() ?? '';
          final district = row['district']?.toString().trim() ?? '';
          if (city.isEmpty) continue;
          cities.add(city);
          if (district.isNotEmpty) {
            districts.putIfAbsent(city, () => <String>{}).add(district);
          }
        }
        if (rows.length < pageSize) break;
        offset += pageSize;
      }
      if (!mounted) return;
      final sortedCities = cities.toList()..sort(_trCompare);
      final sortedDistricts = <String, List<String>>{};
      for (final entry in districts.entries) {
        sortedDistricts[entry.key] = entry.value.toList()..sort(_trCompare);
      }
      setState(() {
        _cities = sortedCities;
        _districtsByCity = sortedDistricts;
      });
    } catch (_) {
      // Filtre seçenekleri yüklenemezse mevcut metinler korunur; liste çalışmaya devam eder.
    }
  }

  static int _trCompare(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider).state;
    final appSettings = ref.watch(companyAppSettingsProvider).asData?.value ??
        const CompanyAppSettings(companyId: '');
    final canView = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_view_customers', fallback: true)
            : appSettings.permission('technician_view_customers', fallback: true));
    final canEdit = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_edit_customers', fallback: true)
            : appSettings.permission('technician_edit_customers', fallback: true));
    final canCreateService = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_create_service', fallback: true)
            : appSettings.permission('technician_create_service'));

    return CustomerModuleShell(
      role: widget.role,
      title: 'Müşteriler',
      actions: <Widget>[
        if (widget.role != AppRole.technician && canEdit)
          FilledButton.icon(
            onPressed: () => context.go('${_prefix()}/customers/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Yeni Müşteri'),
          ),
        if (widget.role == AppRole.manager || widget.role == AppRole.admin) ...<Widget>[
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/manager/excel-transfer'),
            icon: const Icon(Icons.file_present_outlined, size: 18),
            label: const Text('Excel Aktar'),
          ),
        ],
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _refreshAll,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: !canView
          ? const Center(child: Text('Bu kullanıcı için müşteri listesi görüntüleme yetkisi kapalı.'))
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                children: <Widget>[
                  const Text(
                    'Tüm müşterilerinizi görüntüleyin ve yönetin.',
                    style: TextStyle(color: Color(0xFF66778A), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  _ActiveCustomersCard(
                    count: _activeCustomerCount,
                    loading: _loadingCount,
                    onShowAll: () async {
                      _nameSearch.clear();
                      _phoneSearch.clear();
                      _city.clear();
                      _district.clear();
                      setState(() => _active = true);
                      await _applyFilters();
                    },
                  ),
                  const SizedBox(height: 18),
                  _CustomerFilterBar(
                    nameSearch: _nameSearch,
                    phoneSearch: _phoneSearch,
                    city: _city,
                    district: _district,
                    active: _active,
                    cities: _cities,
                    districtsByCity: _districtsByCity,
                    onQueryChanged: _scheduleFilters,
                    onCityChanged: (value) {
                      _city.text = value ?? '';
                      _district.clear();
                      setState(() {});
                      _scheduleFilters(const Duration(milliseconds: 80));
                    },
                    onDistrictChanged: (value) {
                      _district.text = value ?? '';
                      setState(() {});
                      _scheduleFilters(const Duration(milliseconds: 80));
                    },
                    onActiveChanged: (value) {
                      setState(() => _active = value);
                      _scheduleFilters(const Duration(milliseconds: 80));
                    },
                    onApply: _applyFilters,
                    onClear: _clearFilters,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final showPreview = constraints.maxWidth >= 1080;
                      final listPanel = _CustomerListPanel(
                        state: state,
                        selectedCustomerId: _selectedCustomer?.id,
                        canEdit: canEdit,
                        canCreateService: canCreateService,
                        onSelect: _selectCustomer,
                        onOpen: (customer) => context.go('${_prefix()}/customers/${customer.id}'),
                        onEdit: (customer) => context.go('${_prefix()}/customers/${customer.id}/edit'),
                        onService: (customer) => context.go('${_prefix()}/service-requests/new/${customer.id}'),
                        onPreviousPage: state.page > 1 ? () => _goToPage(state.page - 1) : null,
                        onNextPage: state.hasMore ? () => _goToPage(state.page + 1) : null,
                      );

                      if (!showPreview) {
                        return Column(
                          children: <Widget>[
                            listPanel,
                            const SizedBox(height: 14),
                            _CustomerPreview(
                              customer: _selectedCustomer,
                              canEdit: canEdit,
                              canCreateService: canCreateService,
                              onOpen: (customer) => context.go('${_prefix()}/customers/${customer.id}'),
                              onEdit: (customer) => context.go('${_prefix()}/customers/${customer.id}/edit'),
                              onService: (customer) => context.go('${_prefix()}/service-requests/new/${customer.id}'),
                            ),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 8, child: listPanel),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 330,
                            child: _CustomerPreview(
                              customer: _selectedCustomer,
                              canEdit: canEdit,
                              canCreateService: canCreateService,
                              onOpen: (customer) => context.go('${_prefix()}/customers/${customer.id}'),
                              onEdit: (customer) => context.go('${_prefix()}/customers/${customer.id}/edit'),
                              onService: (customer) => context.go('${_prefix()}/service-requests/new/${customer.id}'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _ActiveCustomersCard extends StatelessWidget {
  const _ActiveCustomersCard({
    required this.count,
    required this.loading,
    required this.onShowAll,
  });

  final int? count;
  final bool loading;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5EC)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFE1F7F8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_2_outlined, color: Color(0xFF0CB6C3), size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Aktif Müşteriler', style: TextStyle(color: Color(0xFF66778A), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  loading ? '—' : _formatInteger(count ?? 0),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF102033)),
                ),
                const Text('Sistemdeki toplam aktif müşteri', style: TextStyle(color: Color(0xFF66778A), fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onShowAll,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Tümünü Görüntüle'),
          ),
        ],
      ),
    );
  }
}

class _CustomerFilterBar extends StatelessWidget {
  const _CustomerFilterBar({
    required this.nameSearch,
    required this.phoneSearch,
    required this.city,
    required this.district,
    required this.active,
    required this.cities,
    required this.districtsByCity,
    required this.onQueryChanged,
    required this.onCityChanged,
    required this.onDistrictChanged,
    required this.onActiveChanged,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController nameSearch;
  final TextEditingController phoneSearch;
  final TextEditingController city;
  final TextEditingController district;
  final bool? active;
  final List<String> cities;
  final Map<String, List<String>> districtsByCity;
  final VoidCallback onQueryChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<String?> onDistrictChanged;
  final ValueChanged<bool?> onActiveChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final selectedCity = city.text.trim();
    final allDistricts = districtsByCity.values.expand((items) => items).toSet().toList()
      ..sort(_CustomerListScreenState._trCompare);
    final districtItems = selectedCity.isEmpty
        ? allDistricts
        : (districtsByCity[selectedCity] ?? const <String>[]);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EC)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1050;
          final fieldWidth = compact ? (constraints.maxWidth - 12) / 2 : 190.0;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: <Widget>[
              _LabeledField(
                label: 'Müşteri Adı / Soyadı',
                width: compact ? fieldWidth : 220,
                child: TextField(
                  controller: nameSearch,
                  onChanged: (_) => onQueryChanged(),
                  onSubmitted: (_) => onApply(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Ad veya soyad ara...',
                  ),
                ),
              ),
              _LabeledField(
                label: 'Telefon',
                width: fieldWidth,
                child: TextField(
                  controller: phoneSearch,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => onQueryChanged(),
                  onSubmitted: (_) => onApply(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone_outlined, size: 19),
                    hintText: 'Telefon numarası ara...',
                  ),
                ),
              ),
              _LabeledField(
                label: 'İl',
                width: compact ? fieldWidth : 145,
                child: DropdownButtonFormField<String>(
                  value: selectedCity.isEmpty || !cities.contains(selectedCity) ? '' : selectedCity,
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(value: '', child: Text('İl seçin')),
                    ...cities.map((value) => DropdownMenuItem<String>(value: value, child: Text(value))),
                  ],
                  onChanged: onCityChanged,
                ),
              ),
              _LabeledField(
                label: 'İlçe',
                width: compact ? fieldWidth : 155,
                child: DropdownButtonFormField<String>(
                  value: district.text.isEmpty || !districtItems.contains(district.text) ? '' : district.text,
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(value: '', child: Text('İlçe seçin')),
                    ...districtItems.map((value) => DropdownMenuItem<String>(value: value, child: Text(value))),
                  ],
                  onChanged: onDistrictChanged,
                ),
              ),
              _LabeledField(
                label: 'Durum',
                width: compact ? fieldWidth : 145,
                child: DropdownButtonFormField<bool?>(
                  value: active,
                  isExpanded: true,
                  decoration: const InputDecoration(),
                  items: const <DropdownMenuItem<bool?>>[
                    DropdownMenuItem<bool?>(value: true, child: Text('Aktif')),
                    DropdownMenuItem<bool?>(value: false, child: Text('Pasif')),
                    DropdownMenuItem<bool?>(value: null, child: Text('Tümü')),
                  ],
                  onChanged: onActiveChanged,
                ),
              ),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: const Text('Filtrele'),
                ),
              ),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Temizle'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.width, required this.child});

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334E68))),
          ),
          SizedBox(height: 46, child: child),
        ],
      ),
    );
  }
}

class _CustomerListPanel extends StatelessWidget {
  const _CustomerListPanel({
    required this.state,
    required this.selectedCustomerId,
    required this.canEdit,
    required this.canCreateService,
    required this.onSelect,
    required this.onOpen,
    required this.onEdit,
    required this.onService,
    required this.onPreviousPage,
    required this.onNextPage,
  });

  final CustomerState state;
  final String? selectedCustomerId;
  final bool canEdit;
  final bool canCreateService;
  final ValueChanged<CustomerModel> onSelect;
  final ValueChanged<CustomerModel> onOpen;
  final ValueChanged<CustomerModel> onEdit;
  final ValueChanged<CustomerModel> onService;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    final customers = state.customers;
    final page = state.page;
    final pageSize = state.pageSize;
    final start = customers.isEmpty ? 0 : ((page - 1) * pageSize) + 1;
    final end = customers.isEmpty ? 0 : start + customers.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EC)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: <Widget>[
                Text(
                  '${customers.length} müşteri',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334E68)),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFD9E3EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$pageSize', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 7),
                const Text('kayıt göster', style: TextStyle(fontSize: 12, color: Color(0xFF66778A))),
                const Spacer(),
                IconButton(
                  tooltip: 'Önceki sayfa',
                  onPressed: onPreviousPage,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF08AFC0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$page', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Sonraki sayfa',
                  onPressed: onNextPage,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(64),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(child: Text(state.errorMessage.toString())),
            )
          else if (customers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(64),
              child: Center(child: Text('Kayıt bulunamadı.')),
            )
          else
            _CustomerTable(
              customers: customers,
              selectedCustomerId: selectedCustomerId,
              canEdit: canEdit,
              canCreateService: canCreateService,
              onSelect: onSelect,
              onOpen: onOpen,
              onEdit: onEdit,
              onService: onService,
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                Text(
                  customers.isEmpty ? '0 kayıt gösteriliyor' : '$start - $end kayıt gösteriliyor',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF66778A)),
                ),
                const Spacer(),
                Text(
                  'Sayfa $page',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334E68)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({
    required this.customers,
    required this.selectedCustomerId,
    required this.canEdit,
    required this.canCreateService,
    required this.onSelect,
    required this.onOpen,
    required this.onEdit,
    required this.onService,
  });

  final List<CustomerModel> customers;
  final String? selectedCustomerId;
  final bool canEdit;
  final bool canCreateService;
  final ValueChanged<CustomerModel> onSelect;
  final ValueChanged<CustomerModel> onOpen;
  final ValueChanged<CustomerModel> onEdit;
  final ValueChanged<CustomerModel> onService;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 850) {
      return Column(
        children: customers.map((customer) {
          return ListTile(
            selected: customer.id == selectedCustomerId,
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF10B8C4),
              child: Text(_initials(customer.displayName), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            title: Text(customer.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${customer.phone}\n${customer.city ?? '-'} / ${customer.district ?? '-'}'),
            isThreeLine: true,
            trailing: IconButton(icon: const Icon(Icons.visibility_outlined), onPressed: () => onOpen(customer)),
            onTap: () => onSelect(customer),
          );
        }).toList(growable: false),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: true,
              headingRowHeight: 46,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 64,
              columnSpacing: 28,
              horizontalMargin: 16,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FBFC)),
              columns: const <DataColumn>[
                DataColumn(label: Text('Müşteri')),
                DataColumn(label: Text('Telefon')),
                DataColumn(label: Text('İl / İlçe')),
                DataColumn(label: Text('Durum')),
                DataColumn(label: Text('Kayıt Tarihi')),
                DataColumn(label: Text('İşlemler')),
              ],
              rows: customers.map((customer) {
                final isSelected = customer.id == selectedCustomerId;
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (_) => onSelect(customer),
                  cells: <DataCell>[
                    DataCell(
                      Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: const Color(0xFF10B8C4),
                            child: Text(
                              _initials(customer.displayName),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(customer.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                    DataCell(Text(customer.phone)),
                    DataCell(Text('${customer.city ?? '-'} / ${customer.district ?? '-'}')),
                    DataCell(_StatusBadge(active: customer.isActive)),
                    DataCell(Text(_formatDate(customer.registrationDate ?? customer.createdAt))),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(tooltip: 'Müşteri kartı', onPressed: () => onOpen(customer), icon: const Icon(Icons.visibility_outlined, size: 20)),
                          if (canEdit)
                            PopupMenuButton<String>(
                              tooltip: 'İşlemler',
                              icon: const Icon(Icons.more_vert_rounded, size: 20),
                              onSelected: (value) {
                                if (value == 'edit') onEdit(customer);
                                if (value == 'service') onService(customer);
                              },
                              itemBuilder: (context) => <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(value: 'edit', child: Text('Düzenle')),
                                if (canCreateService) const PopupMenuItem<String>(value: 'service', child: Text('Servis Aç')),
                              ],
                            )
                          else if (canCreateService)
                            IconButton(tooltip: 'Servis aç', onPressed: () => onService(customer), icon: const Icon(Icons.add_task_outlined, size: 20)),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerPreview extends StatefulWidget {
  const _CustomerPreview({
    required this.customer,
    required this.canEdit,
    required this.canCreateService,
    required this.onOpen,
    required this.onEdit,
    required this.onService,
  });

  final CustomerModel? customer;
  final bool canEdit;
  final bool canCreateService;
  final ValueChanged<CustomerModel> onOpen;
  final ValueChanged<CustomerModel> onEdit;
  final ValueChanged<CustomerModel> onService;

  @override
  State<_CustomerPreview> createState() => _CustomerPreviewState();
}

class _CustomerPreviewState extends State<_CustomerPreview> {
  Future<List<_RecentService>>? _recentServices;

  @override
  void initState() {
    super.initState();
    _syncFuture();
  }

  @override
  void didUpdateWidget(covariant _CustomerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer?.id != widget.customer?.id) _syncFuture();
  }

  void _syncFuture() {
    final id = widget.customer?.id;
    _recentServices = id == null
        ? Future<List<_RecentService>>.value(const <_RecentService>[])
        : _loadRecentServices(id);
  }

  Future<List<_RecentService>> _loadRecentServices(String customerId) async {
    final client = Supabase.instance.client;
    final items = <_RecentService>[];

    try {
      final rows = List<Map<String, dynamic>>.from(
        await client
            .from('service_requests')
            .select('id, service_type, status, price, planned_date, created_at, updated_at')
            .eq('customer_id', customerId)
            .order('created_at', ascending: false)
            .limit(10),
      );
      items.addAll(rows.map(_RecentService.fromMap));
    } catch (_) {
      // Güncel servis tablosu eski müşterilerde boş olabilir.
    }

    try {
      final history = await MaintenanceRepository(client).getCustomerRecords(customerId);
      for (final record in history.where((item) => item.serviceId == null)) {
        items.add(
          _RecentService(
            typeLabel: record.productName,
            statusLabel: 'Tamamlandı',
            price: record.amount,
            date: record.performedAt,
          ),
        );
      }
    } catch (_) {
      // Bakım geçmişi bir eski tablo yüzünden yüklenemezse Excel satışlarını doğrudan dene.
      try {
        final legacyRows = List<Map<String, dynamic>>.from(
          await client
              .from('historical_customer_sales')
              .select('product_name, amount, transaction_date')
              .eq('customer_id', customerId)
              .order('transaction_date', ascending: false)
              .limit(10),
        );
        for (final row in legacyRows) {
          items.add(
            _RecentService(
              typeLabel: row['product_name']?.toString().trim().isNotEmpty == true
                  ? row['product_name'].toString()
                  : 'Eski İşlem',
              statusLabel: 'Tamamlandı',
              price: (row['amount'] as num?)?.toDouble() ?? 0,
              date: DateTime.tryParse(row['transaction_date']?.toString() ?? ''),
            ),
          );
        }
      } catch (_) {
        // Eski kayıt tablosu da yoksa güncel servisler yine gösterilir.
      }
    }

    items.sort((a, b) {
      final ad = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return items.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    return Container(
      constraints: const BoxConstraints(minHeight: 560),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EC)),
      ),
      child: customer == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.person_search_outlined, size: 46, color: Color(0xFF9BAABA)),
                  SizedBox(height: 10),
                  Text('Müşteri seçin', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Soldaki listeden bir müşteri seçin.', style: TextStyle(fontSize: 12, color: Color(0xFF66778A))),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF10B8C4),
                      child: Text(_initials(customer.displayName), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(customer.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
                          const SizedBox(height: 5),
                          _StatusBadge(active: customer.isActive),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                _PreviewLine(
                  icon: Icons.phone_outlined,
                  text: customer.phone,
                  trailing: IconButton(
                    tooltip: 'WhatsApp',
                    onPressed: () async {
                      final uri = Uri.parse(customer.whatsappUrl);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.chat_rounded, size: 18, color: Color(0xFF13A95A)),
                  ),
                ),
                _PreviewLine(icon: Icons.location_on_outlined, text: '${customer.city ?? '-'} / ${customer.district ?? '-'}'),
                _PreviewLine(icon: Icons.apartment_outlined, text: customer.address.trim().isEmpty ? 'Adres eklenmemiş' : customer.address),
                _PreviewLine(icon: Icons.notes_outlined, text: customer.notes?.trim().isNotEmpty == true ? customer.notes! : 'Not eklenmemiş'),
                _PreviewLine(icon: Icons.calendar_month_outlined, text: 'Kayıt Tarihi: ${_formatDate(customer.registrationDate ?? customer.createdAt)}'),
                _PreviewLine(icon: Icons.badge_outlined, text: 'Müşteri No: M-${_shortId(customer.id)}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () => widget.onOpen(customer),
                      icon: const Icon(Icons.person_outline_rounded, size: 17),
                      label: const Text('Müşteri Kartı'),
                    ),
                    if (widget.canEdit)
                      OutlinedButton.icon(
                        onPressed: () => widget.onEdit(customer),
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('Düzenle'),
                      ),
                    if (widget.canCreateService)
                      OutlinedButton.icon(
                        onPressed: () => widget.onService(customer),
                        icon: const Icon(Icons.handyman_outlined, size: 17),
                        label: const Text('Servis Aç'),
                      ),
                  ],
                ),
                const Divider(height: 30),
                Row(
                  children: <Widget>[
                    const Text('Son İşlemler', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
                    const Spacer(),
                    TextButton(onPressed: () => widget.onOpen(customer), child: const Text('Tümünü Gör')),
                  ],
                ),
                FutureBuilder<List<_RecentService>>(
                  future: _recentServices,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final services = snapshot.data ?? const <_RecentService>[];
                    if (services.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
                        child: const Text('Henüz servis işlemi yok.', style: TextStyle(fontSize: 12, color: Color(0xFF66778A))),
                      );
                    }
                    return Column(
                      children: services.map((service) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => widget.onOpen(customer),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE2E8EE)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          service.typeLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      _ServiceStatusBadge(label: service.statusLabel),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: <Widget>[
                                      Text(_formatDate(service.date), style: const TextStyle(fontSize: 12, color: Color(0xFF66778A))),
                                      const Spacer(),
                                      if (service.price > 0)
                                        Text(_formatMoney(service.price), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF102033))),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right_rounded, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onOpen(customer),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                    label: const Text('Tüm Geçmişi Görüntüle'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: const Color(0xFF60758A)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFF334E68), height: 1.35))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF14975A) : const Color(0xFFC64A4A);
    final background = active ? const Color(0xFFE4F7ED) : const Color(0xFFFFE8E8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Text(active ? 'Aktif' : 'Pasif', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _ServiceStatusBadge extends StatelessWidget {
  const _ServiceStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final completed = label == 'Tamamlandı';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: completed ? const Color(0xFFE3F7EC) : const Color(0xFFE8EEFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: completed ? const Color(0xFF14975A) : const Color(0xFF5267C9),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecentService {
  const _RecentService({
    required this.typeLabel,
    required this.statusLabel,
    required this.price,
    required this.date,
  });

  final String typeLabel;
  final String statusLabel;
  final double price;
  final DateTime? date;

  factory _RecentService.fromMap(Map<String, dynamic> map) {
    return _RecentService(
      typeLabel: _serviceTypeLabel(map['service_type']?.toString()),
      statusLabel: _serviceStatusLabel(map['status']?.toString()),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      date: DateTime.tryParse(
        map['planned_date']?.toString() ??
            map['updated_at']?.toString() ??
            map['created_at']?.toString() ??
            '',
      ),
    );
  }
}

String _serviceTypeLabel(String? value) {
  switch (value) {
    case 'filter_change':
      return 'Filtre Değişimi';
    case 'installation':
    case 'new_installation':
      return 'Yeni Kurulum';
    case 'fault':
    case 'repair':
      return 'Arıza';
    case 'maintenance':
      return 'Bakım';
    case 'service':
      return 'Servis';
    default:
      final text = value?.trim() ?? '';
      return text.isEmpty ? 'Servis İşlemi' : text;
  }
}

String _serviceStatusLabel(String? value) {
  switch (value) {
    case 'completed':
      return 'Tamamlandı';
    case 'cancelled':
    case 'canceled':
      return 'İptal';
    case 'in_progress':
      return 'Devam Ediyor';
    case 'assigned':
      return 'Teknisyende';
    case 'pending':
    case 'awaiting_approval':
      return 'Bekliyor';
    default:
      return 'Servis';
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList(growable: false);
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

String _shortId(String? id) {
  final value = id?.replaceAll('-', '') ?? '';
  if (value.isEmpty) return '000000';
  return value.length <= 8 ? value.toUpperCase() : value.substring(0, 8).toUpperCase();
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
}

String _formatMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '₺${buffer.toString()},${parts[1]}';
}

String _formatInteger(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
