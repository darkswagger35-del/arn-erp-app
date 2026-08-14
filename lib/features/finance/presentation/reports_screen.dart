import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/finance_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late DateTime _start;
  late DateTime _end;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 1);
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: _start,
        end: _end.subtract(const Duration(days: 1)),
      ),
    );
    if (range == null) return;
    setState(() {
      _start = DateUtils.dateOnly(range.start);
      _end = DateUtils.dateOnly(range.end).add(const Duration(days: 1));
      _reloadKey++;
    });
  }

  void _reload() => setState(() => _reloadKey++);

  Future<_ReportBundle> _load() async {
    final repo = ref.read(financeRepositoryProvider);
    final result = await Future.wait<dynamic>([
      repo.summary(start: _start, end: _end),
      repo.reportDetails(start: _start, end: _end),
      repo.payments(start: _start, end: _end),
    ]);
    final summary = Map<String, dynamic>.from(result[0] as Map);
    final details = List<Map<String, dynamic>>.from(result[1] as List);
    final payments = List<Map<String, dynamic>>.from(result[2] as List);
    return _ReportBundle(
      summary: summary,
      details: details,
      payments: payments,
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    return ManagementShell(
      role: role,
      title: 'Raporlar',
      subtitle: 'İş süreçlerinizin finansal ve operasyonel özetini görüntüleyin.',
      dark: false,
      actions: [
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
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/manager/excel-transfer'),
          icon: const Icon(Icons.table_view_rounded, color: Color(0xFF1F9D55)),
          label: const Text("Excel'e Aktar"),
        ),
      ],
      child: FutureBuilder<_ReportBundle>(
        key: ValueKey(_reloadKey),
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ReportError(
              message: 'Raporlar yüklenemedi: ${snapshot.error}',
              onRetry: _reload,
            );
          }

          final bundle = snapshot.data ?? const _ReportBundle.empty();
          final revenue = _sumDetails(bundle.details);
          final collection = _sumPayments(bundle.payments);
          final openBalance = _num(bundle.summary['open_balance']);
          final activeCustomers = _num(bundle.summary['active_customers']).round();
          final completed = _completedCount(bundle.details);
          final chartPoints = _buildRevenuePoints(bundle.details);
          final distribution = _buildDistribution(bundle.details);
          final staff = _buildStaff(bundle.details);

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 1150
                      ? 5
                      : c.maxWidth >= 760
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
                    childAspectRatio: columns == 1 ? 3.2 : 2.05,
                    children: [
                      _ReportMetric(
                        title: 'Toplam Ciro',
                        value: money.format(revenue),
                        detail: '$completed işlem',
                        icon: Icons.show_chart_rounded,
                        color: const Color(0xFF2F80ED),
                      ),
                      _ReportMetric(
                        title: 'Toplam Tahsilat',
                        value: money.format(collection),
                        detail: '${bundle.payments.length} işlem',
                        icon: Icons.account_balance_wallet_outlined,
                        color: const Color(0xFF23B26D),
                      ),
                      _ReportMetric(
                        title: 'Toplam Açık Bakiye',
                        value: money.format(openBalance),
                        detail: openBalance == 0 ? '—' : 'Açık hesap',
                        icon: Icons.wallet_outlined,
                        color: const Color(0xFFF59A23),
                      ),
                      _ReportMetric(
                        title: 'Aktif Müşteri',
                        value: '$activeCustomers',
                        detail: 'Toplam',
                        icon: Icons.people_alt_outlined,
                        color: const Color(0xFF8B5CF6),
                      ),
                      _ReportMetric(
                        title: 'Tamamlanan Servis',
                        value: '$completed',
                        detail: 'Toplam',
                        icon: Icons.task_alt_rounded,
                        color: const Color(0xFF13AEB8),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 1060;
                  final line = _RevenueChartCard(
                    points: chartPoints,
                    money: money,
                  );
                  final donut = _DistributionCard(
                    rows: distribution,
                    money: money,
                  );
                  final performance = _StaffPerformanceCard(
                    rows: staff,
                    money: money,
                    onOpen: (row) => _showStaffDetails(row),
                  );
                  if (!wide) {
                    return Column(
                      children: [
                        line,
                        const SizedBox(height: 14),
                        donut,
                        const SizedBox(height: 14),
                        performance,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: line),
                      const SizedBox(width: 14),
                      Expanded(flex: 3, child: donut),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: performance),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _ReportTransactionsCard(
                rows: bundle.details,
                money: money,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showStaffDetails(_StaffRow row) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('${row.name} • ${row.role}'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReportDetailLine('İş / Servis', '${row.serviceCount}'),
              _ReportDetailLine('Ürün Adedi', _qty(row.productCount)),
              _ReportDetailLine(
                'Ciro',
                NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
                    .format(row.turnover),
              ),
              _ReportDetailLine('En Çok Kullanılan Ürün', row.topProduct),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  List<_RevenuePoint> _buildRevenuePoints(List<Map<String, dynamic>> rows) {
    final days = _end.difference(_start).inDays;
    final monthly = days > 62;
    final grouped = <DateTime, double>{};
    for (final row in rows) {
      final parsed = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      if (parsed == null) continue;
      final local = parsed.toLocal();
      final key = monthly
          ? DateTime(local.year, local.month)
          : DateTime(local.year, local.month, local.day);
      grouped[key] = (grouped[key] ?? 0) + _num(row['amount']);
    }
    final result = grouped.entries
        .map((e) => _RevenuePoint(e.key, e.value))
        .toList(growable: false)
      ..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  List<_DistributionRow> _buildDistribution(List<Map<String, dynamic>> rows) {
    final grouped = <String, double>{};
    for (final row in rows) {
      final type = _serviceTypeLabel(row['service_type']?.toString());
      grouped[type] = (grouped[type] ?? 0) + _num(row['amount']);
    }
    final result = grouped.entries
        .map((e) => _DistributionRow(e.key, e.value))
        .toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    return result.take(5).toList(growable: false);
  }

  List<_StaffRow> _buildStaff(List<Map<String, dynamic>> details) {
    final grouped = <String, _MutableStaff>{};
    final seen = <String, Set<String>>{};

    void addPerson(
      String name,
      String role,
      Map<String, dynamic> row,
    ) {
      final clean = name.trim();
      if (clean.isEmpty || clean.toLowerCase().contains('belirtilmedi')) return;
      final key = '$role::$clean';
      final staff = grouped.putIfAbsent(key, () => _MutableStaff(clean, role));
      final amount = _num(row['amount']);
      staff.turnover += amount;
      final paymentStatus = (row['payment_status']?.toString() ?? '').toLowerCase();
      if (paymentStatus == 'paid' || paymentStatus == 'odendi' || paymentStatus.contains('ödendi')) {
        staff.collected += amount;
      }
      staff.productCount += _num(row['quantity']);
      final record = '${row['source_type']}:${row['record_id']}';
      seen.putIfAbsent(key, () => <String>{}).add(record);
      final product = row['product_name']?.toString().trim() ?? '';
      if (product.isNotEmpty) {
        staff.products[product] = (staff.products[product] ?? 0) + _num(row['quantity']);
      }
    }

    for (final row in details) {
      addPerson(row['technician_name']?.toString() ?? '', 'Teknisyen', row);
      addPerson(row['secretary_name']?.toString() ?? '', 'Sekreter', row);
    }

    final result = <_StaffRow>[];
    for (final entry in grouped.entries) {
      final staff = entry.value;
      final productEntries = staff.products.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      result.add(
        _StaffRow(
          name: staff.name,
          role: staff.role,
          serviceCount: seen[entry.key]?.length ?? 0,
          productCount: staff.productCount,
          turnover: staff.turnover,
          collected: staff.collected,
          topProduct: productEntries.isEmpty ? '-' : productEntries.first.key,
        ),
      );
    }
    result.sort((a, b) => b.turnover.compareTo(a.turnover));
    return result.take(10).toList(growable: false);
  }

  static int _completedCount(List<Map<String, dynamic>> rows) {
    final ids = <String>{};
    for (final row in rows) {
      final source = row['source_type']?.toString() ?? '';
      final record = row['record_id']?.toString() ?? '';
      if (record.isNotEmpty) ids.add('$source:$record');
    }
    return ids.length;
  }

  static double _sumDetails(List<Map<String, dynamic>> rows) =>
      rows.fold<double>(0, (sum, row) => sum + _num(row['amount']));

  static double _sumPayments(List<Map<String, dynamic>> rows) =>
      rows.fold<double>(0, (sum, row) => sum + _num(row['amount']));

  static double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _qty(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  static String _serviceTypeLabel(String? value) => switch (value) {
        'new_installation' => 'Yeni Kurulum',
        'filter_change' => 'Filtre Değişimi',
        'maintenance' => 'Bakım',
        'fault' => 'Arıza',
        'membrane' => 'Membran',
        'external_filter' => 'Dış Filtre',
        'relocation' => 'Taşıma',
        'removal' => 'Söküm',
        _ => value?.trim().isNotEmpty == true ? value!.trim() : 'Diğer',
      };
}

class _ReportBundle {
  const _ReportBundle({
    required this.summary,
    required this.details,
    required this.payments,
  });

  const _ReportBundle.empty()
      : summary = const <String, dynamic>{},
        details = const <Map<String, dynamic>>[],
        payments = const <Map<String, dynamic>>[];

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> details;
  final List<Map<String, dynamic>> payments;
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
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

class _RevenuePoint {
  const _RevenuePoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.points, required this.money});
  final List<_RevenuePoint> points;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ciro Grafiği (₺)',
                style: TextStyle(
                  color: Color(0xFF10243A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 250,
                child: points.isEmpty
                    ? const Center(child: Text('Bu dönemde ciro verisi yok.'))
                    : CustomPaint(
                        painter: _LineChartPainter(points),
                        child: const SizedBox.expand(),
                      ),
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.horizontal_rule_rounded,
                      color: Color(0xFF2F80ED)),
                  SizedBox(width: 4),
                  Text('Ciro'),
                ],
              ),
            ],
          ),
        ),
      );
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter(this.points);
  final List<_RevenuePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 42.0;
    const top = 14.0;
    const bottom = 34.0;
    final chartW = size.width - left - 8;
    final chartH = size.height - top - bottom;
    final maxValue = math.max(
      1.0,
      points.fold<double>(0, (m, p) => math.max(m, p.value)),
    );
    final grid = Paint()
      ..color = const Color(0xFFE7EDF3)
      ..strokeWidth = 1;
    final line = Paint()
      ..color = const Color(0xFF2F80ED)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = const Color(0xFF2F80ED);
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);

    for (var i = 0; i <= 4; i++) {
      final y = top + chartH * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + chartW, y), grid);
      tp.text = TextSpan(
        text: NumberFormat.compact(locale: 'tr_TR')
            .format(maxValue * (1 - i / 4)),
        style: const TextStyle(color: Color(0xFF78899B), fontSize: 9),
      );
      tp.layout(maxWidth: 38);
      tp.paint(canvas, Offset(0, y - 6));
    }

    if (points.isEmpty) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? left + chartW / 2
          : left + chartW * i / (points.length - 1);
      final y = top + chartH - chartH * points[i].value / maxValue;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.6, dot);
      if (points.length <= 14 || i % math.max(1, points.length ~/ 10) == 0) {
        tp.text = TextSpan(
          text: points.length > 40
              ? DateFormat('MMM', 'tr_TR').format(points[i].date)
              : DateFormat('dd MMM', 'tr_TR').format(points[i].date),
          style: const TextStyle(color: Color(0xFF78899B), fontSize: 8),
        );
        tp.layout(maxWidth: 48);
        tp.paint(canvas, Offset(x - tp.width / 2, size.height - 18));
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _DistributionRow {
  const _DistributionRow(this.label, this.value);
  final String label;
  final double value;
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.rows, required this.money});
  final List<_DistributionRow> rows;
  final NumberFormat money;

  static const _colors = <Color>[
    Color(0xFF2F80ED),
    Color(0xFF13AEB8),
    Color(0xFF8B5CF6),
    Color(0xFFE65353),
    Color(0xFFF59A23),
  ];

  @override
  Widget build(BuildContext context) {
    final total = rows.fold<double>(0, (sum, row) => sum + row.value);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ciro Dağılımı',
              style: TextStyle(
                color: Color(0xFF10243A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 150,
              child: rows.isEmpty
                  ? const Center(child: Text('Dağılım verisi yok.'))
                  : CustomPaint(
                      painter: _DonutPainter(
                        values: rows.map((e) => e.value).toList(),
                        colors: _colors,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            const SizedBox(height: 8),
            ...List.generate(rows.length, (index) {
              final row = rows[index];
              final percent = total == 0 ? 0 : row.value / total * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colors[index % _colors.length],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${percent.toStringAsFixed(0)}% (${money.format(row.value)})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});
  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .38;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .48;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
    canvas.drawCircle(
      center,
      radius * .48,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _MutableStaff {
  _MutableStaff(this.name, this.role);
  final String name;
  final String role;
  double turnover = 0;
  double collected = 0;
  double productCount = 0;
  final Map<String, double> products = <String, double>{};
}

class _StaffRow {
  const _StaffRow({
    required this.name,
    required this.role,
    required this.serviceCount,
    required this.productCount,
    required this.turnover,
    required this.collected,
    required this.topProduct,
  });

  final String name;
  final String role;
  final int serviceCount;
  final double productCount;
  final double turnover;
  final double collected;
  final String topProduct;
}

class _StaffPerformanceCard extends StatelessWidget {
  const _StaffPerformanceCard({
    required this.rows,
    required this.money,
    required this.onOpen,
  });

  final List<_StaffRow> rows;
  final NumberFormat money;
  final ValueChanged<_StaffRow> onOpen;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Personel Performansı',
                      style: TextStyle(
                        color: Color(0xFF10243A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${rows.length} personel',
                    style: const TextStyle(
                      color: Color(0xFF0AA8B7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 36),
                  Expanded(flex: 3, child: Text('Personel', style: TextStyle(fontSize: 10, color: Color(0xFF718096), fontWeight: FontWeight.w800))),
                  SizedBox(width: 42, child: Text('İş', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF718096), fontWeight: FontWeight.w800))),
                  SizedBox(width: 88, child: Text('Ciro', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Color(0xFF718096), fontWeight: FontWeight.w800))),
                  SizedBox(width: 88, child: Text('Tahsilat', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Color(0xFF718096), fontWeight: FontWeight.w800))),
                ],
              ),
            ),
            const Divider(height: 1),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Bu dönemde personel performansı yok.'),
              )
            else
              ...rows.take(7).map((row) => InkWell(
                    onTap: () => onOpen(row),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFFE9F8F9),
                            child: Text(
                              _initials(row.name),
                              style: const TextStyle(
                                color: Color(0xFF0AA8B7),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  row.role,
                                  style: const TextStyle(
                                    color: Color(0xFF718096),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${row.serviceCount}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Text(
                              money.format(row.turnover),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Text(
                              money.format(row.collected),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      );

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _ReportTransactionsCard extends StatelessWidget {
  const _ReportTransactionsCard({required this.rows, required this.money});
  final List<Map<String, dynamic>> rows;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final display = rows.take(12).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              'Dönem İşlemleri',
              style: TextStyle(
                color: Color(0xFF10243A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Divider(height: 1),
          if (display.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Text('Bu dönemde işlem yok.'),
            )
          else
            ...display.map((row) {
              final date = DateTime.tryParse(
                row['transaction_date']?.toString() ?? '',
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        date == null
                            ? '-'
                            : DateFormat('dd.MM.yyyy').format(date.toLocal()),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['customer_name']?.toString() ?? 'Müşteri',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['product_name']?.toString() ??
                            _ReportsScreenState._serviceTypeLabel(
                              row['service_type']?.toString(),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['technician_name']?.toString() ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row['secretary_name']?.toString() ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        money.format(_ReportsScreenState._num(row['amount'])),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w900),
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

class _ReportDetailLine extends StatelessWidget {
  const _ReportDetailLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 170,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF10243A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.message, required this.onRetry});
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
