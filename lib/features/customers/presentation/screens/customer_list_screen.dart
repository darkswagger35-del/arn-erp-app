import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/app_role.dart';
import '../providers/customer_providers.dart';
import '../../data/models/customer_model.dart';
import '../../../settings/data/company_app_settings.dart';
import 'customer_module_shell.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key, required this.role});
  final AppRole role;

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _search = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  bool? _active = true;
  DateTime? _startDate;
  DateTime? _endDate;
  CustomerModel? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void dispose() {
    _search.dispose();
    _city.dispose();
    _district.dispose();
    super.dispose();
  }

  String _prefix() => widget.role == AppRole.secretary ? '/secretary' : widget.role == AppRole.technician ? '/technician' : '/manager';

  void _apply() {
    ref.read(customerControllerProvider).loadCustomers(
      search: _search.text,
      city: _city.text,
      district: _district.text,
      isActive: _active,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  void _clear() {
    _search.clear();
    _city.clear();
    _district.clear();
    setState(() {
      _active = true;
      _startDate = null;
      _endDate = null;
    });
    _apply();
  }


  Future<void> _pickDate({required bool start}) async {
    final initial = start ? (_startDate ?? DateTime.now()) : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Başlangıç tarihi' : 'Bitiş tarihi',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_startDate != null && _startDate!.isAfter(picked)) _startDate = picked;
      }
    });
    _apply();
  }

  String _dateText(DateTime? value, String fallback) {
    if (value == null) return fallback;
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider).state;
    final controller = ref.read(customerControllerProvider);
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
    final customers = state.customers;
    final previewCustomer = _selectedCustomer ?? (customers.isNotEmpty ? customers.first : null);
    final activeCount = customers.where((e) => e.isActive).length;
    final thisMonth = customers.where((e) {
      final d = e.registrationDate ?? e.createdAt;
      final n = DateTime.now();
      return d != null && d.year == n.year && d.month == n.month;
    }).length;

    return CustomerModuleShell(
      role: widget.role,
      title: 'Müşteriler',
      actions: [
        if (widget.role != AppRole.technician && canEdit)
          FilledButton.icon(
            onPressed: () => context.go('${_prefix()}/customers/new'),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Müşteri'),
          ),
        const SizedBox(width: 10),
        IconButton(onPressed: controller.refresh, icon: const Icon(Icons.refresh)),
      ],
      child: !canView
          ? const Center(child: Text('Bu kullanıcı için müşteri listesi görüntüleme yetkisi kapalı.'))
          : RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text('Tüm müşterilerinizi görüntüleyin ve yönetin.', style: TextStyle(color: Color(0xFF718096))),
            const SizedBox(height: 18),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth < 760 ? 2 : 4;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: c.maxWidth < 760 ? 2.2 : 2.6,
                children: [
                  _StatCard(icon: Icons.groups_2_outlined, label: 'Listelenen Müşteri', value: '${customers.length}', note: state.hasMore ? 'Daha fazla kayıt var' : 'Güncel liste', color: const Color(0xFF10B8C4)),
                  _StatCard(icon: Icons.monitor_heart_outlined, label: 'Aktif Müşteri', value: '$activeCount', note: 'Listelenen kayıtlar', color: const Color(0xFF2979FF)),
                  _StatCard(icon: Icons.person_add_alt_1_outlined, label: 'Bu Ay Yeni', value: '$thisMonth', note: 'Listelenen kayıtlar', color: const Color(0xFFFFA62B)),
                  _StatCard(icon: Icons.filter_alt_outlined, label: 'Durum', value: _active == true ? 'Aktif' : _active == false ? 'Pasif' : 'Tümü', note: 'Seçili filtre', color: const Color(0xFF7B61E8)),
                ],
              );
            }),
            const SizedBox(height: 18),
            _FilterBar(
              search: _search,
              city: _city,
              district: _district,
              active: _active,
              startDateLabel: _dateText(_startDate, 'Başlangıç Tarihi'),
              endDateLabel: _dateText(_endDate, 'Bitiş Tarihi'),
              onActiveChanged: (v) => setState(() => _active = v),
              onPickStartDate: () => _pickDate(start: true),
              onPickEndDate: () => _pickDate(start: false),
              onApply: _apply,
              onClear: _clear,
              onSearchChanged: controller.updateSearch,
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                final table = Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1EAF0))),
                  child: state.isLoading
                      ? const Padding(padding: EdgeInsets.all(70), child: Center(child: CircularProgressIndicator()))
                      : state.errorMessage != null
                          ? Padding(padding: const EdgeInsets.all(50), child: Center(child: Text(state.errorMessage!)))
                          : customers.isEmpty
                              ? const Padding(padding: EdgeInsets.all(70), child: Center(child: Text('Kayıt bulunamadı.')))
                              : _CustomerTable(
                                  customers: customers,
                                  role: widget.role,
                                  canEdit: canEdit,
                                  canCreateService: canCreateService,
                                  onSelect: (c) => setState(() => _selectedCustomer = c),
                                  onOpen: (c) => context.go('${_prefix()}/customers/${c.id}'),
                                  onEdit: (c) => context.go('${_prefix()}/customers/${c.id}/edit'),
                                  onService: (c) => context.go('${_prefix()}/service-requests/new/${c.id}'),
                                ),
                );
                if (!wide) return table;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 8, child: table),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: _CustomerPreview(
                        customer: previewCustomer,
                        role: widget.role,
                        canEdit: canEdit,
                        canCreateService: canCreateService,
                        onOpen: (c) => context.go('${_prefix()}/customers/${c.id}'),
                        onEdit: (c) => context.go('${_prefix()}/customers/${c.id}/edit'),
                        onService: (c) => context.go('${_prefix()}/service-requests/new/${c.id}'),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (state.hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(child: OutlinedButton.icon(onPressed: controller.loadMoreCustomers, icon: const Icon(Icons.expand_more), label: const Text('Daha Fazla Yükle'))),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.note, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE5EDF2))),
    child: Row(children: [
      CircleAvatar(radius: 26, backgroundColor: color.withOpacity(.13), child: Icon(icon, color: color, size: 28)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(color: Color(0xFF66778A), fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
        Text(note, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ])),
    ]),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.city,
    required this.district,
    required this.active,
    required this.startDateLabel,
    required this.endDateLabel,
    required this.onActiveChanged,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onApply,
    required this.onClear,
    required this.onSearchChanged,
  });

  final TextEditingController search;
  final TextEditingController city;
  final TextEditingController district;
  final bool? active;
  final String startDateLabel;
  final String endDateLabel;
  final ValueChanged<bool?> onActiveChanged;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final ValueChanged<String> onSearchChanged;


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EAF0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final half = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 300,
                child: TextField(
                  controller: search,
                  onChanged: onSearchChanged,
                  onSubmitted: (_) => onApply(),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Müşteri adı / soyadı ara...',
                  ),
                ),
              ),
              SizedBox(
                width: compact ? half : 160,
                child: TextField(
                  controller: city,
                  decoration: const InputDecoration(labelText: 'Şehir'),
                ),
              ),
              SizedBox(
                width: compact ? half : 160,
                child: TextField(
                  controller: district,
                  decoration: const InputDecoration(labelText: 'İlçe'),
                ),
              ),
              SizedBox(
                width: compact ? half : 160,
                child: DropdownButtonFormField<bool?>(
                  isExpanded: true,
                  initialValue: active,
                  decoration: const InputDecoration(labelText: 'Durum'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tüm Durumlar')),
                    DropdownMenuItem(value: true, child: Text('Aktif')),
                    DropdownMenuItem(value: false, child: Text('Pasif')),
                  ],
                  onChanged: onActiveChanged,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onPickStartDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(startDateLabel),
              ),
              OutlinedButton.icon(
                onPressed: onPickEndDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(endDateLabel),
              ),
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Filtrele'),
              ),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.refresh),
                label: const Text('Temizle'),
              ),
            ],
          );
        },
      ),
    );
  }
}


