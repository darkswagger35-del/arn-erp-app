import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/widgets/service_request_edit_dialog.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../settings/data/company_app_settings.dart';
import '../../data/models/customer_model.dart';
import '../providers/customer_providers.dart';
import 'customer_module_shell.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.role, required this.customerId});
  final AppRole role;
  final String customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  late Future<_CustomerCardData> _cardData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(customerControllerProvider).loadCustomer(widget.customerId));
    _cardData = _loadCardData();
  }

  String _prefix() => widget.role == AppRole.secretary ? '/secretary' : widget.role == AppRole.technician ? '/technician' : '/manager';

  Future<_CustomerCardData> _loadCardData() async {
    final client = Supabase.instance.client;

    List<Map<String, dynamic>> services = const [];
    List<Map<String, dynamic>> devices = const [];
    List<CustomerMaintenanceRecord> history = const [];

    try {
      final rows = await client
          .from('service_requests')
          .select(
            'id, service_type, status, price, planned_date, created_at, updated_at, description, completion_note, cancellation_reason, technician_unavailable_reason, technician_unavailable_note, planned_product_id, planned_product_name, planned_quantity, planned_unit_price, service_items(product_name, quantity, unit_price, line_total)',
          )
          .eq('customer_id', widget.customerId)
          .order('created_at', ascending: false)
          .limit(50);
      services = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      // Eski müşteri kayıtları service_requests tablosunda bulunmayabilir.
    }

    try {
      final rows = await client
          .from('customer_devices')
          .select()
          .eq('customer_id', widget.customerId)
          .order('created_at', ascending: false);
      devices = List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      // Cihaz kaydı olmaması müşteri kartının kalanını engellememeli.
    }

    try {
      history = await MaintenanceRepository(client).getCustomerRecords(
        widget.customerId,
      );
    } catch (_) {
      // Excel/eski kayıt tabloları hazır değilse güncel servisler yine gösterilir.
    }

    return _CustomerCardData(
      services: services,
      devices: devices,
      history: history,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerControllerProvider).state;
    final customer = state.currentCustomer;
    final appSettings = ref.watch(companyAppSettingsProvider).asData?.value ??
        const CompanyAppSettings(companyId: '');
    final canEditCustomer = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_edit_customers', fallback: true)
            : appSettings.permission('technician_edit_customers', fallback: true));
    final canCreateService = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_create_service', fallback: true)
            : appSettings.permission('technician_create_service'));
    final canEditCompleted = widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        (widget.role == AppRole.secretary
            ? appSettings.permission('secretary_edit_completed_service', fallback: true)
            : appSettings.permission('technician_edit_completed_service'));
    return CustomerModuleShell(
      role: widget.role,
      title: 'Müşteri Kartı',
      actions: [
        if (customer != null) ...[
          if (canCreateService) ...[
            FilledButton.icon(onPressed: () => context.go('${_prefix()}/service-requests/new/${customer.id}'), icon: const Icon(Icons.add), label: const Text('Yeni Servis Talebi')),
            const SizedBox(width: 10),
          ],
          if (canEditCustomer)
            OutlinedButton.icon(onPressed: () => context.go('${_prefix()}/customers/${customer.id}/edit'), icon: const Icon(Icons.edit_outlined), label: const Text('Düzenle')),
        ],
      ],
      child: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : customer == null
              ? const Center(child: Text('Müşteri bulunamadı.'))
              : FutureBuilder<_CustomerCardData>(
                  future: _cardData,
                  builder: (context, snapshot) => _content(
                    customer,
                    snapshot.data ?? const _CustomerCardData(services: [], devices: [], history: []),
                    canEditCompleted: canEditCompleted,
                  ),
                ),
    );
  }

  Widget _content(
    CustomerModel c,
    _CustomerCardData data, {
    required bool canEditCompleted,
  }) {
    final legacyHistory =
        data.history.where((item) => item.serviceId == null).toList(growable: false);
    final completedServiceRows = data.services
        .where((e) => e['status']?.toString() == 'completed')
        .toList(growable: false);
    final completedRequests = completedServiceRows.length;
    final completed = completedRequests + legacyHistory.length;
    final pending = data.services
        .where((e) => const {'pending', 'assigned', 'in_progress'}.contains(e['status']?.toString()))
        .length;
    // Ciro ve toplam servis yalnızca GERÇEKTEN tamamlanan işlerden hesaplanır.
    // İptal/gidilemedi/açık talepler müşteri kartında not olarak tutulur ama satışa sayılmaz.
    final requestTotal = completedServiceRows.fold<double>(
      0,
      (sum, row) => sum + ((row['price'] as num?)?.toDouble() ?? 0),
    );
    final historyTotal = legacyHistory.fold<double>(
      0,
      (sum, row) => sum + row.amount,
    );
    final total = requestTotal + historyTotal;
    final totalServiceCount = completedServiceRows.length + legacyHistory.length;
    final lastServiceDate = _latestServiceDate(data);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(children: [TextButton.icon(onPressed: () => context.go('${_prefix()}/customers'), icon: const Icon(Icons.arrow_back), label: const Text('Müşteriler')), const Text(' / Müşteri Kartı', style: TextStyle(color: Colors.grey))]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: _box(),
          child: LayoutBuilder(builder: (context, x) {
            final narrow = x.maxWidth < 850;
            final info = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 42, backgroundColor: const Color(0xFF0DB6C1), child: Text(_initials(c.displayName), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))),
              const SizedBox(width: 18),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(c.displayName, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF102033)))), const SizedBox(width: 10), _status(c.isActive)]),
                const SizedBox(height: 18),
                Wrap(spacing: 25, runSpacing: 12, children: [
                  _info(Icons.phone_outlined, c.phone),
                  _info(Icons.email_outlined, c.email ?? '-'),
                  _info(Icons.location_on_outlined, '${c.city ?? '-'} / ${c.district ?? '-'}\n${c.address}'),
                  _info(Icons.notes_outlined, c.notes?.trim().isNotEmpty == true ? c.notes! : 'Not eklenmemiş'),
                ]),
              ])),
            ]);
            final summary = Container(
              width: narrow ? double.infinity : 330,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                _line('Müşteri No', '#${widget.customerId.substring(0, 8)}'),
                _line('Kayıt Tarihi', _date(c.registrationDate ?? c.createdAt)),
                _line('Toplam Servis', '$totalServiceCount'),
                _line('Toplam Tutar', NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(total)),
                _line('Son Servis', _date(lastServiceDate)),
              ]),
            );
            return narrow ? Column(children: [info, const SizedBox(height: 18), summary]) : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: info), const SizedBox(width: 18), summary]);
          }),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width < 900 ? 2 : 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.3,
          children: [
            _metric('Toplam Servis', '$totalServiceCount', Icons.calendar_month_outlined, const Color(0xFF2788E8)),
            _metric('Tamamlanan', '$completed', Icons.check_circle_outline, const Color(0xFF19A764)),
            _metric('Bekleyen', '$pending', Icons.schedule_outlined, const Color(0xFFF59E0B)),
            _metric('Kayıtlı Cihaz', '${data.devices.length}', Icons.devices_other_outlined, const Color(0xFF7457E8)),
            _metric('Toplam Tutar', NumberFormat.compactCurrency(locale: 'tr_TR', symbol: '₺').format(total), Icons.account_balance_wallet_outlined, const Color(0xFF0DB6C1)),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, x) {
          final narrow = x.maxWidth < 900;
          final devices = _section('Kayıtlı Cihazlar', Icons.devices_other_outlined, data.devices.isEmpty
              ? const [Padding(padding: EdgeInsets.all(22), child: Text('Kayıtlı cihaz bulunamadı.'))]
              : data.devices.map((d) => ListTile(leading: const CircleAvatar(child: Icon(Icons.water_drop_outlined)), title: Text((d['brand'] ?? d['device_type'] ?? 'Su Arıtma Cihazı').toString(), style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('Model: ${d['model'] ?? '-'} • Seri No: ${d['serial_number'] ?? '-'}'), trailing: _status((d['is_active'] as bool?) ?? true))).toList());
          final historyWidgets = _serviceHistoryWidgets(data, canEdit: canEditCompleted);
          final services = _section(
            'Tamamlanan İşlemler ve Servis Geçmişi',
            Icons.history,
            historyWidgets.isEmpty
                ? const [Padding(padding: EdgeInsets.all(22), child: Text('Tamamlanan servis veya eski işlem kaydı bulunamadı.'))]
                : historyWidgets,
          );
          final openWidgets = _openServiceWidgets(data);
          final failedWidgets = _failedServiceWidgets(data);
          final serviceTracking = Column(children: [
            services,
            if (openWidgets.isNotEmpty) ...[
              const SizedBox(height: 16),
              _section('Açık Servis Talepleri', Icons.pending_actions_outlined, openWidgets),
            ],
            if (failedWidgets.isNotEmpty) ...[
              const SizedBox(height: 16),
              _section('Gidilemedi / İptal Geçmişi', Icons.warning_amber_rounded, failedWidgets),
            ],
          ]);
          return narrow
              ? Column(children: [devices, const SizedBox(height: 16), serviceTracking])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: devices), const SizedBox(width: 16), Expanded(child: serviceTracking)]);
        }),
      ],
    );
  }


  DateTime? _latestServiceDate(_CustomerCardData data) {
    final dates = <DateTime>[];
    for (final row in data.services.where((row) => row['status']?.toString() == 'completed')) {
      final value = row['planned_date'] ?? row['created_at'];
      final parsed = DateTime.tryParse(value?.toString() ?? '');
      if (parsed != null) dates.add(parsed);
    }
    dates.addAll(
      data.history
          .where((row) => row.serviceId == null)
          .map((row) => row.performedAt),
    );
    if (dates.isEmpty) return null;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }

  List<Widget> _serviceHistoryWidgets(
    _CustomerCardData data, {
    required bool canEdit,
  }) {
    final entries = <_CustomerHistoryEntry>[];

    for (final row in data.services.where((row) => row['status']?.toString() == 'completed')) {
      final status = row['status']?.toString() ?? '';
      final date = DateTime.tryParse(
            (row['planned_date'] ?? row['created_at'])?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final completionNote = row['completion_note']?.toString().trim() ?? '';
      final description = row['description']?.toString().trim() ?? '';
      final rawItems = row['service_items'] is List
          ? List<Map<String, dynamic>>.from(row['service_items'] as List)
          : const <Map<String, dynamic>>[];
      final productText = rawItems
          .map((item) {
            final name = item['product_name']?.toString().trim() ?? '';
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
            if (name.isEmpty) return '';
            final q = quantity == quantity.roundToDouble()
                ? quantity.toInt().toString()
                : quantity.toStringAsFixed(2);
            return '$name × $q';
          })
          .where((item) => item.isNotEmpty)
          .join(', ');
      final details = <String>[
        if (completionNote.isNotEmpty) completionNote,
        if (completionNote.isEmpty && description.isNotEmpty) description,
        if (productText.isNotEmpty) 'Ürün: $productText',
      ];
      entries.add(
        _CustomerHistoryEntry(
          date: date,
          title: _serviceLabel(row['service_type']?.toString()),
          subtitle: details.isEmpty ? 'Açıklama yok' : details.join(' • '),
          amount: (row['price'] as num?)?.toDouble() ?? 0,
          completed: status == 'completed',
          source: status == 'completed' ? 'Tamamlanan servis' : 'Servis talebi',
          serviceRecord: row,
        ),
      );
    }

    // service_id bulunan bakım kayıtları, aynı servisin ikinci bir kopyasıdır.
    // Güncel servis bilgisi service_requests üzerinden gösterilir. Böylece teknisyenin
    // sonradan değiştirdiği servis türü/not doğrudan müşteri kartına yansır ve
    // servis silindiğinde eski bakım satırı müşteri geçmişinde hayalet kayıt olarak kalmaz.
    for (final row in data.history.where((item) => item.serviceId == null)) {
      final staff = row.technicianName ??
          row.secretaryName ??
          row.assignedUserName;
      final details = <String>[
        if (row.notes?.trim().isNotEmpty == true) row.notes!.trim(),
        if (staff?.trim().isNotEmpty == true) 'Personel: ${staff!.trim()}',
        if (row.quantity != 1) 'Adet: ${row.quantity.toStringAsFixed(row.quantity % 1 == 0 ? 0 : 2)}',
      ];
      entries.add(
        _CustomerHistoryEntry(
          date: row.performedAt,
          title: row.productName,
          subtitle: details.isEmpty ? 'Eski işlem kaydı' : details.join(' • '),
          amount: row.amount,
          completed: true,
          source: 'Excel / Eski Kayıt',
          historyRecord: row,
        ),
      );
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries.take(20).map((entry) {
      final color = entry.completed
          ? const Color(0xFF19A764)
          : const Color(0xFFF59E0B);
      final amountText = entry.amount > 0
          ? NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
              .format(entry.amount)
          : null;
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.12),
          child: Icon(
            entry.completed ? Icons.check : Icons.schedule,
            color: color,
          ),
        ),
        title: Text(
          entry.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${entry.subtitle}\n${entry.source}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_date(entry.date)),
                if (amountText != null)
                  Text(
                    amountText,
                    style: const TextStyle(
                      color: Color(0xFF0DB6C1),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            if (canEdit && entry.serviceRecord != null) ...[
              const SizedBox(width: 8),
              Tooltip(message: 'Servis kaydını düzenle', child: IconButton(onPressed: () => _editServiceRecord(entry.serviceRecord!), icon: const Icon(Icons.edit_outlined))),
            ] else if (canEdit && entry.historyRecord != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Eski işlemi düzenle',
                child: IconButton(
                  onPressed: () => _editHistoryRecord(entry.historyRecord!),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ],
          ],
        ),
      );
    }).toList(growable: false);
  }

  List<Widget> _openServiceWidgets(_CustomerCardData data) {
    final rows = data.services
        .where((row) => const {'pending', 'assigned', 'in_progress'}.contains(row['status']?.toString()))
        .toList(growable: false);
    return rows.map((row) {
      final status = row['status']?.toString() ?? '';
      final label = switch (status) {
        'assigned' => 'Teknikerde',
        'in_progress' => 'Devam ediyor',
        _ => 'Atama / planlama bekliyor',
      };
      final date = DateTime.tryParse((row['planned_date'] ?? row['created_at'])?.toString() ?? '');
      final product = row['planned_product_name']?.toString().trim() ?? '';
      final qty = (row['planned_quantity'] as num?)?.toDouble() ?? 0;
      final unit = (row['planned_unit_price'] as num?)?.toDouble() ?? 0;
      final price = (row['price'] as num?)?.toDouble() ?? 0;
      final details = <String>[
        row['description']?.toString().trim().isNotEmpty == true ? row['description'].toString().trim() : 'Not yok',
        if (product.isNotEmpty) 'Ürün: $product${qty > 0 ? ' × ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)}' : ''}',
        if (unit > 0) 'Birim: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(unit)}',
        if (price > 0) 'Toplam: ${NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(price)}',
        label,
      ];
      final canEdit = widget.role == AppRole.secretary || widget.role == AppRole.admin || widget.role == AppRole.manager;
      return ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4FF), child: Icon(Icons.schedule_rounded, color: Color(0xFF2788E8))),
        title: Text(_serviceLabel(row['service_type']?.toString()), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(details.join(' • ')),
        trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          if (date != null) Text(_date(date)),
          if (canEdit) IconButton(tooltip: 'Açık servis talebini düzenle', onPressed: () => _editServiceRecord(row), icon: const Icon(Icons.edit_outlined)),
        ]),
      );
    }).toList(growable: false);
  }

  List<Widget> _failedServiceWidgets(_CustomerCardData data) {
    final rows = data.services
        .where((row) => const {'cancelled', 'could_not_complete'}.contains(row['status']?.toString()))
        .toList(growable: false);
    return rows.map((row) {
      final status = row['status']?.toString() ?? '';
      final reason = [
        row['technician_unavailable_reason']?.toString().trim(),
        row['technician_unavailable_note']?.toString().trim(),
        row['cancellation_reason']?.toString().trim(),
        row['completion_note']?.toString().trim(),
        row['description']?.toString().trim(),
      ].whereType<String>().firstWhere((v) => v.isNotEmpty, orElse: () => 'Not girilmemiş');
      final date = DateTime.tryParse((row['planned_date'] ?? row['updated_at'] ?? row['created_at'])?.toString() ?? '');
      return ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFECEC), child: Icon(Icons.warning_amber_rounded, color: Color(0xFFE75454))),
        title: Text(_serviceLabel(row['service_type']?.toString()), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$reason\n${status == 'could_not_complete' ? 'Tekniker gidilemedi / tamamlanamadı' : 'İptal edildi'}'),
        isThreeLine: true,
        trailing: date == null ? null : Text(_date(date)),
      );
    }).toList(growable: false);
  }

  Future<void> _editServiceRecord(Map<String, dynamic> record) async {
    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) return;

    final result = await showServiceRequestEditDialog(
      context: context,
      title: 'Servis Kaydını Düzenle',
      initialServiceType: record['service_type']?.toString() ?? 'other',
      initialPlannedDate: DateTime.tryParse(record['planned_date']?.toString() ?? ''),
      initialProductId: record['planned_product_id']?.toString(),
      initialProductName: record['planned_product_name']?.toString() ?? '',
      initialQuantity: (record['planned_quantity'] as num?)?.toDouble() ?? 0,
      initialUnitPrice: (record['planned_unit_price'] as num?)?.toDouble() ?? 0,
      initialPrice: (record['price'] as num?)?.toDouble() ?? 0,
      initialDescription: record['description']?.toString() ?? '',
    );
    if (result == null || !mounted) return;

    try {
      await Supabase.instance.client.from('service_requests').update({
        'service_type': result.serviceType,
        'planned_date': result.plannedDate.toUtc().toIso8601String(),
        'price': result.price,
        'description': result.description,
        'planned_product_id': result.productId,
        'planned_product_name': result.productName,
        'planned_quantity': result.quantity,
        'planned_unit_price': result.unitPrice,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      if (!mounted) return;
      await ref.read(customerControllerProvider).loadCustomer(widget.customerId);
      if (!mounted) return;
      setState(() => _cardData = _loadCardData());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis kaydı güncellendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    }
  }

  Future<void> _editHistoryRecord(CustomerMaintenanceRecord record) async {
    final repo = MaintenanceRepository(Supabase.instance.client);
    List<MaintenanceProduct> products;
    List<MaintenanceUser> staff;
    try {
      final results = await Future.wait([
        repo.getProducts(),
        repo.getHistoricalStaff(),
      ]);
      products = results[0] as List<MaintenanceProduct>;
      staff = results[1] as List<MaintenanceUser>;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Düzenleme bilgileri yüklenemedi: $e')),
      );
      return;
    }
    if (!mounted) return;

    String? productId = record.productId;
    if (productId == null || !products.any((p) => p.id == productId)) {
      final matching = products.where(
        (p) => p.name.trim().toLowerCase() == record.productName.trim().toLowerCase(),
      );
      productId = matching.isEmpty ? null : matching.first.id;
    }
    String? secretaryId = record.secretaryId;
    String? technicianId = record.technicianId;
    if (secretaryId != null &&
        !staff.any((u) => u.role == 'secretary' && u.id == secretaryId)) {
      secretaryId = null;
    }
    if (technicianId != null &&
        !staff.any((u) => u.role == 'technician' && u.id == technicianId)) {
      technicianId = null;
    }
    DateTime performedAt = record.performedAt;
    String paymentStatus = record.paymentStatus == 'debt' ? 'debt' : 'paid';
    final quantityController = TextEditingController(
      text: record.quantity.toStringAsFixed(record.quantity % 1 == 0 ? 0 : 2),
    );
    final amountController = TextEditingController(
      text: record.amount.toStringAsFixed(2),
    );
    final notesController = TextEditingController(text: record.notes ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    DateTime? nextMaintenanceDate() {
      if (productId == null) return null;
      final matches = products.where((p) => p.id == productId);
      if (matches.isEmpty || matches.first.maintenanceMonths <= 0) return null;
      final months = matches.first.maintenanceMonths;
      return DateTime(performedAt.year, performedAt.month + months, performedAt.day);
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final nextDate = nextMaintenanceDate();
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_note_rounded),
                SizedBox(width: 10),
                Text('Eski İşlemi Düzenle'),
              ],
            ),
            content: SizedBox(
              width: 720,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: productId,
                        decoration: const InputDecoration(
                          labelText: 'Ürün / Yapılan İşlem *',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        items: products
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.name),
                                ))
                            .toList(growable: false),
                        onChanged: saving
                            ? null
                            : (value) => setDialogState(() => productId = value),
                        validator: (value) => value == null ? 'Ürün seçin' : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: saving
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: performedAt,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                  locale: const Locale('tr', 'TR'),
                                );
                                if (date != null) {
                                  setDialogState(() => performedAt = date);
                                }
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'İşlem Tarihi *',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                          ),
                          child: Text(
                            DateFormat('dd.MM.yyyy').format(performedAt),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (nextDate != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sonraki bakım: ${DateFormat('dd.MM.yyyy').format(nextDate)}',
                          style: const TextStyle(color: Color(0xFF65778A)),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: quantityController,
                              enabled: !saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Adet *',
                                prefixIcon: Icon(Icons.numbers_rounded),
                              ),
                              validator: (value) =>
                                  (double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0) <= 0
                                      ? '0’dan büyük girin'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: amountController,
                              enabled: !saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Toplam Tutar (₺)',
                                prefixIcon: Icon(Icons.currency_lira_rounded),
                              ),
                              validator: (value) =>
                                  (double.tryParse((value ?? '').replaceAll(',', '.')) ?? -1) < 0
                                      ? 'Geçerli tutar girin'
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: secretaryId,
                              decoration: const InputDecoration(
                                labelText: 'Sekreter',
                                prefixIcon: Icon(Icons.support_agent_outlined),
                              ),
                              items: staff
                                  .where((u) => u.role == 'secretary')
                                  .map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName)))
                                  .toList(growable: false),
                              onChanged: saving
                                  ? null
                                  : (value) => setDialogState(() => secretaryId = value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: technicianId,
                              decoration: const InputDecoration(
                                labelText: 'Tekniker',
                                prefixIcon: Icon(Icons.engineering_outlined),
                              ),
                              items: staff
                                  .where((u) => u.role == 'technician')
                                  .map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName)))
                                  .toList(growable: false),
                              onChanged: saving
                                  ? null
                                  : (value) => setDialogState(() => technicianId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: paymentStatus,
                        decoration: const InputDecoration(
                          labelText: 'Ödeme Durumu',
                          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'paid', child: Text('Ödendi')),
                          DropdownMenuItem(value: 'debt', child: Text('Borçlu')),
                        ],
                        onChanged: saving
                            ? null
                            : (value) => setDialogState(
                                  () => paymentStatus = value ?? 'paid',
                                ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama / Not',
                          prefixIcon: Icon(Icons.notes_outlined),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false) || productId == null) {
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          await repo.updateCustomerRecord(
                            record: record,
                            productId: productId!,
                            performedAt: performedAt,
                            nextMaintenanceDate: nextMaintenanceDate(),
                            secretaryId: secretaryId,
                            technicianId: technicianId,
                            notes: notesController.text,
                            quantity: double.parse(quantityController.text.replaceAll(',', '.')),
                            amount: double.parse(amountController.text.replaceAll(',', '.')),
                            paymentStatus: paymentStatus,
                          );
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(content: Text('Eski işlem güncellenemedi: $e')),
                            );
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(saving ? 'Kaydediliyor...' : 'Kaydet'),
              ),
            ],
          );
        },
      ),
    );

    quantityController.dispose();
    amountController.dispose();
    notesController.dispose();

    if (saved == true && mounted) {
      setState(() => _cardData = _loadCardData());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eski işlem güncellendi.')),
      );
    }
  }

  BoxDecoration _box() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1EAF0)));
  Widget _section(String title, IconData icon, List<Widget> children) => Container(decoration: _box(), child: Column(children: [Padding(padding: const EdgeInsets.all(18), child: Row(children: [Icon(icon, color: const Color(0xFF0DB6C1)), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))])), const Divider(height: 1), ...children]));
  Widget _metric(String l, String v, IconData i, Color c) => Container(padding: const EdgeInsets.all(15), decoration: _box(), child: Row(children: [CircleAvatar(backgroundColor: c.withOpacity(.12), child: Icon(i, color: c)), const SizedBox(width: 10), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(v, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))]))]));
  Widget _info(IconData i, String t) => SizedBox(width: 250, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 20, color: const Color(0xFF65778A)), const SizedBox(width: 8), Expanded(child: Text(t))]));
  Widget _line(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [Expanded(child: Text(l, style: const TextStyle(color: Colors.grey))), Text(v, style: const TextStyle(fontWeight: FontWeight.w800))]));
  Widget _status(bool active) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: active ? const Color(0xFFE3F7EC) : const Color(0xFFFFE8E8), borderRadius: BorderRadius.circular(10)), child: Text(active ? 'Aktif' : 'Pasif', style: TextStyle(color: active ? const Color(0xFF169B55) : const Color(0xFFD94B4B), fontWeight: FontWeight.w800, fontSize: 12)));
  String _date(DateTime? d) => d == null ? '-' : DateFormat('dd.MM.yyyy').format(d.toLocal());
  String _initials(String n) { final p = n.trim().split(RegExp(r'\s+')); return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase(); }
  String _serviceLabel(String? value) {
    switch (value) {
      case 'new_installation':
        return 'Cihaz Satışı / Montaj';
      case 'filter_change':
        return 'Filtre Değişimi';
      case 'maintenance':
        return 'Bakım';
      case 'repair':
        return 'Arıza / Onarım';
      case 'membrane_change':
        return 'Membran Değişimi';
      case 'pump_change':
        return 'Pompa Değişimi';
      case 'other':
        return 'Diğer';
      default:
        if (value == null || value.trim().isEmpty) return 'Servis';
        return value
            .replaceAll('_', ' ')
            .split(' ')
            .map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}')
            .join(' ');
    }
  }
}

class _CustomerCardData {
  const _CustomerCardData({
    required this.services,
    required this.devices,
    required this.history,
  });

  final List<Map<String, dynamic>> services;
  final List<Map<String, dynamic>> devices;
  final List<CustomerMaintenanceRecord> history;
}

class _CustomerHistoryEntry {
  const _CustomerHistoryEntry({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.completed,
    required this.source,
    this.historyRecord,
    this.serviceRecord,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final double amount;
  final bool completed;
  final String source;
  final CustomerMaintenanceRecord? historyRecord;
  final Map<String, dynamic>? serviceRecord;
}
