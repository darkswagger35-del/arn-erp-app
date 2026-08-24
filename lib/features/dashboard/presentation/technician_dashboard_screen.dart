import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../../service_execution/data/service_execution_providers.dart';
import '../../service_execution/data/service_execution_repository.dart';
import '../../settings/data/company_app_settings.dart';

class TechnicianDashboardScreen extends ConsumerStatefulWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  ConsumerState<TechnicianDashboardScreen> createState() =>
      _TechnicianDashboardScreenState();
}

class _TechnicianDashboardScreenState
    extends ConsumerState<TechnicianDashboardScreen> {
  late Future<_DashboardData> _future;
  DateTime _selectedDate = DateTime.now();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  bool _sameDay(DateTime? value, DateTime day) {
    if (value == null) return false;
    final local = value.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }

  Future<_DashboardData> _load() async {
    final repo = ref.read(serviceExecutionRepositoryProvider);
    final results = await Future.wait([
      repo.getTechnicianJobs(''),
      repo.getCompletedJobsForDay(_selectedDate),
      repo.getFailedJobsForDay(_selectedDate),
      repo.getTechnicianDayPerformance(_selectedDate),
      repo.getActiveProducts(ref.read(authControllerProvider).profile?.id ?? ''),
    ]);
    return _DashboardData(
      active: results[0] as List<TechnicianJob>,
      completed: results[1] as List<TechnicianJob>,
      failed: results[2] as List<TechnicianJob>,
      performance: results[3] as TechnicianDayPerformance,
      vehicleProducts: results[4] as List<Map<String, dynamic>>,
      referenceDay: _selectedDate,
    );
  }

  void _refresh() => setState(() => _future = _load());

  void _moveDay(int days) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );
      _filter = 'all';
      _future = _load();
    });
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
    setState(() {
      _selectedDate = picked;
      _filter = 'all';
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final fullName = auth.profile?.fullName.trim();
    final name = (fullName?.isNotEmpty ?? false) ? fullName! : 'Teknisyen';
    final panelSettings = ref.watch(companyAppSettingsProvider).asData?.value ??
        const CompanyAppSettings(companyId: '');
    bool showPanel(String key) => panelSettings.panelVisible('technician', key);

    return ManagementShell(
      role: AppRole.technician,
      title: 'Merhaba, $name 👋',
      subtitle: 'Seçtiğiniz günün performansını buradan takip edebilirsiniz.',
      actions: [
        IconButton(
          tooltip: 'Önceki gün',
          onPressed: () => _moveDay(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            DateFormat('dd MMMM yyyy, EEEE', 'tr_TR').format(_selectedDate),
          ),
        ),
        IconButton(
          tooltip: 'Sonraki gün',
          onPressed: () => _moveDay(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Panel yüklenemedi: ${snapshot.error}'));
          }

          final data = snapshot.data ??
              _DashboardData(
                referenceDay: _selectedDate,
                performance: const TechnicianDayPerformance(),
              );
          final activeForDay = data.activeForDay;
          final inProgress =
              activeForDay.where((job) => job.status == 'in_progress').toList();
          final late = data.lateJobs;
          final tomorrow = data.tomorrowJobs;
          final totalForDay = activeForDay.length + data.completed.length + data.failed.length;

          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                if (showPanel('metrics'))
                  LayoutBuilder(
                  builder: (context, c) {
                    final width = c.maxWidth;
                    final count = width >= 1200 ? 5 : width >= 760 ? 3 : 1;
                    const gap = 12.0;
                    final cardWidth = (width - gap * (count - 1)) / count;
                    final cards = <Widget>[
                      _MetricCard(
                        selected: _filter == 'all',
                        icon: Icons.calendar_today_rounded,
                        label: 'Seçili Gün İşleri',
                        value: '$totalForDay',
                        subtitle: 'Toplam iş',
                        accent: const Color(0xFF2D7EF7),
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      _MetricCard(
                        selected: _filter == 'progress',
                        icon: Icons.timelapse_rounded,
                        label: 'Devam Eden',
                        value: '${inProgress.length}',
                        subtitle: 'Aktif servis',
                        accent: const Color(0xFFF6A313),
                        onTap: () => setState(() => _filter = 'progress'),
                      ),
                      _MetricCard(
                        selected: _filter == 'completed',
                        icon: Icons.check_circle_outline_rounded,
                        label: 'Tamamlanan',
                        value: '${data.completed.length}',
                        subtitle:
                            '${_qty(data.performance.usedItemCount)} ürün • ${_money(data.performance.totalRevenue)}',
                        accent: const Color(0xFF19A866),
                        onTap: () => setState(() => _filter = 'completed'),
                      ),
                      _MetricCard(
                        selected: _filter == 'failed',
                        icon: Icons.report_problem_outlined,
                        label: 'Yapılamayan / Aktarılan',
                        value: '${data.failed.length}',
                        subtitle: data.failed.isEmpty ? 'Kayıt yok' : 'Tamamlanamadı / iptal / aktarım',
                        accent: const Color(0xFFE67E22),
                        onTap: () => setState(() => _filter = 'failed'),
                      ),
                      _MetricCard(
                        selected: false,
                        icon: Icons.event_repeat_rounded,
                        label: 'Yarının İşleri',
                        value: '${tomorrow.length}',
                        subtitle: 'Planlanan servis',
                        accent: const Color(0xFF7954E8),
                        onTap: () => _moveDay(1),
                      ),
                      _MetricCard(
                        selected: _filter == 'late',
                        icon: Icons.warning_amber_rounded,
                        label: 'Geciken',
                        value: '${late.length}',
                        subtitle: late.isEmpty ? 'Geciken servis yok' : 'Kontrol gerekli',
                        accent: const Color(0xFFE7494E),
                        onTap: () => setState(() => _filter = 'late'),
                      ),
                    ];
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: cards
                          .map((card) => SizedBox(width: cardWidth, child: card))
                          .toList(growable: false),
                    );
                  },
                ),
                if (showPanel('metrics') && showPanel('morning_preparation'))
                  const SizedBox(height: 16),
                if (showPanel('morning_preparation'))
                  _MorningPreparationPanel(
                    jobs: activeForDay,
                    vehicleProducts: data.vehicleProducts,
                    onOpenJobs: () => context.go('/technician/jobs'),
                  ),
                if ((showPanel('metrics') || showPanel('morning_preparation')) &&
                    showPanel('performance'))
                  const SizedBox(height: 16),
                if (showPanel('performance'))
                  _Panel(
                  title: 'Günlük Performans Özeti',
                  subtitle:
                      DateFormat('dd MMMM yyyy, EEEE', 'tr_TR').format(_selectedDate),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final width = c.maxWidth;
                      final count = width >= 900 ? 4 : width >= 520 ? 2 : 1;
                      const gap = 10.0;
                      final itemWidth = (width - gap * (count - 1)) / count;
                      final p = data.performance;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          _MiniStat(
                            width: itemWidth,
                            label: 'Toplam Ciro',
                            value: _money(p.totalRevenue),
                            icon: Icons.trending_up_rounded,
                          ),
                          _MiniStat(
                            width: itemWidth,
                            label: 'Tahsilat',
                            value: _money(p.collectedAmount),
                            icon: Icons.payments_outlined,
                          ),
                          _MiniStat(
                            width: itemWidth,
                            label: 'Kullanılan Ürün',
                            value: _qty(p.usedItemCount),
                            icon: Icons.inventory_2_outlined,
                          ),
                          _MiniStat(
                            width: itemWidth,
                            label: 'Ortalama İş Süresi',
                            value: p.averageJobMinutes <= 0
                                ? '-'
                                : '${p.averageJobMinutes.round()} dk',
                            icon: Icons.timer_outlined,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if ((showPanel('metrics') ||
                        showPanel('morning_preparation') ||
                        showPanel('performance')) &&
                    (showPanel('products') || showPanel('jobs')))
                  const SizedBox(height: 16),
                if (showPanel('products') || showPanel('jobs'))
                  LayoutBuilder(
                    builder: (context, c) {
                      final products = _ProductsPanel(
                        products: data.performance.productQuantities,
                      );
                      final jobs = _JobsPanel(
                        title: _filterTitle,
                        rows: _filteredRows(data),
                        onOpenJobs: () => context.go('/technician/jobs'),
                      );
                      if (showPanel('products') && !showPanel('jobs')) return products;
                      if (!showPanel('products') && showPanel('jobs')) return jobs;
                      if (c.maxWidth < 920) {
                        return Column(
                          children: [
                            products,
                            const SizedBox(height: 14),
                            jobs,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: products),
                          const SizedBox(width: 14),
                          Expanded(flex: 6, child: jobs),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String get _filterTitle => switch (_filter) {
        'progress' => 'Devam Eden İşler',
        'completed' => 'Tamamlanan İşler',
        'failed' => 'Yapılamayan / İptal / Aktarılan İşler',
        'late' => 'Geciken İşler',
        _ => 'Seçili Gün İşleri',
      };

  List<_JobRow> _filteredRows(_DashboardData data) {
    if (_filter == 'completed') {
      return data.completed.map((j) => _JobRow(job: j, completed: true)).toList();
    }
    if (_filter == 'progress') {
      return data.activeForDay
          .where((j) => j.status == 'in_progress')
          .map((j) => _JobRow(job: j))
          .toList();
    }
    if (_filter == 'failed') {
      return data.failed.map((j) => _JobRow(job: j, failed: true)).toList();
    }
    if (_filter == 'late') {
      return data.lateJobs.map((j) => _JobRow(job: j)).toList();
    }
    return [
      ...data.activeForDay.map((j) => _JobRow(job: j)),
      ...data.completed.map((j) => _JobRow(job: j, completed: true)),
      ...data.failed.map((j) => _JobRow(job: j, failed: true)),
    ];
  }

  String _money(double value) =>
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
          .format(value);

  String _qty(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
}

class _DashboardData {
  const _DashboardData({
    this.active = const <TechnicianJob>[],
    this.completed = const <TechnicianJob>[],
    this.failed = const <TechnicianJob>[],
    this.vehicleProducts = const <Map<String, dynamic>>[],
    required this.performance,
    required this.referenceDay,
  });

  final List<TechnicianJob> active;
  final List<TechnicianJob> completed;
  final List<TechnicianJob> failed;
  final List<Map<String, dynamic>> vehicleProducts;
  final TechnicianDayPerformance performance;
  final DateTime referenceDay;

  bool _sameDay(DateTime? value, DateTime day) {
    if (value == null) return false;
    final local = value.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }

  List<TechnicianJob> get activeForDay {
    final rows = active.where((j) => _sameDay(j.plannedDate, referenceDay)).toList();
    rows.sort((a, b) => (a.routeOrder ?? 9999).compareTo(b.routeOrder ?? 9999));
    return rows;
  }

  List<TechnicianJob> get tomorrowJobs {
    final tomorrow =
        DateTime(referenceDay.year, referenceDay.month, referenceDay.day + 1);
    return active.where((j) => _sameDay(j.plannedDate, tomorrow)).toList();
  }

  List<TechnicianJob> get lateJobs {
    final start = DateTime(referenceDay.year, referenceDay.month, referenceDay.day);
    return active.where((j) {
      final date = j.plannedDate?.toLocal();
      return date != null && date.isBefore(start);
    }).toList();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 125,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .11),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF102A43))),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF8A9AAF), fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5EBF2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0AAFC0)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF718096))),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MorningPreparationPanel extends StatelessWidget {
  const _MorningPreparationPanel({
    required this.jobs,
    required this.vehicleProducts,
    required this.onOpenJobs,
  });

  final List<TechnicianJob> jobs;
  final List<Map<String, dynamic>> vehicleProducts;
  final VoidCallback onOpenJobs;

  @override
  Widget build(BuildContext context) {
    final required = <String, double>{};
    for (final job in jobs) {
      final name = job.plannedProductName.trim();
      if (name.isEmpty) continue;
      final qty = job.plannedQuantity > 0 ? job.plannedQuantity : 1.0;
      required[name] = (required[name] ?? 0) + qty;
    }
    final stock = <String, double>{};
    for (final product in vehicleProducts) {
      final name = product['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      stock[name] = (product['stock_quantity'] as num?)?.toDouble() ?? 0;
    }
    final missing = <MapEntry<String, double>>[];
    for (final entry in required.entries) {
      final diff = entry.value - (stock[entry.key] ?? 0);
      if (diff > 0) missing.add(MapEntry(entry.key, diff));
    }
    String qty(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

    Widget listBox(String title, IconData icon, List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF1)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 20, color: const Color(0xFF0AAFC0)), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.w900))]),
        const SizedBox(height: 10),
        if (children.isEmpty) const Text('Kayıt yok.', style: TextStyle(color: Color(0xFF718096))) else ...children,
      ]),
    );

    return _Panel(
      title: 'Sabah Hazırlığı',
      subtitle: 'İş listesine göre malzemeni kontrol et, eksikleri tamamla ve rotaya çık.',
      trailing: FilledButton.icon(onPressed: onOpenJobs, icon: const Icon(Icons.route_outlined), label: const Text('İş Listesi / Rota')),
      child: LayoutBuilder(builder: (context, c) {
        final needRows = required.entries.map((e) {
          final have = stock[e.key] ?? 0;
          final diff = e.value - have;
          return Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [
            Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('Gerekli ${qty(e.value)}  •  Araçta ${qty(have)}', style: TextStyle(fontWeight: FontWeight.w700, color: diff > 0 ? const Color(0xFFD97706) : const Color(0xFF169B55))),
          ]));
        }).toList(growable: false);
        final stockRows = vehicleProducts
            .where((p) => ((p['stock_quantity'] as num?)?.toDouble() ?? 0) != 0)
            .take(10)
            .map((p) {
          final vehicle = (p['stock_quantity'] as num?)?.toDouble() ?? 0;
          final main = (p['main_stock'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Expanded(child: Text(p['name']?.toString() ?? '-')),
              Text(
                'Araç ${qty(vehicle)}${main > 0 ? ' • Merkez ${qty(main)}' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: vehicle < 0 ? const Color(0xFFD97706) : null,
                ),
              ),
            ]),
          );
        }).toList(growable: false);
        final alert = missing.isEmpty
          ? const Text('✓ Bugünkü planlanan ürünlere göre eksik görünmüyor.', style: TextStyle(color: Color(0xFF169B55), fontWeight: FontWeight.w800))
          : Text('Eksik: ${missing.map((e) => '${e.key} × ${qty(e.value)}').join(' • ')}', style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w900));
        final boxes = [listBox('Bugün Araçta Olması Gerekenler', Icons.inventory_2_outlined, needRows), listBox('Araçta Bulunan Malzemelerim', Icons.local_shipping_outlined, stockRows)];
        return Column(children: [
          if (c.maxWidth >= 850) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: boxes[0]), const SizedBox(width: 12), Expanded(child: boxes[1])]) else Column(children: [boxes[0], const SizedBox(height: 12), boxes[1]]),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: alert),
        ]);
      }),
    );
  }
}

