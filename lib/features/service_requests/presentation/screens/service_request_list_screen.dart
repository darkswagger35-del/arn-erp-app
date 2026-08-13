import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/widgets/management_shell.dart';
import '../../../../core/widgets/service_request_edit_dialog.dart';
import '../../../user_management/data/user_management_repository_provider.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../user_management/domain/user_management_user.dart';
import '../../data/models/service_request_model.dart';
import '../controllers/service_request_controller.dart';
import '../providers/service_request_providers.dart';

class ServiceRequestListScreen extends ConsumerStatefulWidget {
  const ServiceRequestListScreen({
    super.key,
    required this.role,
    this.initialStatus,
  });

  final AppRole role;
  final ServiceRequestStatus? initialStatus;

  @override
  ConsumerState<ServiceRequestListScreen> createState() =>
      _ServiceRequestListScreenState();
}

class _ServiceRequestListScreenState
    extends ConsumerState<ServiceRequestListScreen> {
  final _searchController = TextEditingController();

  ServiceRequestStatus? _selectedStatus;
  ServiceRequestType? _selectedType;
  DateTimeRange? _dateRange;
  List<UserManagementUser> _technicians = const [];
  List<UserManagementUser> _users = const [];
  bool _isLoadingTechnicians = false;
  String? _selectedTechnicianId;
  String? _selectedCity;
  String? _selectedDistrict;
  bool? _locationSortAscending;
  int _page = 0;
  static const int _pageSize = 20;
  final Set<String> _selectedRequestIds = <String>{};
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      ref.read(serviceRequestControllerProvider).loadServiceRequests(),
      _loadTechnicians(),
    ]);
  }

  Future<void> _loadTechnicians() async {
    if (_isLoadingTechnicians) return;
    setState(() => _isLoadingTechnicians = true);
    try {
      final users =
          await ref.read(userManagementRepositoryProvider).listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _technicians = users
            .where((user) => user.role == AppRole.technician && user.isActive)
            .toList(growable: false)
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
      });
    } finally {
      if (mounted) setState(() => _isLoadingTechnicians = false);
    }
  }

  List<ServiceRequestModel> _visibleRequests(
    List<ServiceRequestModel> source,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    final result = source.where((request) {
      final matchesSearch = query.isEmpty ||
          request.customerName.toLowerCase().contains(query) ||
          request.customerPhone.toLowerCase().contains(query) ||
          request.customerAddress.toLowerCase().contains(query) ||
          request.serviceType.label.toLowerCase().contains(query) ||
          (request.id ?? '').toLowerCase().contains(query);

      final matchesType =
          _selectedType == null || request.serviceType == _selectedType;
      final matchesStatus =
          _selectedStatus == null || request.status == _selectedStatus;
      final matchesTechnician = _selectedTechnicianId == null ||
          request.assignedTechnicianId == _selectedTechnicianId;
      final matchesCity = _selectedCity == null ||
          request.customerCity.trim().toLowerCase() == _selectedCity!.toLowerCase();
      final matchesDistrict = _selectedDistrict == null ||
          request.customerDistrict.trim().toLowerCase() == _selectedDistrict!.toLowerCase();

      final planned = request.plannedDate;
      final matchesDate = _dateRange == null ||
          (planned != null &&
              !planned.isBefore(_startOfDay(_dateRange!.start)) &&
              planned.isBefore(_startOfDay(_dateRange!.end)
                  .add(const Duration(days: 1))));

      return matchesSearch && matchesType && matchesStatus &&
          matchesTechnician && matchesCity && matchesDistrict && matchesDate;
    }).toList(growable: false);

    result.sort((a, b) {
      if (_locationSortAscending != null) {
        final aLocation = '${a.customerCity.trim()} ${a.customerDistrict.trim()}'.toLowerCase();
        final bLocation = '${b.customerCity.trim()} ${b.customerDistrict.trim()}'.toLowerCase();
        final compared = aLocation.compareTo(bLocation);
        return _locationSortAscending! ? compared : -compared;
      }
      final aDate = a.plannedDate ?? a.createdAt ?? DateTime(1970);
      final bDate = b.plannedDate ?? b.createdAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return result;
  }

  bool _canBulkSelect(ServiceRequestModel r) {
    return r.id != null &&
        r.status != ServiceRequestStatus.completed &&
        r.status != ServiceRequestStatus.cancelled &&
        r.status != ServiceRequestStatus.couldNotComplete &&
        r.status != ServiceRequestStatus.inProgress;
  }

  Future<void> _bulkReturnToApproval() async {
    if (_selectedRequestIds.isEmpty || _bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final selected = ref
          .read(serviceRequestControllerProvider)
          .state
          .serviceRequests
          .where((r) => r.id != null && _selectedRequestIds.contains(r.id))
          .toList(growable: false);
      for (final r in selected) {
        if (r.status == ServiceRequestStatus.assigned) {
          await repo.unassignTechnician(serviceRequestId: r.id!);
        }
        await repo.updateStatus(
          serviceRequestId: r.id!,
          status: ServiceRequestStatus.pending,
        );
      }
      _selectedRequestIds.clear();
      await _loadData();
      if (mounted) {
        _showMessage('Seçilen işler tekrar Onay Bekliyor bölümüne alındı.');
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _bulkApprove() async {
    if (_selectedRequestIds.isEmpty || _bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final selected = ref
          .read(serviceRequestControllerProvider)
          .state
          .serviceRequests
          .where((r) =>
              r.id != null &&
              _selectedRequestIds.contains(r.id) &&
              (r.status == ServiceRequestStatus.pending ||
               r.status == ServiceRequestStatus.deferred))
          .toList(growable: false);
      if (selected.isEmpty) {
        _showMessage('Kabul edilecek Onay Bekleyen/Tehir kaydı seçilmedi.');
        return;
      }
      final missingDate = selected.where((r) => r.plannedDate == null).toList();
      if (missingDate.isNotEmpty) {
        _showMessage('${missingDate.length} işin tarihi yok. Önce Toplu Tarih ile tarih verin.');
        return;
      }
      for (final request in selected) {
        await repo.updateStatus(
          serviceRequestId: request.id!,
          status: ServiceRequestStatus.approved,
        );
      }
      _selectedRequestIds.clear();
      await _loadData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seçilen işler atama bölümüne gönderildi.')));
    } finally { if (mounted) setState(() => _bulkBusy = false); }
  }

  Future<void> _approveRequest(ServiceRequestModel request) async {
    if (request.id == null || _bulkBusy) return;
    if (request.plannedDate == null) {
      _showMessage('Bu işin tarihi yok. Onaylamadan önce tarih girin.');
      return;
    }
    setState(() => _bulkBusy = true);
    try {
      await ref.read(serviceRequestRepositoryProvider).updateStatus(
        serviceRequestId: request.id!,
        status: ServiceRequestStatus.approved,
      );
      await _loadData();
      if (mounted) _showMessage('İş onaylandı ve Atama Bekliyor bölümüne gönderildi.');
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _bulkSetDate() async {
    if (_selectedRequestIds.isEmpty || _bulkBusy) return;
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2035));
    if (picked == null || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final selected = ref.read(serviceRequestControllerProvider).state.serviceRequests.where((r) => r.id != null && _selectedRequestIds.contains(r.id)).toList();
      for (final r in selected) {
        final old = r.plannedDate?.toLocal();
        final date = DateTime(picked.year, picked.month, picked.day, old?.hour ?? 0, old?.minute ?? 0);
        await repo.updateServiceRequest(r.copyWith(plannedDate: date));
      }
      await _loadData();
    } finally { if (mounted) setState(() => _bulkBusy = false); }
  }

  Future<void> _bulkDefer() async {
    if (_selectedRequestIds.isEmpty || _bulkBusy) return;
    final note = TextEditingController();
    DateTime? newDate;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: const Text('Seçilen İşleri Tehire Al'),
      content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Yönetici notu', hintText: 'Örn. Bölge rotasına uymuyor')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () async { final d=await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days:1)), firstDate: DateTime.now(), lastDate: DateTime(2035)); if(d!=null)setLocal(()=>newDate=d); }, icon: const Icon(Icons.calendar_month), label: Text(newDate==null?'Yeni tarih seç (opsiyonel)':DateFormat('dd.MM.yyyy').format(newDate!)))
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Vazgeç')), FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Tehire Al'))],
    )));
    if (ok != true || !mounted) { note.dispose(); return; }
    setState(() => _bulkBusy = true);
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      final selected = ref.read(serviceRequestControllerProvider).state.serviceRequests.where((r)=>r.id!=null&&_selectedRequestIds.contains(r.id)).toList();
      for(final r in selected){
        var base = r;
        if (r.status == ServiceRequestStatus.assigned && r.id != null) {
          await repo.unassignTechnician(serviceRequestId: r.id!);
          base = await repo.getServiceRequestById(r.id!) ?? r;
        }
        final desc = '${base.description}${base.description.trim().isEmpty?'':'\n'}[Yönetici Tehir Notu] ${note.text.trim()}';
        await repo.updateServiceRequest(base.copyWith(status: ServiceRequestStatus.deferred, plannedDate: newDate ?? base.plannedDate, description: desc));
      }
      _selectedRequestIds.clear(); await _loadData();
    } finally { note.dispose(); if(mounted)setState(()=>_bulkBusy=false); }
  }

  Widget _buildBulkBar(List<ServiceRequestModel> filtered) {
    final selectable = filtered.where(_canBulkSelect).toList();
    final allSelected = selectable.isNotEmpty && selectable.every((r)=>_selectedRequestIds.contains(r.id));
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal:14, vertical:10),
      decoration: BoxDecoration(color: const Color(0xFFF0FAFB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFE9ED))),
      child: Wrap(spacing:10, runSpacing:8, crossAxisAlignment:WrapCrossAlignment.center, children:[
        Checkbox(value: allSelected, onChanged: selectable.isEmpty?null:(v)=>setState((){ if(v==true){_selectedRequestIds.addAll(selectable.map((e)=>e.id!));}else{_selectedRequestIds.removeAll(selectable.map((e)=>e.id!));} })),
        Text('${_selectedRequestIds.length} iş seçili', style: const TextStyle(fontWeight:FontWeight.w700)),
        FilledButton.icon(onPressed:_bulkBusy||_selectedRequestIds.isEmpty?null:_bulkApprove, icon:const Icon(Icons.check_circle_outline), label:const Text('Kabul Et → Atamaya Gönder')),
        OutlinedButton.icon(onPressed:_bulkBusy||_selectedRequestIds.isEmpty?null:_bulkReturnToApproval, icon:const Icon(Icons.undo_rounded), label:const Text("Onay Bekliyor'a Geri Al")),
        OutlinedButton.icon(onPressed:_bulkBusy||_selectedRequestIds.isEmpty?null:_bulkSetDate, icon:const Icon(Icons.event), label:const Text('Toplu Tarih')),
        OutlinedButton.icon(onPressed:_bulkBusy||_selectedRequestIds.isEmpty?null:_bulkDefer, icon:const Icon(Icons.pause_circle_outline), label:const Text('Tehire Al')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(serviceRequestControllerProvider);
    final state = controller.state;
    final all = state.serviceRequests;
    final filtered = _visibleRequests(all);
    final maxPage = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ _pageSize;
    if (_page > maxPage) _page = maxPage;
    final start = _page * _pageSize;
    final pageItems = filtered.skip(start).take(_pageSize).toList();

    return ManagementShell(
      role: widget.role,
      title: 'Servis Talepleri',
      subtitle: 'Tüm servis taleplerini görüntüleyin, yönetin ve takip edin.',
      actions: [
        if (widget.role != AppRole.technician)
          FilledButton.icon(
            onPressed: () => context.go(_customersRoute()),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Servis Talebi'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0797A9),
              foregroundColor: Colors.white,
            ),
          ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Yenile',
          onPressed: state.isLoading ? null : _loadData,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          children: [
            _buildSummaryCards(all),
            const SizedBox(height: 16),
            _buildFilterPanel(all),
            const SizedBox(height: 14),
            _buildLocationDistribution(all),
            const SizedBox(height: 14),
            _buildStatusTabs(all),
            if (_canManageApproval) _buildBulkBar(filtered),
            _buildContentCard(
              state: state,
              filtered: filtered,
              pageItems: pageItems,
              maxPage: maxPage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ServiceRequestState state) {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE4EAF2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Panele dön',
            onPressed: () => context.go(_dashboardRoute()),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Servis Talepleri',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B1F35),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tüm servis taleplerini görüntüleyin, yönetin ve takip edin.',
                  style: TextStyle(color: Color(0xFF6D7C91)),
                ),
              ],
            ),
          ),
          if (widget.role != AppRole.technician)
            FilledButton.icon(
              onPressed: () => context.go(_customersRoute()),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Servis Talebi'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0797A9),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Yenile',
            onPressed: state.isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<ServiceRequestModel> requests) {
    final today = DateTime.now();
    final todayCount = requests.where((request) {
      final date = request.plannedDate;
      return date != null && _sameDay(date, today);
    }).length;

    final cards = [
      _SummaryData(
        label: 'Onay Bekleyen',
        value: _countStatus(requests, ServiceRequestStatus.pending),
        caption: 'Yönetici onayı bekliyor',
        icon: Icons.schedule_rounded,
        color: const Color(0xFFF59E0B),
        status: ServiceRequestStatus.pending,
      ),
      _SummaryData(
        label: 'Bugünkü Servisler',
        value: todayCount,
        caption: 'Bugün planlanan',
        icon: Icons.calendar_month_rounded,
        color: const Color(0xFFEA8A1A),
        onTap: () {
          setState(() {
            _selectedStatus = null;
            _dateRange = DateTimeRange(start: today, end: today);
            _page = 0;
          });
          _loadData();
        },
      ),
      _SummaryData(
        label: 'Teknisyende',
        value: _countStatus(requests, ServiceRequestStatus.assigned),
        caption: 'Ataması yapıldı',
        icon: Icons.engineering_rounded,
        color: const Color(0xFF7C5CE5),
        status: ServiceRequestStatus.assigned,
      ),
      _SummaryData(
        label: 'Devam Ediyor',
        value: _countStatus(requests, ServiceRequestStatus.inProgress),
        caption: 'İşlemde',
        icon: Icons.build_circle_outlined,
        color: const Color(0xFF2779E8),
        status: ServiceRequestStatus.inProgress,
      ),
      _SummaryData(
        label: 'Tamamlandı',
        value: _countStatus(requests, ServiceRequestStatus.completed),
        caption: 'Başarıyla tamamlandı',
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF20A464),
        status: ServiceRequestStatus.completed,
      ),
      _SummaryData(
        label: 'İptal Edildi',
        value: _countStatus(requests, ServiceRequestStatus.cancelled),
        caption: 'İptal edilen',
        icon: Icons.close_rounded,
        color: const Color(0xFFE94A4A),
        status: ServiceRequestStatus.cancelled,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 1200
            ? 6
            : constraints.maxWidth >= 760
                ? 3
                : 2;
        final width =
            (constraints.maxWidth - (count - 1) * 12) / count;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: _SummaryCard(
                    data: card,
                    selected: card.status != null &&
                        _selectedStatus == card.status &&
                        _dateRange == null,
                    onTap: card.onTap ??
                        () => _changeStatus(
                              _selectedStatus == card.status
                                  ? null
                                  : card.status,
                            ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildFilterPanel(List<ServiceRequestModel> requests) {
    InputDecoration dd(String label) => InputDecoration(labelText: label);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 300, child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() => _page = 0),
                decoration: const InputDecoration(
                  hintText: 'Müşteri adı, soyadı veya telefon ara...',
                  prefixIcon: Icon(Icons.search),
                ),
              )),
              SizedBox(width: 175, child: DropdownButtonFormField<ServiceRequestType?>(
                isExpanded: true,
                initialValue: _selectedType,
                decoration: dd('Servis Türü'),
                items: [
                  const DropdownMenuItem<ServiceRequestType?>(value: null, child: Text('Tümü')),
                  ...ServiceRequestType.values.map((type) => DropdownMenuItem<ServiceRequestType?>(value: type, child: Text(type.label, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => setState(() { _selectedType = value; _page = 0; }),
              )),
              if (widget.role != AppRole.technician)
                SizedBox(width: 210, child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _selectedTechnicianId,
                  decoration: dd('Teknisyen'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tüm teknisyenler')),
                    ..._technicians.map((t) => DropdownMenuItem<String?>(value: t.id, child: Text(t.fullName, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (value) => setState(() { _selectedTechnicianId = value; _page = 0; }),
                )),
              SizedBox(width: 245, child: OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Align(alignment: Alignment.centerLeft, child: Text(
                  _dateRange == null ? 'Tarih Aralığı' : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                  overflow: TextOverflow.ellipsis,
                )),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17)),
              )),
              FilledButton.icon(
                onPressed: () => setState(() => _page = 0),
                icon: const Icon(Icons.filter_alt_outlined), label: const Text('Filtrele'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0797A9), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17)),
              ),
              OutlinedButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Temizle'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17))),
            ],
          ),

        ],
      ),
    );
  }

  Widget _buildLocationDistribution(List<ServiceRequestModel> requests) {
    const preferred = ['İzmir', 'Aydın', 'Manisa', 'Muğla'];
    final counts = <String, int>{};
    for (final r in requests) {
      final city = r.customerCity.trim();
      if (city.isNotEmpty) counts[city] = (counts[city] ?? 0) + 1;
    }
    final cities = <String>[...preferred.where((c) => counts.containsKey(c))];
    for (final c in counts.keys) { if (!cities.contains(c) && cities.length < 4) cities.add(c); }
    if (cities.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          const Text('Lokasyona Göre Dağılım', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF526277))),
          const SizedBox(width: 16),
          Expanded(child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: cities.map((city) {
              final selected = _selectedCity == city;
              return InkWell(
                onTap: () => setState(() { _selectedCity = selected ? null : city; _selectedDistrict = null; _page = 0; }),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 138,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFF0FBFC) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? const Color(0xFF78DDE5) : const Color(0xFFDDE5ED)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(city, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${counts[city] ?? 0} iş', style: const TextStyle(color: Color(0xFF607086))),
                  ]),
                ),
              );
            }).toList(),
          )),
        ],
      ),
    );
  }

  Widget _buildStatusTabs(List<ServiceRequestModel> requests) {
    final tabs = <(String, ServiceRequestStatus?, int)>[
      ('Tümü', null, requests.length),
      (
        'Onay Bekliyor',
        ServiceRequestStatus.pending,
        _countStatus(requests, ServiceRequestStatus.pending),
      ),
      (
        'Atama Bekliyor',
        ServiceRequestStatus.approved,
        _countStatus(requests, ServiceRequestStatus.approved),
      ),
      (
        'Tehir',
        ServiceRequestStatus.deferred,
        _countStatus(requests, ServiceRequestStatus.deferred),
      ),
      (
        'Teknisyende',
        ServiceRequestStatus.assigned,
        _countStatus(requests, ServiceRequestStatus.assigned),
      ),
      (
        'Devam Ediyor',
        ServiceRequestStatus.inProgress,
        _countStatus(requests, ServiceRequestStatus.inProgress),
      ),
      (
        'Tamamlandı',
        ServiceRequestStatus.completed,
        _countStatus(requests, ServiceRequestStatus.completed),
      ),
      (
        'İptal Edildi',
        ServiceRequestStatus.cancelled,
        _countStatus(requests, ServiceRequestStatus.cancelled),
      ),
      (
        'Tamamlanamadı',
        ServiceRequestStatus.couldNotComplete,
        _countStatus(requests, ServiceRequestStatus.couldNotComplete),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0)),
          left: BorderSide(color: Color(0xFFE2E8F0)),
          right: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((tab) {
            final selected = _selectedStatus == tab.$2;
            return InkWell(
              onTap: () => _changeStatus(tab.$2),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected
                          ? const Color(0xFF0797A9)
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      tab.$1,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? const Color(0xFF0797A9)
                            : const Color(0xFF607086),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFDDF7FA)
                            : const Color(0xFFF0F3F7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${tab.$3}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? const Color(0xFF0797A9)
                              : const Color(0xFF607086),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildContentCard({
    required ServiceRequestState state,
    required List<ServiceRequestModel> filtered,
    required List<ServiceRequestModel> pageItems,
    required int maxPage,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(
          left: BorderSide(color: Color(0xFFE2E8F0)),
          right: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Column(
        children: [
          if (state.isLoading && state.serviceRequests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(80),
              child: CircularProgressIndicator(),
            )
          else if (state.errorMessage != null &&
              state.serviceRequests.isEmpty)
            _EmptyState(
              icon: Icons.error_outline,
              title: 'Servis talepleri yüklenemedi',
              subtitle: state.errorMessage!,
              buttonLabel: 'Tekrar Dene',
              onPressed: _loadData,
            )
          else if (filtered.isEmpty)
            const _EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Kayıt bulunamadı',
              subtitle: 'Seçtiğiniz filtrelere uygun servis talebi yok.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 920) {
                  return Column(
                    children: pageItems
                        .map((request) => _buildMobileCard(request, state))
                        .toList(),
                  );
                }
                return _buildDesktopTable(pageItems, state);
              },
            ),
          if (filtered.isNotEmpty)
            _buildPagination(filtered.length, maxPage),
        ],
      ),
    );
  }

  String _productSummary(ServiceRequestModel request) {
    final names = <String>[];
    for (final item in request.items) {
      final name = item.productName.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    if (names.isEmpty && request.plannedProductName.trim().isNotEmpty) {
      names.add(request.plannedProductName.trim());
    }
    if (names.isEmpty) return 'Ürün belirtilmedi';
    if (names.length <= 2) return names.join(' • ');
    return '${names.take(2).join(' • ')} +${names.length - 2}';
  }

  String _creatorName(ServiceRequestModel request) {
    final id = request.createdBy;
    if (id == null || id.isEmpty) return '-';
    for (final user in _users) {
      if (user.id == id) return user.fullName.trim().isEmpty ? user.username : user.fullName;
    }
    return '-';
  }

  Widget _buildLocationColumnHeader() {
    final active = _selectedCity != null || _selectedDistrict != null || _locationSortAscending != null;
    return InkWell(
      onTap: _showLocationColumnOptions,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('İl / İlçe'),
            const SizedBox(width: 5),
            Icon(
              active ? Icons.filter_alt_rounded : Icons.arrow_drop_down_rounded,
              size: 19,
              color: active ? const Color(0xFF0797A9) : const Color(0xFF69788B),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocationColumnOptions() async {
    final source = ref.read(serviceRequestControllerProvider).state.serviceRequests;
    final cities = source
        .map((r) => r.customerCity.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String? tempCity = _selectedCity;
    String? tempDistrict = _selectedDistrict;
    bool? tempSort = _locationSortAscending;

    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final districts = source
              .where((r) => tempCity == null ||
                  r.customerCity.trim().toLowerCase() == tempCity!.toLowerCase())
              .map((r) => r.customerDistrict.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
            contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            actionsPadding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            title: Row(
              children: [
                const Expanded(child: Text('İl / İlçe', style: TextStyle(fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(dialogContext, false), icon: const Icon(Icons.close)),
              ],
            ),
            content: SizedBox(
              width: 390,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sırala', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => setLocalState(() => tempSort = true),
                        icon: Icon(Icons.arrow_downward_rounded, color: tempSort == true ? const Color(0xFF0797A9) : null),
                        label: const Text('A → Z'),
                        style: OutlinedButton.styleFrom(backgroundColor: tempSort == true ? const Color(0xFFE9F9FB) : null),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => setLocalState(() => tempSort = false),
                        icon: Icon(Icons.arrow_upward_rounded, color: tempSort == false ? const Color(0xFF0797A9) : null),
                        label: const Text('Z → A'),
                        style: OutlinedButton.styleFrom(backgroundColor: tempSort == false ? const Color(0xFFE9F9FB) : null),
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: tempCity,
                    decoration: const InputDecoration(labelText: 'İl'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tüm İller')),
                      ...cities.map((city) => DropdownMenuItem<String?>(value: city, child: Text(city))),
                    ],
                    onChanged: (value) => setLocalState(() {
                      tempCity = value;
                      tempDistrict = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: tempDistrict,
                    decoration: InputDecoration(
                      labelText: 'İlçe',
                      helperText: tempCity == null ? 'Önce il seçersen ilçeler o ile göre daralır.' : null,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tüm İlçeler')),
                      ...districts.map((district) => DropdownMenuItem<String?>(value: district, child: Text(district))),
                    ],
                    onChanged: (value) => setLocalState(() => tempDistrict = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setLocalState(() {
                    tempCity = null;
                    tempDistrict = null;
                    tempSort = null;
                  });
                },
                child: const Text('Temizle'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0797A9)),
                child: const Text('Uygula'),
              ),
            ],
          );
        },
      ),
    );

    if (apply == true && mounted) {
      setState(() {
        _selectedCity = tempCity;
        _selectedDistrict = tempDistrict;
        _locationSortAscending = tempSort;
        _page = 0;
      });
    }
  }

  Widget _buildDesktopTable(
    List<ServiceRequestModel> requests,
    ServiceRequestState state,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1460),
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 14,
          horizontalMargin: 10,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          dividerThickness: 1,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 72,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF526277)),
          columns: [
            const DataColumn(label: Text('')),
            const DataColumn(label: Text('Müşteri')),
            DataColumn(label: _buildLocationColumnHeader()),
            const DataColumn(label: Text('Servis Türü')),
            const DataColumn(label: Text('Sekreter')),
            const DataColumn(label: Text('Teknisyen')),
            const DataColumn(label: Text('Durum')),
            const DataColumn(label: Text('Oluşturma Tarihi')),
            const DataColumn(label: Text('Atama Tarihi')),
            const DataColumn(label: Text('İşlemler')),
          ],
          rows: requests.map((request) => DataRow(
            onSelectChanged: (_) => _showDetails(request),
            cells: [
              DataCell(Checkbox(
                value: request.id != null && _selectedRequestIds.contains(request.id),
                onChanged: request.id == null || !_canManageApproval || !_canBulkSelect(request) ? null : (v) => setState(() { if (v == true) { _selectedRequestIds.add(request.id!); } else { _selectedRequestIds.remove(request.id); } }),
              )),
              DataCell(SizedBox(width: 185, child: _TwoLineText(primary: request.customerName.trim().isEmpty ? 'Müşteri bilgisi yok' : request.customerName, secondary: request.customerPhone.trim().isEmpty ? '#${_shortId(request.id)}' : request.customerPhone))),
              DataCell(SizedBox(width: 150, child: _TwoLineText(primary: request.customerCity.trim().isEmpty ? '-' : request.customerCity, secondary: request.customerDistrict.trim().isEmpty ? '-' : request.customerDistrict))),
              DataCell(SizedBox(
                width: 155,
                child: _TwoLineText(
                  primary: request.serviceType.label,
                  secondary: _productSummary(request),
                ),
              )),
              DataCell(SizedBox(width: 135, child: Text(_creatorName(request), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)))),
              DataCell(SizedBox(width: 165, child: _TechnicianCell(name: request.status == ServiceRequestStatus.pending ? '' : request.assignedTechnicianName))),
              DataCell(_StatusBadge(status: request.status)),
              DataCell(Text(request.createdAt == null ? '-' : _formatDate(request.createdAt!.toLocal()))),
              DataCell(Text(request.plannedDate == null ? '-' : _formatDate(request.plannedDate!.toLocal()))),
              DataCell(SizedBox(width: 180, child: Align(alignment: Alignment.centerRight, child: _buildRowActions(request, state.isSaving)))),
            ],
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileCard(
    ServiceRequestModel request,
    ServiceRequestState state,
  ) {
    return InkWell(
      onTap: () => _showDetails(request),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE8EDF3))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PriorityBadge(request: request),
                const Spacer(),
                _StatusBadge(status: request.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request.customerName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF10233A),
              ),
            ),
            const SizedBox(height: 5),
            Text('${request.serviceType.label} • ${request.customerPhone}'),
            const SizedBox(height: 5),
            Text(
              request.customerAddress,
              style: const TextStyle(color: Color(0xFF6C7B8D)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 17),
                const SizedBox(width: 6),
                Text(request.plannedDate == null
                    ? 'Planlanmadı'
                    : '${_formatDate(request.plannedDate!)} ${_formatTime(request.plannedDate!)}'),
                const Spacer(),
                _buildRowActions(request, state.isSaving),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canManageApproval =>
      widget.role == AppRole.admin || widget.role == AppRole.manager;

  bool get _canDeleteService => _canManageApproval;

  Widget _buildRowActions(ServiceRequestModel request, bool isSaving) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Detayları Gör',
          onPressed: () => _showDetails(request),
          icon: const Icon(Icons.visibility_outlined),
        ),
        if (widget.role != AppRole.technician &&
            request.status != ServiceRequestStatus.completed &&
            request.status != ServiceRequestStatus.cancelled &&
            request.status != ServiceRequestStatus.couldNotComplete)
          IconButton(
            tooltip: 'Servis talebini düzenle',
            onPressed: isSaving ? null : () => _editRequest(request),
            icon: const Icon(Icons.edit_outlined),
          ),
        if (_canManageApproval && request.status == ServiceRequestStatus.pending)
          IconButton(
            tooltip: 'Onayla → Atamaya Gönder',
            onPressed: isSaving || _bulkBusy ? null : () => _approveRequest(request),
            color: const Color(0xFF0797A9),
            icon: const Icon(Icons.check_circle_outline_rounded),
          ),
        if (widget.role != AppRole.technician &&
            (request.status == ServiceRequestStatus.approved ||
             request.status == ServiceRequestStatus.assigned ||
             request.status == ServiceRequestStatus.inProgress))
          IconButton(
            tooltip: request.assignedTechnicianId == null
                ? 'Teknisyen Ata'
                : 'Atamayı Değiştir',
            onPressed: isSaving ? null : () => _showAssignSheet(request),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        if (_canDeleteService &&
            (request.status == ServiceRequestStatus.completed ||
                request.status == ServiceRequestStatus.cancelled))
          IconButton(
            tooltip: request.status == ServiceRequestStatus.completed
                ? 'Servisi sil ve stoğu geri yükle'
                : 'Servis kaydını sil',
            onPressed: isSaving
                ? null
                : () => request.status == ServiceRequestStatus.completed
                    ? _deleteCompletedRequest(request)
                    : _deleteRequest(request),
            color: const Color(0xFFD94A4A),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        PopupMenuButton<String>(
          tooltip: 'Diğer İşlemler',
          onSelected: (value) {
            switch (value) {
              case 'customer':
                context.push(_customerRoute(request.customerId));
                break;
              case 'approve':
                _approveRequest(request);
                break;
              case 'defer':
                if (request.id != null) {
                  setState(() {
                    _selectedRequestIds
                      ..clear()
                      ..add(request.id!);
                  });
                  _bulkDefer();
                }
                break;
              case 'cancel':
                _cancelRequest(request);
                break;
              case 'unassign':
                _unassign(request);
                break;
              case 'delete':
                request.status == ServiceRequestStatus.completed
                    ? _deleteCompletedRequest(request)
                    : _deleteRequest(request);
                break;
            }
          },
          itemBuilder: (context) => [
            if (_canManageApproval && request.status == ServiceRequestStatus.pending)
              const PopupMenuItem(
                value: 'approve',
                child: ListTile(dense: true, leading: Icon(Icons.check_circle_outline), title: Text('Onayla → Atamaya Gönder')),
              ),
            if (_canManageApproval && (request.status == ServiceRequestStatus.pending || request.status == ServiceRequestStatus.approved))
              const PopupMenuItem(
                value: 'defer',
                child: ListTile(dense: true, leading: Icon(Icons.pause_circle_outline), title: Text('Tehire Al')),
              ),
            if (_canManageApproval && request.status != ServiceRequestStatus.completed && request.status != ServiceRequestStatus.cancelled)
              const PopupMenuItem(
                value: 'cancel',
                child: ListTile(dense: true, leading: Icon(Icons.cancel_outlined), title: Text('İptal Et')),
              ),
            const PopupMenuItem(
              value: 'customer',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.person_outline),
                title: Text('Müşteri Kartı'),
              ),
            ),
            if (widget.role != AppRole.technician &&
                request.assignedTechnicianId != null &&
                request.status != ServiceRequestStatus.completed &&
                request.status != ServiceRequestStatus.cancelled)
              const PopupMenuItem(
                value: 'unassign',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.person_remove_outlined),
                  title: Text('Atamayı Kaldır (Bekleyene Al)'),
                ),
              ),
            if (_canDeleteService &&
                (request.status == ServiceRequestStatus.completed ||
                    request.status == ServiceRequestStatus.cancelled))
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_forever_outlined),
                  title: Text('Kaydı Kalıcı Sil'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPagination(int total, int maxPage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8EDF3))),
      ),
      child: Row(
        children: [
          Text(
            'Toplam $total kayıt',
            style: const TextStyle(color: Color(0xFF69788B)),
          ),
          const Spacer(),
          IconButton.outlined(
            onPressed: _page == 0 ? null : () => setState(() => _page--),
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0797A9),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${_page + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('/ ${maxPage + 1}'),
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed:
                _page >= maxPage ? null : () => setState(() => _page++),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 16),
          const Text('20 / sayfa'),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (selected != null) {
      setState(() {
        _dateRange = selected;
        _page = 0;
      });
    }
  }

  Future<void> _clearFilters() async {
    _searchController.clear();
    setState(() {
      _selectedStatus = null;
      _selectedType = null;
      _selectedTechnicianId = null;
      _selectedCity = null;
      _selectedDistrict = null;
      _locationSortAscending = null;
      _dateRange = null;
      _page = 0;
    });
    await ref.read(serviceRequestControllerProvider).loadServiceRequests();
  }

  Future<void> _changeStatus(ServiceRequestStatus? status) async {
    setState(() {
      _selectedStatus = status;
      _page = 0;
    });
  }

  void _showDetails(ServiceRequestModel request) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFDDF7FA),
                      child: Text(
                        _initials(request.customerName),
                        style: const TextStyle(
                          color: Color(0xFF07889A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.customerName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('Talep No: #${_shortId(request.id)}'),
                        ],
                      ),
                    ),
                    _StatusBadge(status: request.status),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Wrap(
                  spacing: 28,
                  runSpacing: 18,
                  children: [
                    _DetailItem(
                      icon: Icons.build_outlined,
                      label: 'Servis Türü',
                      value: request.serviceType.label,
                    ),
                    _DetailItem(
                      icon: Icons.calendar_month_outlined,
                      label: 'Planlanan Tarih',
                      value: request.plannedDate == null
                          ? 'Planlanmadı'
                          : '${_formatDate(request.plannedDate!)} ${_formatTime(request.plannedDate!)}',
                    ),
                    _DetailItem(
                      icon: Icons.engineering_outlined,
                      label: 'Teknisyen',
                      value: request.status == ServiceRequestStatus.pending ||
                              request.assignedTechnicianName.trim().isEmpty
                          ? 'Atanmadı'
                          : request.assignedTechnicianName,
                    ),
                    _DetailItem(
                      icon: Icons.phone_outlined,
                      label: 'Telefon',
                      value: request.customerPhone.trim().isEmpty
                          ? '-'
                          : request.customerPhone,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _DetailBlock(
                  icon: Icons.location_on_outlined,
                  title: 'Adres',
                  text: request.customerAddress.trim().isEmpty
                      ? 'Adres bilgisi bulunmuyor.'
                      : request.customerAddress,
                ),
                const SizedBox(height: 12),
                _DetailBlock(
                  icon: Icons.notes_outlined,
                  title: 'Açıklama',
                  text: request.description.trim().isEmpty
                      ? 'Açıklama eklenmemiş.'
                      : request.description,
                ),
                if (request.status == ServiceRequestStatus.cancelled) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD5D5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('İptal Bilgileri', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFC93636))),
                        const SizedBox(height: 10),
                        Text('Neden: ${request.cancellationReason.trim().isEmpty ? 'Belirtilmedi' : request.cancellationReason}'),
                        const SizedBox(height: 6),
                        Text('İptal eden: ${request.cancelledByName.trim().isEmpty ? '-' : request.cancelledByName}'),
                        const SizedBox(height: 6),
                        Text('İptal zamanı: ${request.cancelledAt == null ? '-' : '${_formatDate(request.cancelledAt!.toLocal())} ${_formatTime(request.cancelledAt!.toLocal())}'}'),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 6),
                        const Text('Ürünler / Tutar', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        if (request.items.isEmpty)
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(request.plannedProductName.isEmpty ? '-' : '${request.plannedProductName} × ${request.plannedQuantity.toStringAsFixed(request.plannedQuantity % 1 == 0 ? 0 : 1)}')), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(request.price), style: const TextStyle(fontWeight: FontWeight.w900))])
                        else
                          ...request.items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Expanded(child: Text('${item.productName} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}')), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w800))]))),
                        const Divider(),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Toplam', style: TextStyle(fontWeight: FontWeight.w900)), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(request.price), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFC93636)))]),
                      ],
                    ),
                  ),
                ],
                if (request.status == ServiceRequestStatus.completed) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF7FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE1EAF0))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Tamamlanan İş / Ürünler', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      if (request.items.isEmpty)
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(request.plannedProductName.isEmpty ? request.serviceType.label : request.plannedProductName)), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(request.price), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0797A9)))])
                      else
                        ...request.items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [Expanded(child: Text('${item.productName} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)}')), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w800))]))),
                      const Divider(height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Toplam', style: TextStyle(fontWeight: FontWeight.w900)), Text(NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(request.price), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0797A9)))]),
                      if (request.completionNote.trim().isNotEmpty) ...[const SizedBox(height: 8), Text('Tamamlama notu: ${request.completionNote}', style: const TextStyle(color: Color(0xFF52657A)))],
                    ]),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        context.push(_customerRoute(request.customerId));
                      },
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Müşteri Kartı'),
                    ),
                    if (widget.role != AppRole.technician &&
                        request.status == ServiceRequestStatus.cancelled) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _markCustomerInactive(request);
                        },
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('Müşteriyi Pasife Al'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC93636),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _openNewServiceForCancelled(request);
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Yeniden Servis Aç'),
                      ),
                    ],
                    if (widget.role != AppRole.technician &&
                        request.status != ServiceRequestStatus.completed &&
                        request.status != ServiceRequestStatus.cancelled) ...[
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showAssignSheet(request);
                        },
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: Text(
                          request.assignedTechnicianId == null
                              ? 'Teknisyen Ata'
                              : 'Atamayı Değiştir',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignSheet(ServiceRequestModel request) async {
    if (_isLoadingTechnicians) {
      _showMessage('Teknisyenler yükleniyor.');
      return;
    }
    if (_technicians.isEmpty) {
      _showMessage('Aktif teknisyen bulunamadı.');
      return;
    }

    String? technicianId = request.assignedTechnicianId;
    DateTime? plannedDate = request.plannedDate;

    final result = await showModalBottomSheet<_AssignmentResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.viewInsetsOf(context).bottom + 28,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Teknisyen Ataması',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    request.customerName,
                    style: const TextStyle(color: Color(0xFF6D7C91)),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: technicianId,
                    decoration: const InputDecoration(
                      labelText: 'Teknisyen',
                      prefixIcon: Icon(Icons.engineering_outlined),
                    ),
                    items: _technicians
                        .map(
                          (technician) => DropdownMenuItem(
                            value: technician.id,
                            child: Text(technician.fullName, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setSheetState(() => technicianId = value),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: plannedDate ?? now,
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: DateTime(now.year + 2),
                      );
                      if (selected != null) {
                        final old = plannedDate;
                        setSheetState(() {
                          plannedDate = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            old?.hour ?? 0,
                            old?.minute ?? 0,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      plannedDate == null
                          ? 'Planlanan Tarihi Seç'
                          : 'Planlanan: ${_formatDate(plannedDate!)}',
                    ),
                  ),
                  if (plannedDate == null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Teknisyen ataması için planlanan tarih zorunludur.',
                      style: TextStyle(color: Color(0xFFC93636), fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: technicianId == null || plannedDate == null
                        ? null
                        : () => Navigator.of(context).pop(
                              _AssignmentResult(
                                technicianId: technicianId!,
                                plannedDate: plannedDate,
                              ),
                            ),
                    icon: const Icon(Icons.assignment_ind_outlined),
                    label: const Text('Atamayı Kaydet'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null || request.id == null) return;

    final success = await ref
        .read(serviceRequestControllerProvider)
        .assignTechnician(
          serviceRequestId: request.id!,
          technicianId: result.technicianId,
          plannedDate: result.plannedDate,
        );

    if (!mounted) return;
    final currentState = ref.read(serviceRequestControllerProvider).state;
    _showMessage(
      success
          ? currentState.successMessage ?? 'Teknisyen atandı.'
          : currentState.errorMessage ?? 'Teknisyen atanamadı.',
    );
    await _loadData();
  }

  Future<void> _editRequest(ServiceRequestModel request) async {
    if (request.id == null) return;

    final result = await showServiceRequestEditDialog(
      context: context,
      title: '${request.customerName} • Servis Talebini Düzenle',
      initialServiceType: request.serviceType.value,
      initialPlannedDate: request.plannedDate,
      initialProductId: request.plannedProductId,
      initialProductName: request.plannedProductName,
      initialQuantity: request.plannedQuantity,
      initialUnitPrice: request.plannedUnitPrice,
      initialPrice: request.price,
      initialDescription: request.description,
    );
    if (result == null || !mounted) return;

    try {
      await Supabase.instance.client.from('service_requests').update({
        'service_type': result.serviceType,
        'planned_date': result.plannedDate.toUtc().toIso8601String(),
        'description': result.description,
        'planned_product_id': result.productId,
        'planned_product_name': result.productName,
        'planned_quantity': result.quantity,
        'planned_unit_price': result.unitPrice,
        'price': result.price,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request.id!);
      if (!mounted) return;
      _showMessage('Servis talebi güncellendi.');
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      _showMessage('Servis güncellenemedi: $e');
    }
  }

  Future<void> _unassign(ServiceRequestModel request) async {
    if (request.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Teknisyen atamasını iptal et'),
        content: Text(
          '${request.customerName} kaydı tekrar Atama Bekleyen durumuna alınacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Atamayı İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(serviceRequestControllerProvider)
        .unassignTechnician(request.id!);
    if (!mounted) return;
    final currentState = ref.read(serviceRequestControllerProvider).state;
    _showMessage(
      ok
          ? currentState.successMessage ?? 'Atama iptal edildi.'
          : currentState.errorMessage ?? 'Atama iptal edilemedi.',
    );
    await _loadData();
  }

  Future<void> _cancelRequest(ServiceRequestModel request) async {
    if (request.id == null) return;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Servis talebini iptal et'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${request.customerName} için servis İptal Edildi bölümüne taşınacak.'),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'İptal nedeni *',
                  hintText: 'Örn. Müşteri iptal istedi',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.trim().isEmpty) return;
    final ok = await ref
        .read(serviceRequestControllerProvider)
        .cancelServiceRequest(serviceRequestId: request.id!, reason: reason);
    if (!mounted) return;
    final currentState = ref.read(serviceRequestControllerProvider).state;
    _showMessage(
      ok
          ? currentState.successMessage ?? 'Servis İptal Edildi bölümüne taşındı.'
          : currentState.errorMessage ?? 'İptal edilemedi.',
    );
    await _loadData();
  }

  void _openNewServiceForCancelled(ServiceRequestModel request) {
    final base = widget.role == AppRole.secretary ? '/secretary' : '/manager';
    context.push('$base/service-requests/new/${request.customerId}');
  }

  Future<void> _markCustomerInactive(ServiceRequestModel request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Müşteriyi pasife al'),
        content: Text(
          '${request.customerName} pasife alınacak. Açık/bekleyen servisleri de kapatılacak ve atama listelerinden çıkarılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC93636)),
            child: const Text('Pasife Al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(customerControllerProvider).toggleActive(request.customerId, false);

      final client = Supabase.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();
      final user = client.auth.currentUser;
      String cancelledByName = '';
      if (user != null) {
        try {
          final profile = await client
              .from('profiles')
              .select('full_name')
              .eq('id', user.id)
              .maybeSingle();
          cancelledByName = profile?['full_name']?.toString().trim() ?? '';
        } catch (_) {}
      }

      final openStatuses = [
        ServiceRequestStatus.pending.value,
        ServiceRequestStatus.assigned.value,
        ServiceRequestStatus.inProgress.value,
      ];

      try {
        await client
            .from('service_requests')
            .update({
              'status': ServiceRequestStatus.cancelled.value,
              'assigned_technician_id': null,
              'route_order': null,
              'route_plan_date': null,
              'cancellation_reason': 'Müşteri pasife alındı - bir daha servis istemiyor',
              'cancelled_at': now,
              'cancelled_by': user?.id,
              'cancelled_by_name': cancelledByName,
              'updated_at': now,
            })
            .eq('customer_id', request.customerId)
            .inFilter('status', openStatuses);
      } catch (_) {
        await client
            .from('service_requests')
            .update({
              'status': ServiceRequestStatus.cancelled.value,
              'assigned_technician_id': null,
              'route_order': null,
              'route_plan_date': null,
              'updated_at': now,
            })
            .eq('customer_id', request.customerId)
            .inFilter('status', openStatuses);
      }

      if (!mounted) return;
      _showMessage('Müşteri pasife alındı ve açık servisleri kapatıldı.');
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Müşteri pasife alınamadı: $error');
    }
  }

  Future<void> _deleteCompletedRequest(ServiceRequestModel request) async {
    if (request.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tamamlanan servisi sil'),
        content: const Text(
          'Bu servis aktif kayıtlardan kaldırılacak. Kullanılan ürünler teknisyenin araç deposuna geri eklenecek; müşteri kartındaki servis geçmişinden de kaybolacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil ve stoğu geri yükle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(serviceRequestControllerProvider)
        .deleteCompletedService(request.id!);
    if (!mounted) return;
    final currentState = ref.read(serviceRequestControllerProvider).state;
    _showMessage(
      ok
          ? currentState.successMessage ?? 'Servis silindi.'
          : currentState.errorMessage ?? 'Servis silinemedi.',
    );
    if (ok) await _loadData();
  }

  Future<void> _deleteRequest(ServiceRequestModel request) async {
    if (request.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Servis talebini kalıcı sil'),
        content: Text(
          '${request.customerName} kaydı kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kalıcı Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(serviceRequestControllerProvider)
        .deleteServiceRequest(request.id!);
    if (!mounted) return;
    final currentState = ref.read(serviceRequestControllerProvider).state;
    _showMessage(
      ok
          ? currentState.successMessage ?? 'Servis talebi silindi.'
          : currentState.errorMessage ?? 'Servis talebi silinemedi.',
    );
    if (ok) await _loadData();
  }

  String _customerRoute(String customerId) {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/manager/customers/$customerId';
      case AppRole.secretary:
        return '/secretary/customers/$customerId';
      case AppRole.technician:
        return '/technician/customers/$customerId';
    }
  }

  String _customersRoute() {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/manager/customers';
      case AppRole.secretary:
        return '/secretary/customers';
      case AppRole.technician:
        return '/technician-dashboard';
    }
  }

  String _dashboardRoute() {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/admin-dashboard';
      case AppRole.secretary:
        return '/secretary-dashboard';
      case AppRole.technician:
        return '/technician-dashboard';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SummaryData {
  const _SummaryData({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    this.status,
    this.onTap,
  });

  final String label;
  final int value;
  final String caption;
  final IconData icon;
  final Color color;
  final ServiceRequestStatus? status;
  final VoidCallback? onTap;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _SummaryData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? data.color : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, color: data.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF526277),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${data.value}',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10233A),
                      ),
                    ),
                    Text(
                      data.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8390A2),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoLineText extends StatelessWidget {
  const _TwoLineText({required this.primary, required this.secondary});

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF16283E),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (secondary.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF758398),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _TechnicianCell extends StatelessWidget {
  const _TechnicianCell({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    if (name.trim().isEmpty) {
      return const _TwoLineText(primary: '-', secondary: 'Atanmadı');
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFEDE8FF),
          child: Text(
            _initials(name),
            style: const TextStyle(
              color: Color(0xFF7653D6),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceRequestStatus.pending => const Color(0xFFF59E0B),
      ServiceRequestStatus.approved => const Color(0xFF0891B2),
      ServiceRequestStatus.deferred => const Color(0xFF64748B),
      ServiceRequestStatus.assigned => const Color(0xFF7C5CE5),
      ServiceRequestStatus.inProgress => const Color(0xFF2779E8),
      ServiceRequestStatus.completed => const Color(0xFF20A464),
      ServiceRequestStatus.cancelled => const Color(0xFFE94A4A),
      ServiceRequestStatus.couldNotComplete => const Color(0xFFEA7C24),
    };

    final label = switch (status) {
      ServiceRequestStatus.pending => 'Onay Bekliyor',
      ServiceRequestStatus.approved => 'Atama Bekliyor',
      ServiceRequestStatus.deferred => 'Tehir Edildi',
      ServiceRequestStatus.assigned => 'Teknisyende',
      ServiceRequestStatus.inProgress => 'Devam Ediyor',
      ServiceRequestStatus.completed => 'Tamamlandı',
      ServiceRequestStatus.cancelled => 'İptal Edildi',
      ServiceRequestStatus.couldNotComplete => 'Tamamlanamadı',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.request});

  final ServiceRequestModel request;

  @override
  Widget build(BuildContext context) {
    final priority = _priorityFor(request);
    final color = switch (priority) {
      _RequestPriority.high => const Color(0xFFE94A4A),
      _RequestPriority.medium => const Color(0xFFF59E0B),
      _RequestPriority.low => const Color(0xFF2779E8),
    };
    final label = switch (priority) {
      _RequestPriority.high => 'Yüksek',
      _RequestPriority.medium => 'Orta',
      _RequestPriority.low => 'Düşük',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 54, color: const Color(0xFF9AA7B8)),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF758398)),
          ),
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
          ],
        ],
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 285,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF0797A9)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF758398),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0797A9)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(color: Color(0xFF617084))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentResult {
  const _AssignmentResult({
    required this.technicianId,
    required this.plannedDate,
  });

  final String technicianId;
  final DateTime? plannedDate;
}

enum _RequestPriority { high, medium, low }

_RequestPriority _priorityFor(ServiceRequestModel request) {
  if (request.serviceType == ServiceRequestType.fault ||
      request.serviceType == ServiceRequestType.newInstallation) {
    return _RequestPriority.high;
  }
  if (request.serviceType == ServiceRequestType.maintenance ||
      request.serviceType == ServiceRequestType.membrane ||
      request.serviceType == ServiceRequestType.filterChange) {
    return _RequestPriority.medium;
  }
  return _RequestPriority.low;
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x080F172A),
        blurRadius: 12,
        offset: Offset(0, 4),
      ),
    ],
  );
}

int _countStatus(
  List<ServiceRequestModel> requests,
  ServiceRequestStatus status,
) {
  return requests.where((request) => request.status == status).length;
}

DateTime _startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _shortId(String? value) {
  final id = value?.trim() ?? '';
  if (id.isEmpty) return '-';
  return id.length <= 8 ? id.toUpperCase() : id.substring(0, 8).toUpperCase();
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}
