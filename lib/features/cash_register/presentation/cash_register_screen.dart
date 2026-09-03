import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/cash_register_repository.dart';

class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key, required this.role});
  final AppRole role;

  @override
  ConsumerState<CashRegisterScreen> createState() => _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  late Future<Map<String, dynamic>> _future;
  final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  final _repo = CashRegisterRepository(Supabase.instance.client);

  List<Map<String, dynamic>> _staff = const [];
  int _tab = 0;
  String _period = 'today';
  String _categoryFilter = 'all';
  String _personFilter = 'all';
  String _sourceFilter = 'all';
  DateTimeRange? _customRange;
  bool _busy = false;

  bool get _manager => widget.role == AppRole.admin || widget.role == AppRole.manager;

  static const _categories = <String, String>{
    'fuel': 'Yakıt',
    'advance': 'Avans',
    'salary': 'Maaş',
    'advertising': 'Reklam',
    'rent': 'Kira',
    'ssi': 'SSK',
    'meal': 'Yemek',
    'material': 'Malzeme',
    'vehicle': 'Araç',
    'other': 'Diğer',
  };

  @override
  void initState() {
    super.initState();
    _reload();
    _loadStaff();
  }

  void _reload() {
    _future = _repo.summary();
  }

  Future<void> _loadStaff() async {
    try {
      final rows = await _repo.staff();
      if (mounted) setState(() => _staff = rows);
    } catch (_) {
      // Personel listesi gider ekranını bloke etmesin.
    }
  }

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  double _n(Object? value) => (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0;

  DateTime? _dt(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  DateTimeRange _rangeForPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (period == 'week') {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return DateTimeRange(start: start, end: today.add(const Duration(days: 1)));
    }
    if (period == 'month') {
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 1),
      );
    }
    if (period == 'custom' && _customRange != null) {
      return DateTimeRange(
        start: DateTime(_customRange!.start.year, _customRange!.start.month, _customRange!.start.day),
        end: DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day).add(const Duration(days: 1)),
      );
    }
    return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
  }

  bool _inRange(DateTime? date, DateTimeRange range) =>
      date != null && !date.isBefore(range.start) && date.isBefore(range.end);

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _customRange,
    );
    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _period = 'custom';
    });
  }

  Future<void> _transfer(Map<String, dynamic> holder) async {
    final balance = _n(holder['balance']);
    final amount = TextEditingController(text: balance.toStringAsFixed(0));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${holder['full_name']} → Ana Kasa'),
        content: SizedBox(
          width: 430,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text('Personel kasası: ${money.format(balance)}')),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Çekilecek tutar'),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ana Kasaya Çek')),
        ],
      ),
    );
    if (ok != true) return;
    final parsed = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    try {
      await _repo.transferToMain(profileId: holder['profile_id'].toString(), amount: parsed, note: note.text);
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      _error('Aktarım yapılamadı: $e');
    }
  }

  Future<void> _saveExpense(_ExpenseDraft draft, {String? movementId}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (movementId == null) {
        await _repo.addExpense(
          category: draft.category,
          amount: draft.amount,
          paymentSource: draft.paymentSource,
          beneficiaryProfileId: draft.beneficiaryId,
          sourceProfileId: draft.sourceProfileId,
          note: draft.note,
          documentNo: draft.documentNo,
          expenseAt: draft.date,
        );
      } else {
        await _repo.updateExpense(
          movementId: movementId,
          category: draft.category,
          amount: draft.amount,
          paymentSource: draft.paymentSource,
          beneficiaryProfileId: draft.beneficiaryId,
          sourceProfileId: draft.sourceProfileId,
          note: draft.note,
          documentNo: draft.documentNo,
          expenseAt: draft.date,
        );
      }
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(movementId == null ? 'Gider kaydedildi.' : 'Gider güncellendi.')),
      );
    } catch (e) {
      _error('Gider kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gideri sil'),
        content: Text('${_categoryLabel(row['category'])} • ${money.format(_n(row['amount']))}\nBu kayıt silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteExpense(row['id'].toString());
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      _error('Gider silinemedi: $e');
    }
  }

  void _error(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red.shade700),
    );
  }

  String _categoryLabel(Object? value) => _categories[value?.toString()] ?? 'Diğer';

  IconData _categoryIcon(String key) {
    return switch (key) {
      'fuel' => Icons.local_gas_station_outlined,
      'advance' => Icons.person_add_alt_1_outlined,
      'salary' => Icons.groups_outlined,
      'advertising' => Icons.campaign_outlined,
      'rent' => Icons.home_work_outlined,
      'ssi' => Icons.health_and_safety_outlined,
      'meal' => Icons.restaurant_outlined,
      'material' => Icons.inventory_2_outlined,
      'vehicle' => Icons.directions_car_outlined,
      _ => Icons.more_horiz_rounded,
    };
  }

  Future<void> _exportExpenses(List<Map<String, dynamic>> rows) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['Giderler'];
    sheet.appendRow([
      TextCellValue('Tarih'),
      TextCellValue('Gider Türü'),
      TextCellValue('Kime / Kim İçin'),
      TextCellValue('Tutar'),
      TextCellValue('Ödeme Şekli'),
      TextCellValue('Ödeyen Kasa'),
      TextCellValue('Açıklama'),
      TextCellValue('Fiş / Fatura No'),
      TextCellValue('Kaydeden'),
    ]);
    for (final r in rows) {
      final date = _dt(r['expense_at']);
      sheet.appendRow([
        TextCellValue(date == null ? '' : DateFormat('dd.MM.yyyy HH:mm').format(date)),
        TextCellValue(_categoryLabel(r['category'])),
        TextCellValue(r['beneficiary_name']?.toString() ?? '-'),
        TextCellValue(_n(r['amount']).toStringAsFixed(2)),
        TextCellValue(r['payment_source'] == 'personnel_cash' ? 'Personel Kasası' : 'Ana Kasa'),
        TextCellValue(r['payment_source'] == 'personnel_cash' ? (r['source_profile_name']?.toString() ?? '-') : 'Ana Kasa'),
        TextCellValue(r['note']?.toString() ?? ''),
        TextCellValue(r['document_no']?.toString() ?? ''),
        TextCellValue(r['created_by_name']?.toString() ?? ''),
      ]);
    }
    final bytes = excel.encode();
    if (bytes == null) return;
    await FilePicker.platform.saveFile(
      dialogTitle: 'Kasa giderlerini kaydet',
      fileName: 'MOTUS_Kasa_Giderleri_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: widget.role,
      title: _manager ? 'Kasa' : 'Kasam',
      subtitle: _manager
          ? 'Nakit tahsilatlarınızı, personel kasalarını ve giderlerinizi yönetin.'
          : 'Nakit tahsilatlarınızı ve kasanızı görüntüleyin.',
      actions: [
        if (_manager)
          FilledButton.icon(
            onPressed: () => _openExpenseDialog(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Gider Ekle'),
          ),
        const SizedBox(width: 8),
        IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh_rounded), tooltip: 'Yenile'),
      ],
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          if (snap.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 10),
                Text('Kasa yüklenemedi: ${snap.error}'),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => setState(_reload), child: const Text('Tekrar Dene')),
              ]),
            );
          }
          return _body(snap.data ?? const <String, dynamic>{});
        },
      ),
    );
  }

  Widget _body(Map<String, dynamic> data) {
    if (!_manager) {
      return _technicianCashBody(data);
    }

    final rawHolders = _rows(data['holders']);

    // Admin/Yönetici Personel Kasaları ekranında sadece para bulunanları değil,
    // tüm aktif teknikerleri görür. Kasa hareketi olmayan tekniker 0 TL görünür.
    final holderById = <String, Map<String, dynamic>>{
      for (final h in rawHolders)
        if (h['profile_id'] != null) h['profile_id'].toString(): Map<String, dynamic>.from(h),
    };
    for (final s in _staff) {
      final role = s['role']?.toString().toLowerCase();
      final active = s['is_active'] != false;
      final id = s['id']?.toString();
      if (role != 'technician' || !active || id == null || id.isEmpty) continue;
      holderById.putIfAbsent(id, () => <String, dynamic>{
            'profile_id': id,
            'full_name': s['full_name'] ?? s['name'] ?? 'Tekniker',
            'received': 0,
            'transferred': 0,
            'expenses': 0,
            'balance': 0,
          });
    }
    final holders = holderById.values.toList()
      ..sort((a, b) => (a['full_name'] ?? '').toString().compareTo((b['full_name'] ?? '').toString()));

    final receipts = _rows(data['cash_receipts']);
    final expenses = _rows(data['expenses']);
    final transfers = _rows(data['transfers']);
    final range = _rangeForPeriod(_period);

    // Özet, seçili tarih/kişi/ödeme kaynağını baz alır; kategori filtresini
    // bilerek dışarıda bırakır. Böylece Ali seçildiğinde Avans, Yakıt, Yemek vb.
    // bütün gider türlerinin toplamı aynı anda görülebilir.
    final expenseSummaryRows = expenses.where((r) {
      final inDate = _inRange(_dt(r['expense_at']), range);
      final personOk = _personFilter == 'all' || r['beneficiary_profile_id']?.toString() == _personFilter;
      final sourceOk = _sourceFilter == 'all' || r['payment_source'] == _sourceFilter;
      return inDate && personOk && sourceOk;
    }).toList();

    final filteredExpenses = expenseSummaryRows.where((r) {
      final categoryOk = _categoryFilter == 'all' || r['category'] == _categoryFilter;
      return categoryOk;
    }).toList();
    final filteredReceipts = receipts.where((r) => _inRange(_dt(r['payment_date']), range)).toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));

    double sumRows(List<Map<String, dynamic>> rows, String field) =>
        rows.fold<double>(0, (sum, r) => sum + _n(r[field]));

    final todayReceipts = receipts.where((r) {
      final d = _dt(r['payment_date']);
      return d != null && !d.isBefore(today) && d.isBefore(tomorrow);
    }).toList();
    final yesterdayReceipts = receipts.where((r) {
      final d = _dt(r['payment_date']);
      return d != null && !d.isBefore(yesterday) && d.isBefore(today);
    }).toList();
    final todayExpenses = expenses.where((r) {
      final d = _dt(r['expense_at']);
      return d != null && !d.isBefore(today) && d.isBefore(tomorrow);
    }).toList();
    final yesterdayExpenses = expenses.where((r) {
      final d = _dt(r['expense_at']);
      return d != null && !d.isBefore(yesterday) && d.isBefore(today);
    }).toList();

    final personnelBalance = holders.fold<double>(0, (s, h) => s + _n(h['balance']));
    final mainCash = _n(data['main_cash']);
    final todayCash = sumRows(todayReceipts, 'amount');
    final yesterdayCash = sumRows(yesterdayReceipts, 'amount');
    final todayExpense = sumRows(todayExpenses, 'amount');
    final yesterdayExpense = sumRows(yesterdayExpenses, 'amount');
    final todayCardNet = _n(data['today_card_net']);
    final monthCardNet = _n(data['month_card_net']);
    final todayCardCommission = _n(data['today_card_commission']);

    final categoryTotals = <String, double>{};
    for (final e in expenses.where((r) => _inRange(_dt(r['expense_at']), DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month + 1, 1))))) {
      final key = e['category']?.toString() ?? 'other';
      categoryTotals[key] = (categoryTotals[key] ?? 0) + _n(e['amount']);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final desktop = c.maxWidth >= 1120;
        final content = ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            if (_manager)
              _summaryCards(
                c.maxWidth,
                mainCash: mainCash,
                personnelCash: personnelBalance,
                todayCash: todayCash,
                yesterdayCash: yesterdayCash,
                todayExpense: todayExpense,
                yesterdayExpense: yesterdayExpense,
                todayCardNet: todayCardNet,
                monthCardNet: monthCardNet,
                todayCardCommission: todayCardCommission,
              ),
            if (_manager) const SizedBox(height: 14),
            if (desktop && _manager)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _mainPanel(
                      expenses: expenses,
                      filteredExpenses: filteredExpenses,
                      expenseSummaryRows: expenseSummaryRows,
                      receipts: filteredReceipts,
                      holders: holders,
                      transfers: transfers,
                      categoryTotals: categoryTotals,
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 330,
                    child: _ExpenseForm(
                      staff: _staff,
                      categories: _categories,
                      busy: _busy,
                      onSave: _saveExpense,
                    ),
                  ),
                ],
              )
            else
              _mainPanel(
                expenses: expenses,
                filteredExpenses: filteredExpenses,
                expenseSummaryRows: expenseSummaryRows,
                receipts: filteredReceipts,
                holders: holders,
                transfers: transfers,
                categoryTotals: categoryTotals,
              ),
          ],
        );
        return content;
      },
    );
  }

  Widget _technicianCashBody(Map<String, dynamic> data) {
    final totalRevenue = _n(data['technician_total_revenue']);
    final cashOnHand = _n(data['technician_cash_on_hand']);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final cardWidth = width >= 760 ? (width - 50) / 2 : width - 36;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _KpiCard(
                  width: cardWidth,
                  title: 'Toplam Ciro',
                  value: money.format(totalRevenue),
                  icon: Icons.trending_up_rounded,
                  subtitle: 'Tamamlanan servislerin toplamı',
                ),
                _KpiCard(
                  width: cardWidth,
                  title: 'Üzerimdeki Nakit Para',
                  value: money.format(cashOnHand),
                  icon: Icons.account_balance_wallet_outlined,
                  subtitle: 'Ana kasaya henüz teslim edilmemiş nakit',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCards(
    double width, {
    required double mainCash,
    required double personnelCash,
    required double todayCash,
    required double yesterdayCash,
    required double todayExpense,
    required double yesterdayExpense,
    required double todayCardNet,
    required double monthCardNet,
    required double todayCardCommission,
  }) {
    final cardWidth = width >= 1250 ? (width - 56) / 5 : width >= 760 ? (width - 28) / 3 : width >= 520 ? (width - 14) / 2 : width;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _KpiCard(width: cardWidth, title: 'Ana Kasa Bakiyesi', value: money.format(mainCash), icon: Icons.account_balance_wallet_outlined, subtitle: 'Kredi kartları hariç'),
        _KpiCard(width: cardWidth, title: 'Tekniker Kasalarında', value: money.format(personnelCash), icon: Icons.groups_2_outlined, subtitle: 'Henüz ana kasaya çekilmemiş'),
        _KpiCard(width: cardWidth, title: 'Bugün Nakit Tahsilat', value: money.format(todayCash), icon: Icons.payments_outlined, subtitle: 'Dün: ${money.format(yesterdayCash)}'),
        _KpiCard(width: cardWidth, title: 'Kart / POS Net', value: money.format(todayCardNet), icon: Icons.credit_card_outlined, subtitle: 'Bu ay: ${money.format(monthCardNet)} • Komisyon: ${money.format(todayCardCommission)}'),
        _KpiCard(width: cardWidth, title: 'Bugün Gider', value: money.format(todayExpense), icon: Icons.remove_circle_outline, subtitle: 'Dün: ${money.format(yesterdayExpense)}', negative: true),
      ],
    );
  }

  Widget _mainPanel({
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> filteredExpenses,
    required List<Map<String, dynamic>> expenseSummaryRows,
    required List<Map<String, dynamic>> receipts,
    required List<Map<String, dynamic>> holders,
    required List<Map<String, dynamic>> transfers,
    required Map<String, double> categoryTotals,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _tabButton(0, 'Genel Bakış'),
                  _tabButton(1, 'Nakit Tahsilatlar'),
                  _tabButton(2, 'Personel Kasaları'),
                  _tabButton(3, 'Giderler'),
                ],
              ),
            ),
          ),
          const Divider(height: 18),
          if (_tab == 0) ...[
            _filters(),
            _expenseSummary(expenseSummaryRows),
            _expensesTable(filteredExpenses),
          ] else if (_tab == 1)
            _receiptsTable(receipts)
          else if (_tab == 2)
            _holdersPanel(holders)
          else ...[
            _filters(),
            _expenseSummary(expenseSummaryRows),
            _expensesTable(filteredExpenses),
          ],
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final selected = _tab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: () => setState(() => _tab = index),
        style: TextButton.styleFrom(
          foregroundColor: selected ? Theme.of(context).colorScheme.primary : const Color(0xFF334E68),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 72 : 0,
              height: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _periodButton('today', 'Bugün'),
          _periodButton('week', 'Bu Hafta'),
          _periodButton('month', 'Bu Ay'),
          OutlinedButton.icon(
            onPressed: _pickCustomRange,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(_period == 'custom' && _customRange != null
                ? '${DateFormat('dd.MM').format(_customRange!.start)} - ${DateFormat('dd.MM').format(_customRange!.end)}'
                : 'Tarih Aralığı'),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              initialValue: _categoryFilter,
              decoration: const InputDecoration(labelText: 'Gider Türü', isDense: true),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Tümü')),
                ..._categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => _categoryFilter = v ?? 'all'),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: _personFilter,
              decoration: const InputDecoration(labelText: 'Kime', isDense: true),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Tümü')),
                ..._staff.map((s) => DropdownMenuItem(value: s['id'].toString(), child: Text(s['full_name']?.toString() ?? '-'))),
              ],
              onChanged: (v) => setState(() => _personFilter = v ?? 'all'),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _sourceFilter,
              decoration: const InputDecoration(labelText: 'Ödeme Şekli', isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tümü')),
                DropdownMenuItem(value: 'main_cash', child: Text('Ana Kasa')),
                DropdownMenuItem(value: 'personnel_cash', child: Text('Personel Kasası')),
              ],
              onChanged: (v) => setState(() => _sourceFilter = v ?? 'all'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _period = 'today';
              _customRange = null;
              _categoryFilter = 'all';
              _personFilter = 'all';
              _sourceFilter = 'all';
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Temizle'),
          ),
        ],
      ),
    );
  }

  Widget _periodButton(String value, String label) {
    final selected = _period == value;
    return selected
        ? FilledButton(onPressed: () => setState(() => _period = value), child: Text(label))
        : OutlinedButton(onPressed: () => setState(() => _period = value), child: Text(label));
  }

  Widget _expenseSummary(List<Map<String, dynamic>> rows) {
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final r in rows) {
      final key = r['category']?.toString() ?? 'other';
      totals[key] = (totals[key] ?? 0) + _n(r['amount']);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final grandTotal = totals.values.fold<double>(0, (sum, value) => sum + value);
    String personName = 'Tüm Personel / Genel';
    if (_personFilter != 'all') {
      for (final staff in _staff) {
        if (staff['id']?.toString() == _personFilter) {
          personName = staff['full_name']?.toString() ?? 'Personel';
          break;
        }
      }
    }
    String periodLabel;
    switch (_period) {
      case 'week':
        periodLabel = 'Bu Hafta';
        break;
      case 'month':
        periodLabel = 'Bu Ay';
        break;
      case 'custom':
        periodLabel = _customRange == null
            ? 'Tarih Aralığı'
            : '${DateFormat('dd.MM.yyyy').format(_customRange!.start)} - ${DateFormat('dd.MM.yyyy').format(_customRange!.end)}';
        break;
      default:
        periodLabel = 'Bugün';
    }

    final orderedKeys = <String>[
      'advance', 'fuel', 'meal', 'vehicle', 'material', 'salary',
      'advertising', 'rent', 'ssi', 'other',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFD),
          border: Border.all(color: const Color(0xFFDCE7EE)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _personFilter == 'all' ? 'Toplam Gider Özeti' : '$personName • Gider Özeti',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text('$periodLabel • ${rows.length} işlem', style: const TextStyle(color: Color(0xFF66788A))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(color: const Color(0xFFFFECEC), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('GENEL TOPLAM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF9B2C2C))),
                        Text(money.format(grandTotal), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFD92D20))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: orderedKeys.map((key) {
                  final total = totals[key] ?? 0;
                  final count = counts[key] ?? 0;
                  return _CategoryCard(
                    icon: _categoryIcon(key),
                    title: _categoryLabel(key),
                    value: money.format(total),
                    count: count,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categorySummary(Map<String, double> totals, List<Map<String, dynamic>> expenses) {
    final month = DateTime.now();
    final monthRange = DateTimeRange(start: DateTime(month.year, month.month, 1), end: DateTime(month.year, month.month + 1, 1));
    final counts = <String, int>{};
    for (final r in expenses.where((r) => _inRange(_dt(r['expense_at']), monthRange))) {
      final key = r['category']?.toString() ?? 'other';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final visible = <String>['fuel', 'advance', 'salary', 'advertising', 'rent', 'other'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gider Özetleri (Bu Ay)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visible.map((key) {
              final otherTotal = key == 'other'
                  ? totals.entries.where((e) => !visible.take(5).contains(e.key)).fold<double>(0, (s, e) => s + e.value)
                  : (totals[key] ?? 0);
              final otherCount = key == 'other'
                  ? counts.entries.where((e) => !visible.take(5).contains(e.key)).fold<int>(0, (s, e) => s + e.value)
                  : (counts[key] ?? 0);
              return _CategoryCard(
                icon: _categoryIcon(key),
                title: _categoryLabel(key),
                value: money.format(otherTotal),
                count: otherCount,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _expensesTable(List<Map<String, dynamic>> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('Giderler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
              Text('Toplam ${rows.length} kayıt', style: const TextStyle(color: Color(0xFF66788A))),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: rows.isEmpty ? null : () => _exportExpenses(rows),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text("Excel'e Aktar"),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const _EmptyBox(text: 'Seçili filtrelerde gider kaydı yok.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text('Tarih')),
                  DataColumn(label: Text('Gider Türü')),
                  DataColumn(label: Text('Kime / Kim İçin')),
                  DataColumn(label: Text('Tutar')),
                  DataColumn(label: Text('Ödeme Şekli')),
                  DataColumn(label: Text('Açıklama')),
                  DataColumn(label: Text('Fiş / Fatura No')),
                  DataColumn(label: Text('İşlemler')),
                ],
                rows: rows.map((r) {
                  final date = _dt(r['expense_at']);
                  final category = r['category']?.toString() ?? 'other';
                  final source = r['payment_source']?.toString() ?? 'main_cash';
                  final sourceText = source == 'personnel_cash'
                      ? 'Personel Kasası\n${r['source_profile_name'] ?? '-'}'
                      : 'Ana Kasa';
                  return DataRow(cells: [
                    DataCell(Text(date == null ? '-' : DateFormat('dd.MM.yyyy HH:mm').format(date))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_categoryIcon(category), size: 18),
                      const SizedBox(width: 7),
                      Text(_categoryLabel(category), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ])),
                    DataCell(Text(r['beneficiary_name']?.toString() ?? '-')),
                    DataCell(Text('-${money.format(_n(r['amount']))}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900))),
                    DataCell(Text(sourceText)),
                    DataCell(SizedBox(width: 190, child: Text(r['note']?.toString().isNotEmpty == true ? r['note'].toString() : '-'))),
                    DataCell(Text(r['document_no']?.toString().isNotEmpty == true ? r['document_no'].toString() : '-')),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Detay',
                        icon: const Icon(Icons.visibility_outlined, size: 19),
                        onPressed: () => _showExpenseDetail(r),
                      ),
                      IconButton(
                        tooltip: 'Düzenle',
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        onPressed: () => _openExpenseDialog(row: r),
                      ),
                      IconButton(
                        tooltip: 'Sil',
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 19),
                        onPressed: () => _deleteExpense(r),
                      ),
                    ])),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _receiptsTable(List<Map<String, dynamic>> rows) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nakit Tahsilatlar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const _EmptyBox(text: 'Seçili dönemde nakit tahsilat yok.')
          else
            ...rows.map((r) {
              final dt = _dt(r['payment_date']);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.payments_outlined)),
                title: Text(r['customer_name']?.toString() ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r['receiver_name'] ?? '-'}${dt == null ? '' : ' • ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}'}\n${r['description'] ?? ''}'),
                isThreeLine: true,
                trailing: Text(money.format(_n(r['amount'])), style: const TextStyle(color: Color(0xFF00A878), fontWeight: FontWeight.w900, fontSize: 16)),
              );
            }),
        ],
      ),
    );
  }

  Widget _holdersPanel(List<Map<String, dynamic>> holders) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_manager ? 'Personel Kasaları' : 'Nakit Kasam', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (holders.isEmpty)
            const _EmptyBox(text: 'Henüz personelde nakit bulunmuyor.')
          else
            ...holders.map((h) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const CircleAvatar(child: Icon(Icons.person_outline)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h['full_name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 3),
                          Text('Alınan: ${money.format(_n(h['received']))} • Ana kasaya verilen: ${money.format(_n(h['transferred']))} • Personel gideri: ${money.format(_n(h['expenses']))}'),
                        ],
                      ),
                    ),
                    Text(money.format(_n(h['balance'])), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                    if (_manager && _n(h['balance']) > 0) ...[
                      const SizedBox(width: 10),
                      FilledButton(onPressed: () => _transfer(h), child: const Text('Ana Kasaya Çek')),
                    ],
                  ],
                ),
              ),
            )),
        ],
      ),
    );
  }

  Widget _cashMovements(
    List<Map<String, dynamic>> receipts,
    List<Map<String, dynamic>> expenses,
    List<Map<String, dynamic>> transfers,
  ) {
    final items = <_Movement>[];
    for (final r in receipts.take(10)) {
      items.add(_Movement(date: _dt(r['payment_date']) ?? DateTime(2000), type: 'receipt', row: r));
    }
    for (final r in expenses.take(10)) {
      items.add(_Movement(date: _dt(r['expense_at']) ?? DateTime(2000), type: 'expense', row: r));
    }
    for (final r in transfers.take(10)) {
      items.add(_Movement(date: _dt(r['created_at']) ?? DateTime(2000), type: 'transfer', row: r));
    }
    items.sort((a, b) => b.date.compareTo(a.date));
    final recent = items.take(10).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 26),
          const Text('Kasa Hareketleri (Son 10)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            const _EmptyBox(text: 'Henüz kasa hareketi yok.')
          else
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _movementCard(recent[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _movementCard(_Movement item) {
    final r = item.row;
    if (item.type == 'receipt') {
      return _MovementCard(
        icon: Icons.south_rounded,
        title: 'Nakit Tahsilat',
        name: r['customer_name']?.toString() ?? 'Müşteri',
        note: r['receiver_name']?.toString() ?? '-',
        amount: money.format(_n(r['amount'])),
        positive: true,
        time: DateFormat('HH:mm').format(item.date),
      );
    }
    if (item.type == 'transfer') {
      return _MovementCard(
        icon: Icons.swap_horiz_rounded,
        title: 'Kasa Transferi',
        name: '${r['from_profile_name'] ?? '-'} Kasası',
        note: 'Ana Kasaya aktarıldı',
        amount: money.format(_n(r['amount'])),
        time: DateFormat('HH:mm').format(item.date),
      );
    }
    return _MovementCard(
      icon: Icons.north_rounded,
      title: 'Gider',
      name: '${_categoryLabel(r['category'])} - ${r['beneficiary_name'] ?? '-'}',
      note: r['note']?.toString() ?? '',
      amount: '-${money.format(_n(r['amount']))}',
      negative: true,
      time: DateFormat('HH:mm').format(item.date),
    );
  }

  Future<void> _showExpenseDetail(Map<String, dynamic> r) async {
    final date = _dt(r['expense_at']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gider Detayı'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Tarih', date == null ? '-' : DateFormat('dd.MM.yyyy HH:mm').format(date)),
              _detailRow('Gider Türü', _categoryLabel(r['category'])),
              _detailRow('Kime / Kim İçin', r['beneficiary_name']?.toString() ?? '-'),
              _detailRow('Tutar', money.format(_n(r['amount']))),
              _detailRow('Ödeme Şekli', r['payment_source'] == 'personnel_cash' ? 'Personel Kasası' : 'Ana Kasa'),
              if (r['payment_source'] == 'personnel_cash') _detailRow('Ödeyen Kasa', r['source_profile_name']?.toString() ?? '-'),
              _detailRow('Açıklama', r['note']?.toString().isNotEmpty == true ? r['note'].toString() : '-'),
              _detailRow('Fiş / Fatura No', r['document_no']?.toString().isNotEmpty == true ? r['document_no'].toString() : '-'),
              _detailRow('Kaydeden', r['created_by_name']?.toString() ?? '-'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Color(0xFF66788A), fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );

  Future<void> _openExpenseDialog({Map<String, dynamic>? row}) async {
    final form = _ExpenseForm(
      staff: _staff,
      categories: _categories,
      busy: _busy,
      initial: row,
      onSave: (draft) async {
        await _saveExpense(draft, movementId: row?['id']?.toString());
        if (mounted) Navigator.of(context).maybePop();
      },
    );
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 760),
          child: SingleChildScrollView(child: form),
        ),
      ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    required this.staff,
    required this.categories,
    required this.busy,
    required this.onSave,
    this.initial,
  });

  final List<Map<String, dynamic>> staff;
  final Map<String, String> categories;
  final bool busy;
  final Future<void> Function(_ExpenseDraft draft) onSave;
  final Map<String, dynamic>? initial;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late String category;
  String? beneficiaryId;
  late String paymentSource;
  String? sourceProfileId;
  late DateTime date;
  late TextEditingController amount;
  late TextEditingController note;
  late TextEditingController documentNo;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    category = r?['category']?.toString() ?? 'fuel';
    beneficiaryId = r?['beneficiary_profile_id']?.toString();
    paymentSource = r?['payment_source']?.toString() ?? 'main_cash';
    sourceProfileId = r?['source_profile_id']?.toString();
    date = DateTime.tryParse(r?['expense_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    amount = TextEditingController(text: r == null ? '' : '${r['amount'] ?? ''}');
    note = TextEditingController(text: r?['note']?.toString() ?? '');
    documentNo = TextEditingController(text: r?['document_no']?.toString() ?? '');
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    documentNo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initial == null ? 'Yeni Gider Ekle' : 'Gideri Düzenle', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Gider Türü *'),
              items: widget.categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => category = v ?? 'other'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: beneficiaryId ?? '__general__',
              decoration: const InputDecoration(labelText: 'Kime / Kim İçin'),
              items: [
                const DropdownMenuItem<String>(value: '__general__', child: Text('Genel / Personel dışı')),
                ...widget.staff.map((s) => DropdownMenuItem<String>(value: s['id'].toString(), child: Text('${s['full_name']} (${_role(s['role'])})'))),
              ],
              onChanged: (v) => setState(() => beneficiaryId = v == '__general__' ? null : v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Tutar *', prefixText: '₺  '),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: paymentSource,
              decoration: const InputDecoration(labelText: 'Ödeme Şekli *'),
              items: const [
                DropdownMenuItem(value: 'main_cash', child: Text('Ana Kasa')),
                DropdownMenuItem(value: 'personnel_cash', child: Text('Personel Kasası')),
              ],
              onChanged: (v) => setState(() {
                paymentSource = v ?? 'main_cash';
                if (paymentSource == 'main_cash') sourceProfileId = null;
              }),
            ),
            if (paymentSource == 'personnel_cash') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: sourceProfileId,
                decoration: const InputDecoration(labelText: 'Hangi Personel Kasası? *'),
                items: widget.staff
                    .where((s) => !['admin', 'manager'].contains(s['role']?.toString()))
                    .map((s) => DropdownMenuItem<String?>(value: s['id'].toString(), child: Text(s['full_name']?.toString() ?? '-')))
                    .toList(),
                onChanged: (v) => setState(() => sourceProfileId = v),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(DateTime.now().year - 3),
                  lastDate: DateTime(DateTime.now().year + 2),
                  initialDate: date,
                );
                if (picked == null) return;
                setState(() => date = DateTime(picked.year, picked.month, picked.day, date.hour, date.minute));
              },
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Tarih *', suffixIcon: Icon(Icons.calendar_month_outlined)),
                child: Text(DateFormat('dd.MM.yyyy HH:mm').format(date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Açıklama')),
            const SizedBox(height: 12),
            TextField(controller: documentNo, decoration: const InputDecoration(labelText: 'Fiş / Fatura No')),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.busy ? null : _submit,
              icon: widget.busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(widget.initial == null ? 'Kaydet' : 'Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final parsed = _parseAmount(amount.text);
    if (parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçerli bir tutar girin.')));
      return;
    }
    if (paymentSource == 'personnel_cash' && sourceProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personel kasasını seçin.')));
      return;
    }
    await widget.onSave(_ExpenseDraft(
      category: category,
      beneficiaryId: beneficiaryId,
      amount: parsed,
      paymentSource: paymentSource,
      sourceProfileId: sourceProfileId,
      date: date,
      note: note.text.trim(),
      documentNo: documentNo.text.trim(),
    ));
    if (widget.initial == null && mounted) {
      amount.clear();
      note.clear();
      documentNo.clear();
      setState(() => date = DateTime.now());
    }
  }

  static double _parseAmount(String input) {
    var raw = input.trim().replaceAll('₺', '').replaceAll(' ', '');
    if (raw.isEmpty) return 0;
    final hasComma = raw.contains(',');
    final hasDot = raw.contains('.');
    if (hasComma && hasDot) {
      if (raw.lastIndexOf(',') > raw.lastIndexOf('.')) {
        raw = raw.replaceAll('.', '').replaceAll(',', '.');
      } else {
        raw = raw.replaceAll(',', '');
      }
    } else if (hasComma) {
      raw = raw.replaceAll(',', '.');
    }
    return double.tryParse(raw) ?? 0;
  }

  static String _role(Object? value) {
    return switch (value?.toString()) {
      'technician' => 'Tekniker',
      'secretary' => 'Sekreter',
      'manager' => 'Yönetici',
      'admin' => 'Admin',
      _ => 'Personel',
    };
  }
}

class _ExpenseDraft {
  const _ExpenseDraft({
    required this.category,
    required this.amount,
    required this.paymentSource,
    required this.date,
    this.beneficiaryId,
    this.sourceProfileId,
    this.note,
    this.documentNo,
  });

  final String category;
  final String? beneficiaryId;
  final double amount;
  final String paymentSource;
  final String? sourceProfileId;
  final DateTime date;
  final String? note;
  final String? documentNo;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.subtitle,
    this.negative = false,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;
  final String subtitle;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: negative ? const Color(0xFFFFE8E8) : const Color(0xFFE3F7F8),
                child: Icon(icon, color: negative ? Colors.red : const Color(0xFF0AA7B5)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Color(0xFF65788A), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF72869A), fontSize: 12)),
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.icon, required this.title, required this.value, required this.count});
  final IconData icon;
  final String title;
  final String value;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(radius: 18, backgroundColor: const Color(0xFFE7F8FA), child: Icon(icon, size: 19, color: const Color(0xFF0AA7B5))),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('$count işlem', style: const TextStyle(fontSize: 11, color: Color(0xFF71869B))),
            ]),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
        child: Center(child: Text(text, style: const TextStyle(color: Color(0xFF708399)))),
      );
}

class _Movement {
  const _Movement({required this.date, required this.type, required this.row});
  final DateTime date;
  final String type;
  final Map<String, dynamic> row;
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.icon,
    required this.title,
    required this.name,
    required this.note,
    required this.amount,
    required this.time,
    this.positive = false,
    this.negative = false,
  });

  final IconData icon;
  final String title;
  final String name;
  final String note;
  final String amount;
  final String time;
  final bool positive;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final accent = positive ? const Color(0xFF00A878) : negative ? Colors.red : const Color(0xFF1677FF);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE3EAF0)), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 19, backgroundColor: accent.withValues(alpha: .10), child: Icon(icon, size: 20, color: accent)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(amount, style: TextStyle(fontWeight: FontWeight.w900, color: accent))]),
              const SizedBox(height: 4),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6F8396))),
              const Spacer(),
              Align(alignment: Alignment.bottomRight, child: Text(time, style: const TextStyle(fontSize: 11, color: Color(0xFF71869B)))),
            ]),
          ),
        ],
      ),
    );
  }
}