class _ProductsPanel extends StatelessWidget {
  const _ProductsPanel({required this.products});
  final Map<String, double> products;

  @override
  Widget build(BuildContext context) {
    final rows = products.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = rows.isEmpty ? 1.0 : rows.first.value;
    return _Panel(
      title: 'Kullanılan Ürünler',
      subtitle: 'Seçili gün',
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Bu gün için ürün kullanımı yok.')),
            )
          : Column(
              children: rows.take(8).map((entry) {
                final ratio = (entry.value / maxValue).clamp(0.05, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(entry.key,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE8EEF5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        entry.value.toStringAsFixed(
                            entry.value % 1 == 0 ? 0 : 1),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
    );
  }
}

class _JobRow {
  const _JobRow({
    required this.job,
    this.completed = false,
    this.failed = false,
  });
  final TechnicianJob job;
  final bool completed;
  final bool failed;
}

class _JobsPanel extends StatelessWidget {
  const _JobsPanel({
    required this.title,
    required this.rows,
    required this.onOpenJobs,
  });

  final String title;
  final List<_JobRow> rows;
  final VoidCallback onOpenJobs;

  @override
  Widget build(BuildContext context) => _Panel(
        title: title,
        subtitle: '${rows.length} kayıt',
        trailing: TextButton(
          onPressed: onOpenJobs,
          child: const Text('Günlük İşlere Git'),
        ),
        child: rows.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('Bu filtrede kayıt yok.')),
              )
            : Column(
                children: rows.take(10).map((row) {
                  final job = row.job;
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEDF1F6)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          row.completed
                              ? Icons.check_circle_rounded
                              : row.failed
                                  ? (job.status == 'deferred'
                                      ? Icons.forward_to_inbox_outlined
                                      : job.status == 'cancelled'
                                          ? Icons.cancel_outlined
                                          : Icons.report_problem_outlined)
                                  : Icons.radio_button_checked_rounded,
                          color: row.completed
                              ? const Color(0xFF19A866)
                              : row.failed
                                  ? const Color(0xFFE67E22)
                                  : const Color(0xFF0AAFC0),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job.customerName.isEmpty
                                    ? 'Müşteri'
                                    : job.customerName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              Text(
                                [
                                  _serviceLabel(job.serviceType),
                                  if (job.plannedProductName.isNotEmpty)
                                    job.plannedProductName,
                                  if (row.failed)
                                    job.status == 'deferred'
                                        ? 'Sekretere Aktarıldı'
                                        : job.status == 'cancelled'
                                            ? 'İptal Edildi'
                                            : 'Tamamlanamadı',
                                ].join(' • '),
                                style: TextStyle(
                                  color: row.failed
                                      ? const Color(0xFFE67E22)
                                      : const Color(0xFF718096),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (row.completed)
                          Text(
                            NumberFormat.currency(
                                    locale: 'tr_TR',
                                    symbol: '₺',
                                    decimalDigits: 0)
                                .format(job.price),
                            style: const TextStyle(
                                color: Color(0xFF0A99A7),
                                fontWeight: FontWeight.w900),
                          ),
                      ],
                    ),
                  );
                }).toList(growable: false),
              ),
      );

  String _serviceLabel(String value) => switch (value) {
        'new_installation' => 'Yeni Kurulum',
        'filter_change' => 'Filtre Değişimi',
        'fault' => 'Arıza',
        _ => 'Servis',
      };
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: const TextStyle(
                                color: Color(0xFF8191A5), fontSize: 12)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      );
}
