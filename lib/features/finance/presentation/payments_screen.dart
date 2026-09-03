import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/finance_providers.dart';

class FinancePaymentsScreen extends ConsumerStatefulWidget {
  const FinancePaymentsScreen({super.key});

  @override
  ConsumerState<FinancePaymentsScreen> createState() =>
      _FinancePaymentsScreenState();
}

class _FinancePaymentsScreenState extends ConsumerState<FinancePaymentsScreen> {
  late DateTime _start;
  late DateTime _end;
  String _preset = 'month';
  String _method = 'all';
  String _query = '';
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    _setPeriod('month', notify: false);
  }

  void _setPeriod(String preset, {bool notify = true}) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;
    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        break;
      case 'week':
        start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        end = start.add(const Duration(days: 7));
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year + 1, 1, 1);
        break;
      case 'month':
      default:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        break;
    }
    if (notify) {
      setState(() {
        _preset = preset;
        _start = start;
        _end = end;
        _reloadKey++;
      });
    } else {
      _preset = preset;
      _start = start;
      _end = end;
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: _start,
        end: _end.subtract(const Duration(days: 1)),
      ),
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      _start = DateUtils.dateOnly(picked.start);
      _end = DateUtils.dateOnly(picked.end).add(const Duration(days: 1));
      _reloadKey++;
    });
  }

  void _reload() => setState(() => _reloadKey++);

  Future<_PaymentsBundle> _load() async {
    final repo = ref.read(financeRepositoryProvider);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 1);

    final result = await Future.wait<List<Map<String, dynamic>>>([
      repo.payments(start: _start, end: _end),
      repo.payments(start: todayStart, end: todayEnd),
      repo.payments(start: monthStart, end: monthEnd),
    ]);
    return _PaymentsBundle(
      period: result[0],
      today: result[1],
      month: result[2],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return ManagementShell(
      role: role,
      title: 'Tahsilatlar',
      subtitle: 'Tahsilatları, ödeme yöntemlerine göre ve dönemsel olarak takip edin.',
      dark: false,
      actions: [
        _PeriodChip(
          label: 'Bugün',
          selected: _preset == 'today',
          onTap: () => _setPeriod('today'),
        ),
        const SizedBox(width: 6),
        _PeriodChip(
          label: 'Bu Hafta',
          selected: _preset == 'week',
          onTap: () => _setPeriod('week'),
        ),
        const SizedBox(width: 6),
        _PeriodChip(
          label: 'Bu Ay',
          selected: _preset == 'month',
          onTap: () => _setPeriod('month'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.chevron_left_rounded),
          label: Text(
            '${DateFormat('dd.MM.yyyy').format(_start)} - '
            '${DateFormat('dd.MM.yyyy').format(_end.subtract(const Duration(days: 1)))}',
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<_PaymentsBundle>(
        key: ValueKey(_reloadKey),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FinanceError(
              message: 'Tahsilatlar yüklenemedi: ${snapshot.error}',
              onRetry: _reload,
            );
          }

          final bundle = snapshot.data ?? const _PaymentsBundle.empty();
          final visible = _filter(bundle.period);
          final todayTotal = _sum(bundle.today);
          final todayCash = _sum(_byMethod(bundle.today, 'cash'));
          final todayCard = _sum(_byMethod(bundle.today, 'card'));
          final monthTotal = _sum(bundle.month);
          final monthCash = _sum(_byMethod(bundle.month, 'cash'));
          final monthCard = _sum(_byMethod(bundle.month, 'card'));
          final todayCardCommission = _commissionSum(_byMethod(bundle.today, 'card'));
          final monthCardCommission = _commissionSum(_byMethod(bundle.month, 'card'));
          final todayCardNet = _netSum(_byMethod(bundle.today, 'card'));
          final monthCardNet = _netSum(_byMethod(bundle.month, 'card'));

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 1350
                      ? 4
                      : c.maxWidth >= 820
                          ? 3
                          : c.maxWidth >= 520
                              ? 2
                              : 1;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: columns == 1 ? 3.2 : 1.9,
                    children: [
                      _FinanceMetric(
                        title: 'Bugünkü Tahsilat',
                        value: money.format(todayTotal),
                        detail: '${bundle.today.length} işlem',
                        icon: Icons.today_outlined,
                        color: const Color(0xFF2F80ED),
                      ),
                      _FinanceMetric(
                        title: 'Bugünkü Nakit',
                        value: money.format(todayCash),
                        detail: '${_byMethod(bundle.today, 'cash').length} işlem',
                        icon: Icons.payments_outlined,
                        color: const Color(0xFF23B26D),
                      ),
                      _FinanceMetric(
                        title: 'Bugünkü Kart',
                        value: money.format(todayCard),
                        detail: '${_byMethod(bundle.today, 'card').length} işlem',
                        icon: Icons.credit_card_outlined,
                        color: const Color(0xFF8B5CF6),
                      ),
                      _FinanceMetric(
                        title: 'Bugünkü Kart Net',
                        value: money.format(todayCardNet),
                        detail: 'Komisyon ${money.format(todayCardCommission)}',
                        icon: Icons.savings_outlined,
                        color: const Color(0xFF0EA5A8),
                      ),
                      _FinanceMetric(
                        title: 'Bu Ay Tahsilat',
                        value: money.format(monthTotal),
                        detail: '${bundle.month.length} işlem',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFFF59A23),
                      ),
                      _FinanceMetric(
                        title: 'Bu Ay Nakit',
                        value: money.format(monthCash),
                        detail: '${_byMethod(bundle.month, 'cash').length} işlem',
                        icon: Icons.account_balance_wallet_outlined,
                        color: const Color(0xFF23B26D),
                      ),
                      _FinanceMetric(
                        title: 'Bu Ay Kart',
                        value: money.format(monthCard),
                        detail: '${_byMethod(bundle.month, 'card').length} işlem',
                        icon: Icons.credit_card_rounded,
                        color: const Color(0xFF8B5CF6),
                      ),
                      _FinanceMetric(
                        title: 'Bu Ay Kart Net',
                        value: money.format(monthCardNet),
                        detail: 'Komisyon ${money.format(monthCardCommission)}',
                        icon: Icons.account_balance_outlined,
                        color: const Color(0xFF0EA5A8),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _PaymentsToolbar(
                preset: _preset,
                query: _query,
                method: _method,
                onPreset: _setPeriod,
                onQuery: (value) => setState(() => _query = value),
                onMethod: (value) => setState(() => _method = value),
                onClear: () {
                  setState(() {
                    _query = '';
                    _method = 'all';
                  });
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 980;
                  final chart = _PaymentChartCard(
                    rows: visible,
                    start: _start,
                    end: _end,
                    money: money,
                  );
                  final table = _PaymentsTable(
                    rows: visible,
                    money: money,
                    onOpen: (row) => _showDetail(row, money),
                  );
                  if (!wide) {
                    return Column(
                      children: [
                        chart,
                        const SizedBox(height: 14),
                        table,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: chart),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: table),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((row) {
      final service = _service(row);
      final matchesQuery = q.isEmpty ||
          _customerName(row).toLowerCase().contains(q) ||
          (row['description']?.toString().toLowerCase() ?? '').contains(q) ||
          _serviceTypeLabel(service['service_type']?.toString())
              .toLowerCase()
              .contains(q);
      final matchesMethod = _method == 'all' ||
          row['payment_method']?.toString() == _method;
      return matchesQuery && matchesMethod;
    }).toList(growable: false);
  }

  Future<void> _showDetail(
    Map<String, dynamic> row,
    NumberFormat money,
  ) async {
    final service = _service(row);
    final items = service['items'] is List
        ? List<Map<String, dynamic>>.from(service['items'] as List)
        : const <Map<String, dynamic>>[];
    final customer = row['customers'] is Map
        ? Map<String, dynamic>.from(row['customers'] as Map)
        : const <String, dynamic>{};
    final paymentDate = DateTime.tryParse(row['payment_date']?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE9F8F9),
                      child: Icon(Icons.receipt_long_outlined,
                          color: Color(0xFF0AA8B7)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName(row),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10243A),
                            ),
                          ),
                          Text(
                            money.format(_amount(row)),
                            style: const TextStyle(
                              color: Color(0xFF23B26D),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 26),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 28,
                          runSpacing: 12,
                          children: [
                            _FinanceDetail(
                              'Tarih',
                              paymentDate == null
                                  ? '-'
                                  : DateFormat('dd.MM.yyyy HH:mm', 'tr_TR')
                                      .format(paymentDate.toLocal()),
                            ),
                            _FinanceDetail(
                              'Ödeme',
                              _methodName(row['payment_method']?.toString()),
                            ),
                            if (row['payment_method']?.toString() == 'card')
                              _FinanceDetail('Taksit', '${(row['card_installments'] as num?)?.toInt() ?? 1}'),
                            if (row['payment_method']?.toString() == 'card')
                              _FinanceDetail('Komisyon', '${_num(row['card_commission_rate']).toStringAsFixed(2)}% • ${money.format(_num(row['card_commission_amount']))}'),
                            if (row['payment_method']?.toString() == 'card')
                              _FinanceDetail('Net Tahsilat', money.format(_netAmount(row))),
                            _FinanceDetail(
                              'Telefon',
                              customer['phone']?.toString() ?? '-',
                            ),
                            _FinanceDetail(
                              'Adres',
                              customer['address']?.toString() ?? '-',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _FinanceSection(
                          title: 'Servis Bilgileri',
                          children: [
                            _FinanceLine(
                              'Servis Türü',
                              _serviceTypeLabel(
                                service['service_type']?.toString(),
                              ),
                            ),
                            _FinanceLine(
                              'Teknisyen',
                              service['technician_name']?.toString() ?? '-',
                            ),
                            _FinanceLine(
                              'Sekreter / Talebi Açan',
                              _openedByLabel(service),
                            ),
                            _FinanceLine(
                              'Açıklama',
                              service['description']?.toString() ??
                                  row['description']?.toString() ??
                                  '-',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _FinanceSection(
                          title: 'Ürünler / Yapılan İşlemler',
                          children: items.isEmpty
                              ? const [
                                  Text(
                                    'Bu tahsilata bağlı ürün detayı bulunamadı.',
                                  ),
                                ]
                              : items.map((item) {
                                  final quantity = _num(item['quantity']);
                                  final unitPrice = _num(item['unit_price']);
                                  return _FinanceLine(
                                    item['product_name']?.toString() ?? 'Ürün',
                                    '${_qty(quantity)} × ${money.format(unitPrice)} = '
                                    '${money.format(quantity * unitPrice)}',
                                  );
                                }).toList(growable: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _byMethod(
    List<Map<String, dynamic>> rows,
    String method,
  ) =>
      rows
          .where((row) => row['payment_method']?.toString() == method)
          .toList(growable: false);

  static double _sum(List<Map<String, dynamic>> rows) =>
      rows.fold<double>(0, (sum, row) => sum + _amount(row));

  static double _commissionSum(List<Map<String, dynamic>> rows) =>
      rows.fold<double>(0, (sum, row) => sum + _num(row['card_commission_amount']));

  static double _netSum(List<Map<String, dynamic>> rows) =>
      rows.fold<double>(0, (sum, row) => sum + _netAmount(row));

  static double _netAmount(Map<String, dynamic> row) {
    final stored = _num(row['net_amount']);
    if (stored > 0 || _amount(row) == 0) return stored;
    return _amount(row) - _num(row['card_commission_amount']);
  }

  static double _amount(Map<String, dynamic> row) => _num(row['amount']);

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _service(Map<String, dynamic> row) =>
      row['_service'] is Map
          ? Map<String, dynamic>.from(row['_service'] as Map)
          : <String, dynamic>{};

  static String _customerName(Map<String, dynamic> row) {
    final customer = row['customers'] is Map
        ? Map<String, dynamic>.from(row['customers'] as Map)
        : <String, dynamic>{};
    final companyName = customer['company_name']?.toString().trim() ?? '';
    final fullName = customer['full_name']?.toString().trim() ?? '';
    return companyName.isNotEmpty
        ? companyName
        : fullName.isNotEmpty
            ? fullName
            : 'Müşteri belirtilmemiş';
  }

  static String _methodName(String? value) => switch (value) {
        'cash' => 'Nakit',
        'card' => 'Kart',
        'transfer' => 'Havale / EFT',
        'open_account' => 'Açık Hesap',
        _ => value ?? '-',
      };

  static String _serviceTypeLabel(String? value) => switch (value) {
        'new_installation' => 'Yeni Kurulum',
        'filter_change' => 'Filtre Değişimi',
        'maintenance' => 'Bakım',
        'fault' => 'Arıza',
        'membrane' => 'Membran Değişimi',
        'external_filter' => 'Dış Filtre',
        'relocation' => 'Taşıma',
        'removal' => 'Söküm',
        _ => value?.isNotEmpty == true ? value! : '-',
      };

  static String _openedByLabel(Map<String, dynamic> service) {
    final name = service['opened_by_name']?.toString().trim() ?? '';
    final role = service['opened_by_role']?.toString() ?? '';
    if (name.isEmpty) return '-';
    final roleLabel = switch (role) {
      'secretary' => 'Sekreter',
      'technician' => 'Teknisyen',
      'admin' => 'Admin',
      'manager' => 'Yönetici',
      _ => role,
    };
    return roleLabel.isEmpty ? name : '$name • $roleLabel';
  }

  static String _qty(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

class _PaymentsBundle {
  const _PaymentsBundle({
    required this.period,
    required this.today,
    required this.month,
  });

  const _PaymentsBundle.empty()
      : period = const <Map<String, dynamic>>[],
        today = const <Map<String, dynamic>>[],
        month = const <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> period;
  final List<Map<String, dynamic>> today;
  final List<Map<String, dynamic>> month;
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor:
              selected ? const Color(0xFF0AA8B7) : const Color(0xFF42566D),
          backgroundColor: selected ? const Color(0xFFE9F8F9) : Colors.white,
          side: BorderSide(
            color: selected
                ? const Color(0xFF61CDD5)
                : const Color(0xFFD9E3EC),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(label),
      );
}

class _FinanceMetric extends StatelessWidget {
  const _FinanceMetric({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: color.withOpacity(.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF10243A),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PaymentsToolbar extends StatelessWidget {
  const _PaymentsToolbar({
    required this.preset,
    required this.query,
    required this.method,
    required this.onPreset,
    required this.onQuery,
    required this.onMethod,
    required this.onClear,
  });

  final String preset;
  final String query;
  final String method;
  final ValueChanged<String> onPreset;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onMethod;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TextTab(
                label: 'Günlük',
                selected: preset == 'today',
                onTap: () => onPreset('today'),
              ),
              _TextTab(
                label: 'Haftalık',
                selected: preset == 'week',
                onTap: () => onPreset('week'),
              ),
              _TextTab(
                label: 'Aylık',
                selected: preset == 'month',
                onTap: () => onPreset('month'),
              ),
              _TextTab(
                label: 'Yıllık',
                selected: preset == 'year',
                onTap: () => onPreset('year'),
              ),
              const _TextTab(
                label: 'Özet',
                selected: false,
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 360,
                child: TextFormField(
                  initialValue: query,
                  onChanged: onQuery,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Müşteri, açıklama veya servis türü ara...',
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'Ödeme Yöntemi'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Tümü')),
                    DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                    DropdownMenuItem(value: 'card', child: Text('Kart')),
                    DropdownMenuItem(
                        value: 'transfer', child: Text('Havale / EFT')),
                    DropdownMenuItem(
                        value: 'open_account', child: Text('Açık Hesap')),
                  ],
                  onChanged: (value) => onMethod(value ?? 'all'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Temizle'),
              ),
            ],
          ),
        ),
      );
}

class _TextTab extends StatelessWidget {
  const _TextTab({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? const Color(0xFF0AA8B7)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: selected
                  ? const Color(0xFF0AA8B7)
                  : const Color(0xFF53657A),
            ),
          ),
        ),
      );
}

class _PaymentChartCard extends StatelessWidget {
  const _PaymentChartCard({
    required this.rows,
    required this.start,
    required this.end,
    required this.money,
  });

  final List<Map<String, dynamic>> rows;
  final DateTime start;
  final DateTime end;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final points = _groupByDay(rows, start, end);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tahsilat Grafiği (₺)',
              style: TextStyle(
                color: Color(0xFF10243A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 250,
              child: points.isEmpty
                  ? const Center(child: Text('Bu dönemde tahsilat yok.'))
                  : CustomPaint(
                      painter: _BarChartPainter(points),
                      child: const SizedBox.expand(),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 18,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF23B26D),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 7),
                const Text('Tahsilat Tutarı'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static List<_ChartPoint> _groupByDay(
    List<Map<String, dynamic>> rows,
    DateTime start,
    DateTime end,
  ) {
    final map = <DateTime, double>{};
    for (final row in rows) {
      final parsed = DateTime.tryParse(row['payment_date']?.toString() ?? '');
      if (parsed == null) continue;
      final local = parsed.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      map[day] = (map[day] ?? 0) + _FinancePaymentsScreenState._amount(row);
    }
    final result = map.entries
        .map((e) => _ChartPoint(e.key, e.value))
        .toList(growable: false)
      ..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }
}

class _ChartPoint {
  const _ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter(this.points);
  final List<_ChartPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const top = 12.0;
    const bottom = 35.0;
    final chartH = size.height - top - bottom;
    final chartW = size.width - left - 8;
    final gridPaint = Paint()
      ..color = const Color(0xFFE7EDF3)
      ..strokeWidth = 1;
    final barPaint = Paint()..color = const Color(0xFF23B26D);
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    final maxValue = math.max(
      1.0,
      points.fold<double>(0, (m, p) => math.max(m, p.value)),
    );

    for (var i = 0; i <= 4; i++) {
      final y = top + chartH * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + chartW, y), gridPaint);
      final value = maxValue * (1 - i / 4);
      textPainter.text = TextSpan(
        text: NumberFormat.compact(locale: 'tr_TR').format(value),
        style: const TextStyle(color: Color(0xFF75869A), fontSize: 9),
      );
      textPainter.layout(maxWidth: left - 6);
      textPainter.paint(canvas, Offset(0, y - 6));
    }

    final gap = 3.0;
    final barW = math.max(4.0, (chartW / math.max(points.length, 1)) - gap);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final h = chartH * p.value / maxValue;
      final x = left + i * (chartW / points.length) + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top + chartH - h, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, barPaint);

      if (points.length <= 16 || i % math.max(1, points.length ~/ 12) == 0) {
        textPainter.text = TextSpan(
          text: DateFormat('dd MMM', 'tr_TR').format(p.date),
          style: const TextStyle(color: Color(0xFF75869A), fontSize: 8),
        );
        textPainter.layout(maxWidth: 52);
        canvas.save();
        canvas.translate(x + barW / 2, size.height - 3);
        canvas.rotate(-0.65);
        textPainter.paint(canvas, Offset(-textPainter.width / 2, -10));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({
    required this.rows,
    required this.money,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> rows;
  final NumberFormat money;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    final display = rows.take(10).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tahsilat İşlemleri',
                    style: TextStyle(
                      color: Color(0xFF10243A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${rows.length} kayıt',
                  style: const TextStyle(
                    color: Color(0xFF0AA8B7),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (display.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: Text('Seçilen dönemde tahsilat yok.')),
            )
          else
            ...display.map((row) {
              final date = DateTime.tryParse(
                row['payment_date']?.toString() ?? '',
              );
              final service = _FinancePaymentsScreenState._service(row);
              return InkWell(
                onTap: () => onOpen(row),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 98,
                        child: Text(
                          date == null
                              ? '-'
                              : DateFormat('dd.MM.yy HH:mm')
                                  .format(date.toLocal()),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _FinancePaymentsScreenState._customerName(row),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _FinancePaymentsScreenState._serviceTypeLabel(
                            service['service_type']?.toString(),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MethodPill(
                        label: _FinancePaymentsScreenState._methodName(
                          row['payment_method']?.toString(),
                        ),
                        method: row['payment_method']?.toString() ?? '',
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: Text(
                          money.format(
                            _FinancePaymentsScreenState._amount(row),
                          ),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (display.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Text('Toplam', style: TextStyle(fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Text(
                    money.format(_FinancePaymentsScreenState._sum(rows)),
                    style: const TextStyle(
                      color: Color(0xFF10243A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({required this.label, required this.method});
  final String label;
  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      'cash' => const Color(0xFF23B26D),
      'card' => const Color(0xFF8B5CF6),
      'transfer' => const Color(0xFF2F80ED),
      _ => const Color(0xFF718096),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _FinanceDetail extends StatelessWidget {
  const _FinanceDetail(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF71879A), fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _FinanceSection extends StatelessWidget {
  const _FinanceSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE5EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF102033),
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _FinanceLine extends StatelessWidget {
  const _FinanceLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF52657A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(color: Color(0xFF102033)),
              ),
            ),
          ],
        ),
      );
}

class _FinanceError extends StatelessWidget {
  const _FinanceError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42, color: Color(0xFFE65353)),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
}
