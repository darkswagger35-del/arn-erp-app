import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../finance/data/finance_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  static const _background = Color(0xFF071624);
  static const _panel = Color(0xFF0C2033);
  static const _panelAlt = Color(0xFF102A40);
  static const _border = Color(0xFF1B4054);
  static const _cyan = Color(0xFF13C7DA);
  static const _blue = Color(0xFF2979FF);
  static const _purple = Color(0xFF9C4DFF);
  static const _green = Color(0xFF21C58E);
  static const _orange = Color(0xFFFF9F1C);
  static const _red = Color(0xFFFF4D67);

  late DateTime _start;
  late DateTime _end;
  int _reloadKey = 0;
  int _selectedReportSection = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 1);
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _start : _end.subtract(const Duration(days: 1));
    final value = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      if (start) {
        _start = value;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(days: 1));
        }
      } else {
        _end = value.add(const Duration(days: 1));
        if (!_end.isAfter(_start)) {
          _start = value;
        }
      }
      _reloadKey++;
    });
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      switch (preset) {
        case 'today':
          _start = DateTime(now.year, now.month, now.day);
          _end = _start.add(const Duration(days: 1));
          break;
        case 'week':
          _start = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _end = _start.add(const Duration(days: 7));
          break;
        case 'previous_month':
          _start = DateTime(now.year, now.month - 1, 1);
          _end = DateTime(now.year, now.month, 1);
          break;
        case 'year':
          _start = DateTime(now.year, 1, 1);
          _end = DateTime(now.year + 1, 1, 1);
          break;
        default:
          _start = DateTime(now.year, now.month, 1);
          _end = DateTime(now.year, now.month + 1, 1);
      }
      _reloadKey++;
    });
  }

  void _refresh() => setState(() => _reloadKey++);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1080;

    return Scaffold(
      backgroundColor: _background,
      body: Row(
        children: [
          if (desktop) _buildSidebar(),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(desktop),
                  Expanded(
                    child: FutureBuilder<_ReportBundle>(
                      key: ValueKey(_reloadKey),
                      future: _loadReports(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: _cyan),
                          );
                        }
                        if (snapshot.hasError) {
                          return _ErrorState(
                            message: 'Raporlar yüklenemedi: ${snapshot.error}',
                            onRetry: _refresh,
                          );
                        }
                        return _buildContent(
                          snapshot.data ?? const _ReportBundle.empty(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<_ReportBundle> _loadReports() async {
    final repository = ref.read(financeRepositoryProvider);

    // Döneme bağlı bütün raporları tek kaynaktan üretiriz. Böylece üstteki
    // ciro/servis kartları ile "Bu Dönemin İşlemleri" hiçbir zaman farklı
    // tarih aralığı veya farklı kayıt seti göstermez.
    final yearStart = DateTime(_start.year, 1, 1);
    final yearEnd = DateTime(_start.year + 1, 1, 1);
    final result = await Future.wait<dynamic>([
      repository.summary(start: _start, end: _end),
      repository.reportDetails(start: _start, end: _end),
      repository.reportDetails(start: yearStart, end: yearEnd),
    ]);

    final baseSummary = Map<String, dynamic>.from(result[0] as Map);
    final details = List<Map<String, dynamic>>.from(result[1] as List);
    final yearDetails = List<Map<String, dynamic>>.from(result[2] as List);
    final periodSummary = _periodSummaryFromDetails(baseSummary, details);

    return _ReportBundle(
      summary: periodSummary,
      topProducts: _topProductsFromDetails(details),
      staffPerformance: _staffPerformanceFromDetails(details),
      details: details,
      yearDetails: yearDetails,
    );
  }

  Map<String, dynamic> _periodSummaryFromDetails(
    Map<String, dynamic> base,
    List<Map<String, dynamic>> rows,
  ) {
    final serviceKeys = <String>{};
    var revenue = 0.0;
    var collection = 0.0;

    for (final row in rows) {
      final source = row['source_type']?.toString() ?? '';
      final record = row['record_id']?.toString() ?? '';
      serviceKeys.add('$source:$record');

      final amount = _asDouble(row['amount']);
      revenue += amount;
      final status = (row['payment_status']?.toString() ?? '').toLowerCase();
      if (status.contains('ödendi') || status == 'paid' || status == 'odendi') {
        collection += amount;
      }
    }

    return <String, dynamic>{
      ...base,
      'completed_period': serviceKeys.length,
      'revenue_period': revenue,
      'collection_period': collection,
    };
  }

  List<Map<String, dynamic>> _topProductsFromDetails(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final name = (row['product_name']?.toString().trim().isNotEmpty ?? false)
          ? row['product_name'].toString().trim()
          : 'Ürün';
      final item = grouped.putIfAbsent(name, () => <String, dynamic>{
            'product_name': name,
            'quantity': 0.0,
            'revenue': 0.0,
          });
      item['quantity'] = _asDouble(item['quantity']) + _asDouble(row['quantity']);
      item['revenue'] = _asDouble(item['revenue']) + _asDouble(row['amount']);
    }
    final result = grouped.values.toList();
    result.sort((a, b) {
      final byQuantity = _asDouble(b['quantity']).compareTo(_asDouble(a['quantity']));
      return byQuantity != 0
          ? byQuantity
          : _asDouble(b['revenue']).compareTo(_asDouble(a['revenue']));
    });
    return result.take(10).toList(growable: false);
  }

  Map<String, dynamic> _staffPerformanceFromDetails(
    List<Map<String, dynamic>> rows,
  ) {
    final technicians = _aggregateStaff(rows, 'technician_name', true);
    final secretaries = _aggregateStaff(rows, 'secretary_name', false);

    Map<String, dynamic> leader(List<Map<String, dynamic>> values, String key) {
      if (values.isEmpty) return <String, dynamic>{};
      final copy = [...values]
        ..sort((a, b) => _asDouble(b[key]).compareTo(_asDouble(a[key])));
      return copy.first;
    }

    final allStaff = [...technicians, ...secretaries];
    final productLeader = leader(allStaff, 'product_count');

    return <String, dynamic>{
      'technicians': technicians,
      'secretaries': secretaries,
      'leaders': <String, dynamic>{
        'technician': leader(technicians, 'turnover'),
        'secretary': leader(secretaries, 'turnover'),
        'product_user': productLeader,
      },
    };
  }

  List<Map<String, dynamic>> _aggregateStaff(
    List<Map<String, dynamic>> rows,
    String nameKey,
    bool technician,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    final records = <String, Set<String>>{};
    final products = <String, Map<String, double>>{};

    for (final row in rows) {
      final name = row[nameKey]?.toString().trim() ?? '';
      if (name.isEmpty || name.toLowerCase().contains('belirtilmedi')) continue;
      final item = grouped.putIfAbsent(name, () => <String, dynamic>{
            'full_name': name,
            'turnover': 0.0,
            'product_count': 0,
            'unsuccessful_services': 0,
            'cancelled_services': 0,
            'role': technician ? 'Teknisyen' : 'Sekreter',
          });
      item['turnover'] = _asDouble(item['turnover']) + _asDouble(row['amount']);
      item['product_count'] = (_asDouble(item['product_count']) + _asDouble(row['quantity'])).round();

      final recordKey = '${row['source_type']}:${row['record_id']}';
      records.putIfAbsent(name, () => <String>{}).add(recordKey);
      final productName = row['product_name']?.toString() ?? 'Ürün';
      final productMap = products.putIfAbsent(name, () => <String, double>{});
      productMap[productName] = (productMap[productName] ?? 0) + _asDouble(row['quantity']);
    }

    final result = grouped.entries.map((entry) {
      final item = entry.value;
      final count = records[entry.key]?.length ?? 0;
      final productMap = products[entry.key] ?? const <String, double>{};
      var topProduct = '-';
      var topCount = -1.0;
      for (final product in productMap.entries) {
        if (product.value > topCount) {
          topCount = product.value;
          topProduct = product.key;
        }
      }
      item[technician ? 'completed_services' : 'opened_services'] = count;
      item['top_product'] = topProduct;
      item['top_service_type'] = topProduct;
      item['average_service_amount'] = count == 0 ? 0 : _asDouble(item['turnover']) / count;
      return item;
    }).toList();

    result.sort((a, b) => _asDouble(b['turnover']).compareTo(_asDouble(a['turnover'])));
    for (var i = 0; i < result.length; i++) {
      result[i]['ranking'] = i + 1;
    }
    return result;
  }

  Widget _buildSidebar() {
    final auth = ref.watch(authControllerProvider);
    final items = <_NavItem>[
      const _NavItem('Ana Panel', Icons.home_outlined, '/admin-dashboard'),
      const _NavItem('Müşteriler', Icons.people_alt_outlined, '/manager/customers'),
      const _NavItem('Servis Talepleri', Icons.assignment_outlined, '/manager/service-requests'),
      const _NavItem('Takvim', Icons.calendar_month_outlined, '/manager/service-planning'),
      const _NavItem('Ürünler', Icons.inventory_2_outlined, '/manager/products'),
      const _NavItem('Stok Yönetimi', Icons.warehouse_outlined, '/manager/warehouses'),
      const _NavItem('Tahsilatlar', Icons.account_balance_wallet_outlined, '/manager/payments'),
      const _NavItem('Raporlar', Icons.analytics_outlined, '/manager/reports'),
      const _NavItem('Personeller', Icons.badge_outlined, '/manager/users'),
      const _NavItem('Bildirimler', Icons.notifications_none, '/notifications'),
      const _NavItem('Ayarlar', Icons.settings_outlined, '/manager/settings'),
    ];

    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: Color(0xFF08182A),
        border: Border(right: BorderSide(color: _border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: Image.asset(
                'assets/branding/motus_logo_light.png',
                height: 62,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _cyan,
                      child: Text('M', style: TextStyle(color: Colors.white)),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'MOTUS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: _border, height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = item.route == '/manager/reports';
                  return Material(
                    color: selected ? const Color(0xFF08738D) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go(item.route),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: selected ? Colors.white : const Color(0xFFB8C7D7),
                              size: 21,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                item.label,
                                style: TextStyle(
                                  color: selected ? Colors.white : const Color(0xFFD7E3EF),
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D2336),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: _cyan,
                    child: Icon(Icons.person_outline, color: Colors.white),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.profile?.fullName ?? 'Kullanıcı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Yönetici',
                          style: TextStyle(color: Color(0xFF91A7B9), fontSize: 12),
                        ),
                      ],
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

  Widget _buildHeader(bool desktop) {
    return Container(
      padding: EdgeInsets.fromLTRB(desktop ? 28 : 14, 18, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF08182A),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (!desktop)
            IconButton(
              onPressed: () => context.go('/admin-dashboard'),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Raporlar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'İş süreçlerinizin finansal ve operasyonel özeti',
                  style: TextStyle(color: Color(0xFF9CB0C2)),
                ),
              ],
            ),
          ),
          if (desktop)
            _HeaderDateButton(
              label:
                  '${DateFormat('dd.MM.yyyy').format(_start)} - ${DateFormat('dd.MM.yyyy').format(_end.subtract(const Duration(days: 1)))}',
              onPressed: () => _pickDate(true),
            ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Yenile',
            onPressed: _refresh,
            style: IconButton.styleFrom(
              backgroundColor: _panel,
              foregroundColor: Colors.white,
              side: const BorderSide(color: _border),
            ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(_ReportBundle bundle) {
    final data = bundle.summary;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final completed = _asDouble(data['completed_period']);
    final revenue = _asDouble(data['revenue_period']);
    final collection = _asDouble(data['collection_period']);
    final openBalance = _asDouble(data['open_balance']);
    final activeCustomers = _asDouble(data['active_customers']);

    final cards = <_KpiData>[
      _KpiData('Tamamlanan Servis', completed.toStringAsFixed(0), Icons.task_alt, _cyan),
      _KpiData('Dönem Cirosu', money.format(revenue), Icons.trending_up, _purple),
      _KpiData('Dönem Tahsilatı', money.format(collection), Icons.account_balance_wallet_outlined, _green),
      _KpiData('Toplam Açık Bakiye', money.format(openBalance), Icons.wallet_outlined, _orange),
      _KpiData('Aktif Müşteri', activeCustomers.toStringAsFixed(0), Icons.people_alt_outlined, _blue),
    ];

    return Scrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 30),
        children: [
          _buildFilters(),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1200
                  ? 3
                  : constraints.maxWidth >= 720
                      ? 2
                      : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: count == 1 ? 3.3 : 2.65,
                ),
                itemBuilder: (context, index) => _KpiCard(data: cards[index]),
              );
            },
          ),
          const SizedBox(height: 18),
          _ReportSectionSelector(
            selectedIndex: _selectedReportSection,
            onChanged: (value) => setState(() => _selectedReportSection = value),
          ),
          const SizedBox(height: 18),
          if (_selectedReportSection == 0) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final financial = _MonthlyRevenuePanel(
                  rows: bundle.yearDetails,
                  year: _start.year,
                );
                final distribution = _ProductDistributionPanel(
                  rows: bundle.topProducts,
                );
                if (!wide) {
                  return Column(
                    children: [
                      financial,
                      const SizedBox(height: 14),
                      distribution,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: financial),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: distribution),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _OperationTypePanel(
              rows: bundle.details,
              onOpen: (title, rows) => _showRowsDialog(title, rows),
            ),
            const SizedBox(height: 18),
            _TopProductsPanel(rows: bundle.topProducts),
          ] else if (_selectedReportSection == 1) ...[
            _OperationTypePanel(
              rows: bundle.details,
              onOpen: (title, rows) => _showRowsDialog(title, rows),
            ),
          ] else if (_selectedReportSection == 2) ...[
            _ReportDetailsPanel(rows: bundle.details),
          ] else ...[
            _StaffPerformanceSection(
              data: bundle.staffPerformance,
              onOpen: (name, role) {
                final key = role == 'technician' ? 'technician_name' : 'secretary_name';
                final rows = bundle.details
                    .where((row) => row[key]?.toString().trim() == name.trim())
                    .toList(growable: false);
                _showRowsDialog('$name - İşlem Detayları', rows);
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRowsDialog(
    String title,
    List<Map<String, dynamic>> rows,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: _background,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Divider(color: _border, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: _ReportDetailsPanel(rows: rows),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DateFilterButton(
            title: 'Başlangıç',
            value: DateFormat('dd.MM.yyyy').format(_start),
            onPressed: () => _pickDate(true),
          ),
          _DateFilterButton(
            title: 'Bitiş',
            value: DateFormat('dd.MM.yyyy')
                .format(_end.subtract(const Duration(days: 1))),
            onPressed: () => _pickDate(false),
          ),
          _PresetButton(label: 'Bugün', onPressed: () => _setPreset('today')),
          _PresetButton(label: 'Bu Hafta', onPressed: () => _setPreset('week')),
          _PresetButton(label: 'Bu Ay', onPressed: () => _setPreset('month')),
          _PresetButton(label: 'Geçen Ay', onPressed: () => _setPreset('previous_month')),
          _PresetButton(label: 'Bu Yıl', onPressed: () => _setPreset('year')),
          FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.filter_alt_outlined),
            label: const Text('Filtrele'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF087A98),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _ReportBundle {
  const _ReportBundle({
    required this.summary,
    required this.topProducts,
    required this.staffPerformance,
    required this.details,
    required this.yearDetails,
  });
  const _ReportBundle.empty()
      : summary = const <String, dynamic>{},
        topProducts = const <Map<String, dynamic>>[],
        staffPerformance = const <String, dynamic>{},
        details = const <Map<String, dynamic>>[],
        yearDetails = const <Map<String, dynamic>>[];

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> topProducts;
  final Map<String, dynamic> staffPerformance;
  final List<Map<String, dynamic>> details;
  final List<Map<String, dynamic>> yearDetails;
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

class _KpiData {
  const _KpiData(this.title, this.value, this.icon, this.color);
  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            data.color.withValues(alpha: .34),
            data.color.withValues(alpha: .10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: data.color.withValues(alpha: .10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: .20),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: data.color.withValues(alpha: .60)),
            ),
            child: Icon(data.icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: const TextStyle(color: Color(0xFFC1CFDC), fontSize: 13),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    data.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _MonthlyRevenuePanel extends StatelessWidget {
  const _MonthlyRevenuePanel({required this.rows, required this.year});

  final List<Map<String, dynamic>> rows;
  final int year;

  @override
  Widget build(BuildContext context) {
    final totals = List<double>.filled(12, 0);
    for (final row in rows) {
      final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      if (date == null) continue;
      final local = date.toLocal();
      if (local.year != year) continue;
      final amount = row['amount'] is num
          ? (row['amount'] as num).toDouble()
          : double.tryParse(row['amount']?.toString() ?? '') ?? 0;
      totals[local.month - 1] += amount;
    }
    final maxValue = totals.fold<double>(1, math.max);
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return _DarkPanel(
      title: '$year Aylık Ciro Grafiği',
      trailing: const _PanelBadge(text: '12 Ay'),
      child: SizedBox(
        height: 300,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(12, (index) {
            final value = totals[index];
            return Expanded(
              child: Tooltip(
                message: '${months[index]}: ${money.format(value)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        value == 0 ? '' : NumberFormat.compact(locale: 'tr_TR').format(value),
                        maxLines: 1,
                        style: const TextStyle(color: Color(0xFF9CB0C2), fontSize: 10),
                      ),
                      const SizedBox(height: 5),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: value == 0 ? 3 : 210 * (value / maxValue),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF13C7DA), Color(0xFF2979FF)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(months[index], style: const TextStyle(color: Color(0xFF91A7B9), fontSize: 10)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _OperationTypePanel extends StatelessWidget {
  const _OperationTypePanel({required this.rows, required this.onOpen});

  final List<Map<String, dynamic>> rows;
  final void Function(String title, List<Map<String, dynamic>> rows) onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final raw = row['service_type']?.toString().trim() ?? '';
      final fallback = row['product_name']?.toString().trim() ?? '';
      final name = raw.isNotEmpty && raw.toLowerCase() != 'geçmiş satış'
          ? _pretty(raw)
          : (fallback.isEmpty ? 'Diğer İşlem' : fallback);
      groups.putIfAbsent(name, () => []).add(row);
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => _revenue(b.value).compareTo(_revenue(a.value)));
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return _DarkPanel(
      title: 'İşlem Bazlı Ciro',
      trailing: _PanelBadge(text: '${entries.length} işlem türü'),
      child: entries.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Center(
                child: Text('Bu dönemde işlem bulunamadı.', style: TextStyle(color: Color(0xFF91A7B9))),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final count = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 650 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: count == 1 ? 3.4 : 2.1,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final quantity = entry.value.fold<double>(0, (sum, row) {
                      final value = row['quantity'];
                      return sum + (value is num ? value.toDouble() : double.tryParse('$value') ?? 0);
                    });
                    final revenue = _revenue(entry.value);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onOpen(entry.key, entry.value),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: const Color(0xFF102A40),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: const Color(0xFF1B4054)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.build_circle_outlined, color: Color(0xFF13C7DA)),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                                  ),
                                  const Icon(Icons.chevron_right, color: Color(0xFF91A7B9)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text('${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1)} adet',
                                style: const TextStyle(color: Color(0xFFBFD0DD), fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(money.format(revenue),
                                style: const TextStyle(color: Color(0xFF21C58E), fontSize: 18, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  static double _revenue(List<Map<String, dynamic>> rows) => rows.fold<double>(0, (sum, row) {
    final value = row['amount'];
    return sum + (value is num ? value.toDouble() : double.tryParse('$value') ?? 0);
  });

  static String _pretty(String value) {
    final text = value.replaceAll('_', ' ').trim();
    if (text.isEmpty) return 'Diğer İşlem';
    return text.split(' ').map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}').join(' ');
  }
}

class _FinancialPanel extends StatelessWidget {
  const _FinancialPanel({
    required this.revenue,
    required this.collection,
    required this.openBalance,
  });

  final double revenue;
  final double collection;
  final double openBalance;

  @override
  Widget build(BuildContext context) {
    final maxValue = math.max(1, math.max(revenue, math.max(collection, openBalance)));
    final points = <double>[
      revenue / maxValue,
      collection / maxValue,
      openBalance / maxValue,
    ];

    return _DarkPanel(
      title: 'Dönemsel Finans Analizi',
      trailing: const _PanelBadge(text: 'Seçili Dönem'),
      child: Column(
        children: [
          SizedBox(
            height: 210,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(points: points),
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Ciro', style: TextStyle(color: Color(0xFF91A7B9), fontSize: 11)),
                      Text('Tahsilat', style: TextStyle(color: Color(0xFF91A7B9), fontSize: 11)),
                      Text('Açık Bakiye', style: TextStyle(color: Color(0xFF91A7B9), fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ProgressRow(
            label: 'Ciro',
            value: revenue,
            ratio: revenue / maxValue,
            color: const Color(0xFF13C7DA),
          ),
          _ProgressRow(
            label: 'Tahsilat',
            value: collection,
            ratio: collection / maxValue,
            color: const Color(0xFF21C58E),
          ),
          _ProgressRow(
            label: 'Açık Bakiye',
            value: openBalance,
            ratio: openBalance / maxValue,
            color: const Color(0xFFFF9F1C),
          ),
        ],
      ),
    );
  }
}

class _ProductDistributionPanel extends StatelessWidget {
  const _ProductDistributionPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final top = rows.take(5).toList(growable: false);
    final total = top.fold<double>(
      0,
      (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
    );

    return _DarkPanel(
      title: 'Ürün Kullanım Dağılımı',
      trailing: const _PanelBadge(text: 'İlk 5'),
      child: top.isEmpty
          ? const SizedBox(
              height: 270,
              child: Center(
                child: Text(
                  'Bu dönemde ürün kullanımı yok.',
                  style: TextStyle(color: Color(0xFF91A7B9)),
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 150,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: top
                          .map((row) =>
                              ((row['quantity'] as num?)?.toDouble() ?? 0))
                          .toList(),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Toplam',
                            style: TextStyle(color: Color(0xFF91A7B9)),
                          ),
                          Text(
                            total.toStringAsFixed(total % 1 == 0 ? 0 : 1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...top.asMap().entries.map((entry) {
                  const colors = [
                    Color(0xFF2979FF),
                    Color(0xFF21C58E),
                    Color(0xFFFF9F1C),
                    Color(0xFFFF4D67),
                    Color(0xFF9C4DFF),
                  ];
                  final row = entry.value;
                  final quantity =
                      ((row['quantity'] as num?)?.toDouble() ?? 0);
                  final ratio = total <= 0 ? 0 : quantity / total;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: colors[entry.key % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            row['product_name']?.toString() ?? '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFD6E2EC)),
                          ),
                        ),
                        Text(
                          '${(ratio * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _TopProductsPanel extends StatelessWidget {
  const _TopProductsPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final top = rows.take(10).toList(growable: false);
    final maxQty = top.fold<double>(
      1,
      (value, row) => math.max(
        value,
        ((row['quantity'] as num?)?.toDouble() ?? 0),
      ),
    );

    return _DarkPanel(
      title: 'En Çok Kullanılan Ürünler',
      trailing: _PanelBadge(text: '${top.length} ürün'),
      child: top.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Center(
                child: Text(
                  'Bu dönemde kullanılan ürün yok.',
                  style: TextStyle(color: Color(0xFF91A7B9)),
                ),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: _TableHeader('Ürün Adı')),
                      Expanded(flex: 3, child: _TableHeader('Kullanım')),
                      Expanded(child: _TableHeader('Adet')),
                      Expanded(flex: 2, child: _TableHeader('Toplam Tutar')),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF1B4054), height: 1),
                ...top.map((row) {
                  final quantity =
                      ((row['quantity'] as num?)?.toDouble() ?? 0);
                  final revenue =
                      ((row['revenue'] as num?)?.toDouble() ?? 0);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF16364A)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            row['product_name']?.toString() ?? '-',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: quantity / maxQty,
                                minHeight: 8,
                                backgroundColor: const Color(0xFF173248),
                                valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF13C7DA),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 1),
                            style: const TextStyle(color: Color(0xFFD6E2EC)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            money.format(revenue),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xFF61E6BA),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _DarkPanel extends StatelessWidget {
  const _DarkPanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2033),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1B4054)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PanelBadge extends StatelessWidget {
  const _PanelBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF112B40),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF26506A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFBFD0DD),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final double value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(color: Color(0xFFB8C7D7))),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1),
                minHeight: 9,
                backgroundColor: const Color(0xFF173248),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              money.format(value),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



class _ReportSectionSelector extends StatelessWidget {
  const _ReportSectionSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Genel Özet', 'İşlem Bazlı Rapor', 'Bu Dönemin İşlemleri', 'Personel Performansı'];
    const icons = [Icons.dashboard_outlined, Icons.category_outlined, Icons.receipt_long_outlined, Icons.groups_2_outlined];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C2033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1B4054)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return FilledButton.icon(
            onPressed: () => onChanged(index),
            icon: Icon(icons[index], size: 19),
            label: Text(labels[index]),
            style: FilledButton.styleFrom(
              backgroundColor: selected ? const Color(0xFF087F9A) : const Color(0xFF102A40),
              foregroundColor: Colors.white,
              side: BorderSide(color: selected ? const Color(0xFF13C7DA) : const Color(0xFF1B4054)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          );
        }),
      ),
    );
  }
}

class _ReportDetailsPanel extends StatelessWidget {
  const _ReportDetailsPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C2033),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1B4054)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bu Dönemin İşlemleri', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text('Ciro ve servis kartlarındaki rakamları oluşturan kayıtlar', style: TextStyle(color: Color(0xFF91A7B9))),
                    ],
                  ),
                ),
                Text('${rows.length} kayıt', style: const TextStyle(color: Color(0xFF13C7DA), fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const Divider(color: Color(0xFF1B4054), height: 1),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('Seçili tarih aralığında işlem bulunamadı.', style: TextStyle(color: Color(0xFF91A7B9)))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(color: Color(0xFF17384A), height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                final amount = row['amount'] is num ? (row['amount'] as num).toDouble() : double.tryParse('${row['amount']}') ?? 0;
                final date = DateTime.tryParse('${row['transaction_date']}');
                return ExpansionTile(
                  iconColor: const Color(0xFF13C7DA),
                  collapsedIconColor: const Color(0xFF91A7B9),
                  title: Text(row['customer_name']?.toString() ?? 'Müşteri', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${row['product_name'] ?? row['service_type'] ?? 'İşlem'} • ${date == null ? '-' : DateFormat('dd.MM.yyyy HH:mm').format(date.toLocal())}',
                    style: const TextStyle(color: Color(0xFF91A7B9)),
                  ),
                  trailing: Text(money.format(amount), style: const TextStyle(color: Color(0xFF21C58E), fontSize: 16, fontWeight: FontWeight.w900)),
                  childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  children: [
                    _DetailLine('Kaynak', row['source_type']?.toString() == 'historical' ? 'Excel / Eski Kayıt' : 'Tamamlanan Servis'),
                    _DetailLine('Servis Türü', _reportServiceTypeLabel(row['service_type']?.toString())),
                    _DetailLine('Ürün', row['product_name']?.toString() ?? '-'),
                    _DetailLine('Adet', row['quantity']?.toString() ?? '-'),
                    _DetailLine('Teknisyen', row['technician_name']?.toString() ?? '-'),
                    _DetailLine('Talebi Açan', _reportOpenedBy(row)),
                    _DetailLine('Ödeme', row['payment_status']?.toString() ?? '-'),
                    _DetailLine('Not / Yapılan İşlem', row['description']?.toString() ?? '-'),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

String _reportServiceTypeLabel(String? value) => switch (value) {
  'new_installation' => 'Cihaz Satışı / Montaj',
  'filter_change' => 'Filtre Değişimi',
  'maintenance' => 'Bakım',
  'fault' => 'Arıza',
  'membrane' => 'Membran Değişimi',
  'external_filter' => 'Dış Filtre',
  'relocation' => 'Taşıma',
  'removal' => 'Söküm',
  _ => value?.trim().isNotEmpty == true ? value! : '-',
};

String _reportOpenedBy(Map<String, dynamic> row) {
  final secretary = row['secretary_name']?.toString().trim() ?? '';
  if (secretary.isNotEmpty) return '$secretary • Sekreter';
  final name = row['opened_by_name']?.toString().trim() ?? '';
  final role = row['opened_by_role']?.toString().trim() ?? '';
  if (name.isEmpty) return '-';
  final roleLabel = switch (role) {
    'admin' => 'Admin',
    'manager' => 'Yönetici',
    'technician' => 'Teknisyen',
    'secretary' => 'Sekreter',
    _ => role,
  };
  return roleLabel.isEmpty ? name : '$name • $roleLabel';
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 155, child: Text(label, style: const TextStyle(color: Color(0xFF91A7B9), fontWeight: FontWeight.w700))),
            Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
          ],
        ),
      );
}

class _StaffPerformanceSection extends StatelessWidget {
  const _StaffPerformanceSection({required this.data, required this.onOpen});

  final Map<String, dynamic> data;
  final void Function(String name, String role) onOpen;

  List<Map<String, dynamic>> _rows(String key) {
    final value = data[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final technicians = _rows('technicians');
    final secretaries = _rows('secretaries');
    final leaders = _map(data['leaders']);
    final technicianLeader = _map(leaders['technician']);
    final secretaryLeader = _map(leaders['secretary']);
    final productLeader = _map(leaders['product_user']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personel Performansı',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Seçili tarih aralığındaki teknisyen ve sekreter performansları',
          style: TextStyle(color: Color(0xFF91A7B9)),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth >= 1000 ? 3 : 1;
            final cards = [
              _LeaderCard(
                title: 'Ciro Lideri Teknisyen',
                name: technicianLeader['full_name']?.toString() ?? '-',
                value: _money(technicianLeader['turnover']),
                subtitle:
                    '${_integer(technicianLeader['completed_services'])} tamamlanan servis',
                icon: Icons.engineering_outlined,
                color: const Color(0xFF13C7DA),
              ),
              _LeaderCard(
                title: 'Ciro Lideri Sekreter',
                name: secretaryLeader['full_name']?.toString() ?? '-',
                value: _money(secretaryLeader['turnover']),
                subtitle:
                    '${_integer(secretaryLeader['opened_services'])} açılan servis',
                icon: Icons.support_agent_outlined,
                color: const Color(0xFF9C4DFF),
              ),
              _LeaderCard(
                title: 'En Çok Ürün Kullanan',
                name: productLeader['full_name']?.toString() ?? '-',
                value: '${_integer(productLeader['product_count'])} ürün',
                subtitle: productLeader['role']?.toString() ?? '-',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF21C58E),
              ),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: count == 1 ? 4.2 : 2.5,
              ),
              itemBuilder: (_, index) => cards[index],
            );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final technicianPanel = _PersonnelTable(
              title: 'Teknisyen Performansı',
              role: 'technician',
              rows: technicians,
              onOpen: onOpen,
            );
            final secretaryPanel = _PersonnelTable(
              title: 'Sekreter Performansı',
              role: 'secretary',
              rows: secretaries,
              onOpen: onOpen,
            );
            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  technicianPanel,
                  const SizedBox(height: 14),
                  secretaryPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: technicianPanel),
                const SizedBox(width: 14),
                Expanded(child: secretaryPanel),
              ],
            );
          },
        ),
      ],
    );
  }

  static int _integer(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _money(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(number);
  }
}

class _LeaderCard extends StatelessWidget {
  const _LeaderCard({
    required this.title,
    required this.name,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String name;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .28), color.withValues(alpha: .08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: .55)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFFAFC0CE), fontSize: 12)),
                const SizedBox(height: 4),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17)),
                const SizedBox(height: 3),
                Text('$value • $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonnelTable extends StatelessWidget {
  const _PersonnelTable({
    required this.title,
    required this.role,
    required this.rows,
    required this.onOpen,
  });

  final String title;
  final String role;
  final List<Map<String, dynamic>> rows;
  final void Function(String name, String role) onOpen;

  @override
  Widget build(BuildContext context) {
    return _DarkPanel(
      title: title,
      trailing: _PanelBadge(text: '${rows.length} personel'),
      child: rows.isEmpty
          ? const SizedBox(
              height: 160,
              child: Center(
                child: Text('Bu dönemde personel verisi yok.',
                    style: TextStyle(color: Color(0xFF91A7B9))),
              ),
            )
          : Column(
              children: rows.map((row) {
                final rank = _int(row['ranking']);
                final name = row['full_name']?.toString() ?? '-';
                final turnover = _money(row['turnover']);
                final serviceCount = role == 'technician'
                    ? _int(row['completed_services'])
                    : _int(row['opened_services']);
                final productCount = _int(row['product_count']);
                final topProduct = row['top_product']?.toString() ?? '-';
                final failure = role == 'technician'
                    ? _int(row['unsuccessful_services'])
                    : _int(row['cancelled_services']);
                final extra = role == 'technician'
                    ? 'Ortalama: ${_money(row['average_service_amount'])}'
                    : 'En çok: ${row['top_service_type']?.toString() ?? '-'}';
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onOpen(name, role),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFF102A40),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1B4054)),
                      ),
                      child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rank == 1
                              ? const Color(0xFFFFB020).withValues(alpha: .20)
                              : const Color(0xFF13C7DA).withValues(alpha: .12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: rank == 1
                                ? const Color(0xFFFFB020)
                                : const Color(0xFF2A536C),
                          ),
                        ),
                        child: Text('#$rank',
                            style: TextStyle(
                              color: rank == 1
                                  ? const Color(0xFFFFC550)
                                  : const Color(0xFFBFD0DD),
                              fontWeight: FontWeight.w900,
                            )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900)),
                                ),
                                Text(turnover,
                                    style: const TextStyle(
                                        color: Color(0xFF21C58E),
                                        fontWeight: FontWeight.w900)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$serviceCount servis • $productCount ürün • Hata/iptal: $failure',
                              style: const TextStyle(
                                  color: Color(0xFFB2C2CF), fontSize: 12),
                            ),
                            const SizedBox(height: 3),
                            Text('$extra • Ürün: $topProduct',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF7FA0B5), fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
    );
  }

  int _int(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(number);
  }
}

class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final String title;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined, size: 19),
      label: Text('$title: $value'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE4EDF4),
        side: const BorderSide(color: Color(0xFF2A536C)),
        backgroundColor: const Color(0xFF10283B),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFBFD0DD),
        backgroundColor: const Color(0xFF10283B),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}

class _HeaderDateButton extends StatelessWidget {
  const _HeaderDateButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE4EDF4),
        backgroundColor: const Color(0xFF0C2033),
        side: const BorderSide(color: Color(0xFF1B4054)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF91A7B9),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.points});
  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    const gridColor = Color(0xFF17364A);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final path = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height - (points[i] * size.height * .86) - 10;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6613C7DA), Color(0x0013C7DA)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF13C7DA)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    const colors = [
      Color(0xFF2979FF),
      Color(0xFF21C58E),
      Color(0xFFFF9F1C),
      Color(0xFFFF4D67),
      Color(0xFF9C4DFF),
    ];
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;

    if (total <= 0) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = const Color(0xFF17364A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22,
      );
      return;
    }

    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * math.pi * 2;
      canvas.drawArc(
        rect,
        start,
        math.max(0, sweep - .025),
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0C2033),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF7D3343)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF6B7F), size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}