class _CustomerPreview extends StatelessWidget {
  const _CustomerPreview({required this.customer, required this.role, required this.canEdit, required this.canCreateService, required this.onOpen, required this.onEdit, required this.onService});
  final CustomerModel? customer;
  final AppRole role;
  final bool canEdit;
  final bool canCreateService;
  final ValueChanged<CustomerModel> onOpen;
  final ValueChanged<CustomerModel> onEdit;
  final ValueChanged<CustomerModel> onService;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1EAF0))),
      child: c == null
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.badge_outlined, size: 52, color: Color(0xFFA7B6C5)), SizedBox(height: 12), Text('Müşteri Detayı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 6), Text('Soldaki listeden bir müşteri seçin.', style: TextStyle(color: Color(0xFF718096))) ]))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [CircleAvatar(radius: 30, backgroundColor: const Color(0xFF10B8C4), child: Text(_initials(c.displayName), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), Text(c.isActive ? 'Aktif müşteri' : 'Pasif müşteri', style: TextStyle(color: c.isActive ? const Color(0xFF169B55) : const Color(0xFFD94B4B), fontWeight: FontWeight.w700))]))]),
              const Divider(height: 30),
              _previewLine(Icons.phone_outlined, c.phone),
              _previewLine(Icons.location_city_outlined, '${c.city ?? '-'} / ${c.district ?? '-'}'),
              _previewLine(Icons.location_on_outlined, c.address.isEmpty ? 'Adres yok' : c.address),
              if ((c.notes ?? '').trim().isNotEmpty) _previewLine(Icons.notes_outlined, c.notes!),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: () => onOpen(c), icon: const Icon(Icons.visibility_outlined), label: const Text('Müşteri Kartı')),
                if (canEdit) OutlinedButton.icon(onPressed: () => onEdit(c), icon: const Icon(Icons.edit_outlined), label: const Text('Düzenle')),
                if (canCreateService) OutlinedButton.icon(onPressed: () => onService(c), icon: const Icon(Icons.add_task_outlined), label: const Text('Servis Aç')),
              ]),
            ]),
    );
  }
  static Widget _previewLine(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20, color: const Color(0xFF65778A)), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF334E68))))]));
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.customers, required this.role, required this.canEdit, required this.canCreateService, required this.onSelect, required this.onOpen, required this.onEdit, required this.onService});
  final List<CustomerModel> customers;
  final AppRole role;
  final bool canEdit;
  final bool canCreateService;
  final ValueChanged<CustomerModel> onSelect;
  final ValueChanged<CustomerModel> onOpen;
  final ValueChanged<CustomerModel> onEdit;
  final ValueChanged<CustomerModel> onService;


  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 900) {
      return Column(children: customers.map((c) => ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFF10B8C4), child: Text(_initials(c.displayName), style: const TextStyle(color: Colors.white))),
        title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${c.phone}\n${c.city ?? '-'} / ${c.district ?? '-'}'),
        isThreeLine: true,
        trailing: IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => onOpen(c)),
        onTap: () => onSelect(c),
      )).toList());
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        columns: const [
          DataColumn(label: Text('Müşteri')),
          DataColumn(label: Text('İletişim')),
          DataColumn(label: Text('İl / İlçe')),
          DataColumn(label: Text('Durum')),
          DataColumn(label: Text('İşlemler')),
        ],
        rows: customers.map((c) => DataRow(onSelectChanged: (_) => onSelect(c), cells: [
          DataCell(Row(children: [CircleAvatar(radius: 18, backgroundColor: const Color(0xFF10B8C4), child: Text(_initials(c.displayName), style: const TextStyle(color: Colors.white, fontSize: 12))), const SizedBox(width: 10), Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w800)), Text('#${_shortId(c.id)}', style: const TextStyle(fontSize: 11, color: Colors.grey))])])),
          DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.phone), Text(c.email ?? '-', style: const TextStyle(fontSize: 12, color: Colors.grey))])),
          DataCell(Text('${c.city ?? '-'} / ${c.district ?? '-'}')),
          DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: c.isActive ? const Color(0xFFE3F7EC) : const Color(0xFFFFE8E8), borderRadius: BorderRadius.circular(10)), child: Text(c.isActive ? 'Aktif' : 'Pasif', style: TextStyle(color: c.isActive ? const Color(0xFF169B55) : const Color(0xFFD94B4B), fontWeight: FontWeight.w800)))),
          DataCell(Row(children: [
            IconButton(tooltip: 'Müşteri kartı', onPressed: () => onOpen(c), icon: const Icon(Icons.visibility_outlined)),
            if (canCreateService)
              IconButton(tooltip: 'Servis aç', onPressed: () => onService(c), icon: const Icon(Icons.calendar_month_outlined)),
            if (canEdit)
              IconButton(tooltip: 'Düzenle', onPressed: () => onEdit(c), icon: const Icon(Icons.edit_outlined)),
          ])),
        ])).toList(),
      ),
    );
  }

  static String _shortId(String? id) { final v = id ?? ''; return v.length <= 6 ? v : v.substring(0, 6); }

  static String _initials(String name) {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }
}

String _initials(String name) => _CustomerTable._initials(name);
