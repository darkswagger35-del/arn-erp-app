import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../finance/data/finance_providers.dart';
import '../../operations/data/operations_providers.dart';

enum _DashboardPeriod { day, week, month }

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  late Future<_DashboardBundle> _future;
  DateTime _selectedDate = DateTime.now();
  _DashboardPeriod _period = _DashboardPeriod.day;
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _liveTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  DateTime get _rangeStart {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    switch (_period) {
      case _DashboardPeriod.day:
        return d;
      case _DashboardPeriod.week:
        return d.subtract(Duration(days: d.weekday - DateTime.monday));
      case _DashboardPeriod.month:
        return DateTime(d.year, d.month, 1);
    }
  }

  DateTime get _rangeEnd {
    final start = _rangeStart;
    switch (_period) {
      case _DashboardPeriod.day:
        return start.add(const Duration(days: 1));
      case _DashboardPeriod.week:
        return start.add(const Duration(days: 7));
      case _DashboardPeriod.month:
        return DateTime(start.year, start.month + 1, 1);
    }
  }

  Future<_DashboardBundle> _load() async {
    final start = _rangeStart;
    final end = _rangeEnd;

    final results = await Future.wait<dynamic>([
      _safeWorkspace(),
      _safeDetails(start, end),
      _safePayments(start, end),
      _safeServiceRows(start, end, dateField: 'planned_date'),
      _safeServiceRows(start, end, dateField: 'created_at'),
    ]);

    return _DashboardBundle(
      workspace: results[0] as Map<String, dynamic>,
      details: results[1] as List<Map<String, dynamic>>,
      payments: results[2] as List<Map<String, dynamic>>,
      plannedServices: results[3] as List<Map<String, dynamic>>,
      createdServices: results[4] as List<Map<String, dynamic>>,
      rangeStart: start,
      rangeEnd: end,
    );
  }

  Future<Map<String, dynamic>> _safeWorkspace() async {
    try {
      return await ref
          .read(operationsRepositoryProvider)
          .dashboardWorkspace(selectedDate: _selectedDate)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<List<Map<String, dynamic>>> _safeDetails(
    DateTime start,
    DateTime end,
  ) async {
    try {
      return await ref
          .read(financeRepositoryProvider)
          .reportDetails(start: start, end: end)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _safePayments(
    DateTime start,
    DateTime end,
  ) async {
    try {
      return await ref
          .read(financeRepositoryProvider)
          .payments(start: start, end: end)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _safeServiceRows(
    DateTime start,
    DateTime end, {
    required String dateField,
  }) async {
    try {
      final client = ref.read(operationsRepositoryProvider).client;
      final raw = List<Map<String, dynamic>>.from(
        await client
            .from('service_requests')
            .select(
              'id, assigned_technician_id, created_by, service_type, status, '
              'price, planned_date, created_at',
            )
            .gte(dateField, start.toUtc().toIso8601String())
            .lt(dateField, end.toUtc().toIso8601String())
            .order(dateField, ascending: true)
            .limit(1000),
      );

      final profileIds = <String>{};
      for (final row in raw) {
        final technician = row['assigned_technician_id']?.toString() ?? '';
        final creator = row['created_by']?.toString() ?? '';
        if (technician.isNotEmpty) profileIds.add(technician);
        if (creator.isNotEmpty) profileIds.add(creator);
      }

      final profiles = <String, Map<String, dynamic>>{};
      if (profileIds.isNotEmpty) {
        final profileRows = List<Map<String, dynamic>>.from(
          await client
              .from('profiles')
              .select('id, full_name, role')
              .inFilter('id', profileIds.toList()),
        );
        for (final profile in profileRows) {
          profiles[profile['id'].toString()] = profile;
        }
      }

      return raw.map((row) {
        final technicianId = row['assigned_technician_id']?.toString() ?? '';
        final creatorId = row['created_by']?.toString() ?? '';
        final technician = profiles[technicianId] ?? const <String, dynamic>{};
        final creator = profiles[creatorId] ?? const <String, dynamic>{};
        return <String, dynamic>{
          ...row,
          'technician_name': technician['full_name']?.toString() ?? '',
          'creator_name': creator['full_name']?.toString() ?? '',
          'creator_role': creator['role']?.toString() ?? '',
        };
      }).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  void _setDate(DateTime date, {_DashboardPeriod? period}) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      if (period != null) _period = period;
      _future = _load();
    });
  }

  void _movePeriod(int direction) {
    final next = switch (_period) {
      _DashboardPeriod.day =>
        _selectedDate.add(Duration(days: direction)),
      _DashboardPeriod.week =>
        _selectedDate.add(Duration(days: 7 * direction)),
      _DashboardPeriod.month =>
        DateTime(_selectedDate.year, _selectedDate.month + direction, 1),
    };
    _setDate(next);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      _setDate(picked, period: _DashboardPeriod.day);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.admin,
      title: 'Ana Panel',
      subtitle: 'Canlı operasyon ve finans özeti',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Önceki dönem',
          onPressed: () => _movePeriod(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_rounded, size: 17),
          label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
        ),
        IconButton.filledTonal(
          tooltip: 'Sonraki dönem',
          onPressed: () => _movePeriod(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        _PeriodButton(
          label: 'Bugün',
          selected: _period == _DashboardPeriod.day && _isToday(_selectedDate),
          onTap: () => _setDate(DateTime.now(), period: _DashboardPeriod.day),
        ),
        _PeriodButton(
          label: 'Dün',
          selected: _period == _DashboardPeriod.day &&
              _isSameDay(
                _selectedDate,
                DateTime.now().subtract(const Duration(days: 1)),
              ),
          onTap: () => _setDate(
            DateTime.now().subtract(const Duration(days: 1)),
            period: _DashboardPeriod.day,
          ),
        ),
        _PeriodButton(
          label: 'Bu Hafta',
          selected: _period == _DashboardPeriod.week,
          onTap: () => _setDate(DateTime.now(), period: _DashboardPeriod.week),
        ),
        _PeriodButton(
          label: 'Bu Ay',
          selected: _period == _DashboardPeriod.month,
          onTap: () => _setDate(DateTime.now(), period: _DashboardPeriod.month),
        ),
        IconButton(
          tooltip: 'Tarih seç',
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_month_outlined),
        ),
      ],
      child: FutureBuilder<_DashboardBundle>(
        future: _future,
        builder: (context, snapshot) {
          final bundle = snapshot.data ?? _DashboardBundle.empty(
            rangeStart: _rangeStart,
            rangeEnd: _rangeEnd,
          );
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
              children: [
                _SummaryCards(
                  bundle: bundle,
                  loading: snapshot.connectionState == ConnectionState.waiting,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final technician = _StaffPerformancePanel(
                      title: 'Bugünkü Tekniker Performansı',
                      staff: bundle.technicianPerformance,
                      staffLabel: 'Tekniker',
                      countLabel: 'Toplam İş',
                      onOpenAll: () => context.go('/manager/reports'),
                      onOpenRow: (_) => context.go('/manager/service-planning'),
                    );
                    final secretary = _StaffPerformancePanel(
                      title: 'Bugünkü Sekreter Performansı',
                      staff: bundle.secretaryPerformance,
                      staffLabel: 'Sekreter',
                      countLabel: 'Alınan İş',
                      onOpenAll: () => context.go('/manager/reports'),
                      onOpenRow: (_) => context.go('/manager/reports'),
                    );
                    final program = _DailyProgramPanel(
                      rows: bundle.technicianPerformance,
                    );

                    if (constraints.maxWidth >= 1120) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: technician),
                          const SizedBox(width: 12),
                          Expanded(child: secretary),
                          const SizedBox(width: 12),
                          Expanded(child: program),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        technician,
                        const SizedBox(height: 12),
                        secretary,
                        const SizedBox(height: 12),
                        program,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final payments = _PaymentsPanel(rows: bundle.payments);
                    final quick = const _QuickAccessPanel();
                    if (constraints.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: payments),
                          const SizedBox(width: 12),
                          Expanded(flex: 6, child: quick),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        payments,
                        const SizedBox(height: 12),
                        quick,
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

  bool _isToday(DateTime value) => _isSameDay(value, DateTime.now());

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: selected
          ? FilledButton.tonal(onPressed: onTap, child: Text(label))
          : TextButton(onPressed: onTap, child: Text(label)),
    );
  }
}

class _DashboardBundle {
  const _DashboardBundle({
    required this.workspace,
    required this.details,
    required this.payments,
    required this.plannedServices,
    required this.createdServices,
    required this.rangeStart,
    required this.rangeEnd,
  });

  factory _DashboardBundle.empty({
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    return _DashboardBundle(
      workspace: const <String, dynamic>{},
      details: const <Map<String, dynamic>>[],
      payments: const <Map<String, dynamic>>[],
      plannedServices: const <Map<String, dynamic>>[],
      createdServices: const <Map<String, dynamic>>[],
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  final Map<String, dynamic> workspace;
  final List<Map<String, dynamic>> details;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> plannedServices;
  final List<Map<String, dynamic>> createdServices;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  int get activeCustomers => _int(workspace['active_customers']);
  int get activeServices => _int(workspace['assigned']) + _int(workspace['pending']);

  int get jobCount => plannedServices.where((row) {
        final status = row['status']?.toString() ?? '';
        return !_isCancelled(status);
      }).length;

  double get revenue => details.fold<double>(
        0,
        (sum, row) => sum + _double(row['amount']),
      );

  double get collection => payments.fold<double>(
        0,
        (sum, row) => sum + _double(row['amount']),
      );

  List<_StaffRow> get technicianPerformance {
    final grouped = <String, _MutableStaff>{};
    for (final service in plannedServices) {
      final status = service['status']?.toString() ?? '';
      if (_isCancelled(status)) continue;
      final name = service['technician_name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final item = grouped.putIfAbsent(name, () => _MutableStaff(name));
      item.total += 1;
      if (status == 'completed') {
        item.completed += 1;
      } else {
        item.pending += 1;
      }
    }
    for (final row in details) {
      final name = row['technician_name']?.toString().trim() ?? '';
      if (name.isEmpty || name.toLowerCase().contains('belirtilmedi')) continue;
      final item = grouped.putIfAbsent(name, () => _MutableStaff(name));
      item.turnover += _double(row['amount']);
    }
    final result = grouped.values.map((item) => item.freeze()).toList();
    result.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : b.turnover.compareTo(a.turnover);
    });
    return result;
  }

  List<_StaffRow> get secretaryPerformance {
    final grouped = <String, _MutableStaff>{};
    for (final service in createdServices) {
      if (service['creator_role']?.toString() != 'secretary') continue;
      final name = service['creator_name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final item = grouped.putIfAbsent(name, () => _MutableStaff(name));
      item.total += 1;
      if (service['status']?.toString() == 'completed') {
        item.completed += 1;
      } else {
        item.pending += 1;
      }
    }
    for (final row in details) {
      final name = row['secretary_name']?.toString().trim() ?? '';
      if (name.isEmpty || name.toLowerCase().contains('belirtilmedi')) continue;
      final item = grouped.putIfAbsent(name, () => _MutableStaff(name));
      item.turnover += _double(row['amount']);
    }
    final result = grouped.values.map((item) => item.freeze()).toList();
    result.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      return byTotal != 0 ? byTotal : b.turnover.compareTo(a.turnover);
    });
    return result;
  }

  static bool _isCancelled(String status) =>
      status == 'cancelled' ||
      status == 'canceled' ||
      status == 'could_not_complete' ||
      status == 'deferred';

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _MutableStaff {
  _MutableStaff(this.name);

  final String name;
  int total = 0;
  int completed = 0;
  int pending = 0;
  double turnover = 0;

  _StaffRow freeze() => _StaffRow(
        name: name,
        total: total,
        completed: completed,
        pending: pending,
        turnover: turnover,
      );
}

class _StaffRow {
  const _StaffRow({
    required this.name,
    required this.total,
    required this.completed,
    required this.pending,
    required this.turnover,
  });

  final String name;
  final int total;
  final int completed;
  final int pending;
  final double turnover;
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.bundle, required this.loading});

  final _DashboardBundle bundle;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final cards = <_SummaryData>[
      _SummaryData(
        title: 'Toplam Müşteri',
        value: loading ? '…' : NumberFormat.decimalPattern('tr_TR').format(bundle.activeCustomers),
        subtitle: 'Sistemdeki toplam aktif müşteri',
        link: 'Tüm Müşteriler',
        icon: Icons.groups_2_outlined,
        color: const Color(0xFF2879F5),
        onTap: () => context.go('/manager/customers'),
      ),
      _SummaryData(
        title: 'Aktif Servis',
        value: loading ? '…' : '${bundle.activeServices}',
        subtitle: 'Devam eden servis talebi',
        link: 'Aktif Servisler',
        icon: Icons.business_center_outlined,
        color: const Color(0xFF7559E8),
        onTap: () => context.go('/manager/service-requests'),
      ),
      _SummaryData(
        title: 'Bugünkü İş',
        value: loading ? '…' : '${bundle.jobCount}',
        subtitle: 'Teknikerlerin seçili dönemdeki işi',
        link: 'Günlük İş Programı',
        icon: Icons.event_available_outlined,
        color: const Color(0xFF37B766),
        onTap: () => context.go('/manager/service-planning'),
      ),
      _SummaryData(
        title: 'Bugünkü Ciro',
        value: loading ? '…' : money.format(bundle.revenue),
        subtitle: 'Seçili dönemde oluşan ciro',
        link: 'Ciro Raporu',
        icon: Icons.currency_lira_rounded,
        color: const Color(0xFFF19A39),
        onTap: () => context.go('/manager/reports'),
      ),
      _SummaryData(
        title: 'Bugünkü Tahsilat',
        value: loading ? '…' : money.format(bundle.collection),
        subtitle: 'Tahsil edilen toplam tutar',
        link: 'Tahsilat Raporu',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF15B8BE),
        onTap: () => context.go('/manager/payments'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 1120
            ? 5
            : constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 500
                    ? 2
                    : 1;
        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: count == 1 ? 2.5 : 1.65,
          ),
          itemBuilder: (context, index) => _SummaryCard(data: cards[index]),
        );
      },
    );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.link,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final String link;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE1E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: .11),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(data.icon, color: data.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            color: Color(0xFF586A7E),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.value,
                            style: const TextStyle(
                              color: Color(0xFF071D34),
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF718197),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: data.onTap,
                  label: Text(data.link),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffPerformancePanel extends StatelessWidget {
  const _StaffPerformancePanel({
    required this.title,
    required this.staff,
    required this.staffLabel,
    required this.countLabel,
    required this.onOpenAll,
    required this.onOpenRow,
  });

  final String title;
  final List<_StaffRow> staff;
  final String staffLabel;
  final String countLabel;
  final VoidCallback onOpenAll;
  final ValueChanged<_StaffRow> onOpenRow;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final visible = staff.take(4).toList(growable: false);
    final total = visible.fold<int>(0, (sum, row) => sum + row.total);
    final completed = visible.fold<int>(0, (sum, row) => sum + row.completed);
    final pending = visible.fold<int>(0, (sum, row) => sum + row.pending);
    final turnover = visible.fold<double>(0, (sum, row) => sum + row.turnover);

    return _WhitePanel(
      title: title,
      action: TextButton.icon(
        onPressed: onOpenAll,
        label: const Text('Tümünü Gör'),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      ),
      child: Column(
        children: [
          _PerformanceHeader(
            first: staffLabel,
            second: countLabel,
            showTurnover: true,
          ),
          const Divider(height: 1),
          if (visible.isEmpty)
            const _EmptyPanelText('Bu dönemde personel hareketi bulunmuyor.')
          else
            for (final row in visible)
              _PerformanceRow(
                row: row,
                money: money,
                onTap: () => onOpenRow(row),
              ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Expanded(
                  flex: 4,
                  child: Text('Toplam', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Expanded(child: Text('$total', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
                Expanded(child: Text('$completed', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF12A35A), fontWeight: FontWeight.w900))),
                Expanded(child: Text('$pending', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF18722), fontWeight: FontWeight.w900))),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(money.format(turnover), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextButton.icon(
              onPressed: onOpenAll,
              label: Text('$staffLabel Performans Raporu'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceHeader extends StatelessWidget {
  const _PerformanceHeader({
    required this.first,
    required this.second,
    required this.showTurnover,
  });

  final String first;
  final String second;
  final bool showTurnover;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xFF68798C),
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(first, style: style)),
          Expanded(child: Text(second, textAlign: TextAlign.center, style: style)),
          const Expanded(child: Text('Tamamlanan', textAlign: TextAlign.center, style: style)),
          const Expanded(child: Text('Bekleyen', textAlign: TextAlign.center, style: style)),
          if (showTurnover)
            const Expanded(flex: 2, child: Text('Ciro', textAlign: TextAlign.right, style: style)),
          const SizedBox(width: 22),
        ],
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.row,
    required this.money,
    required this.onTap,
  });

  final _StaffRow row;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: _avatarColor(row.name).withValues(alpha: .14),
                    child: Text(
                      _initials(row.name),
                      style: TextStyle(
                        color: _avatarColor(row.name),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: Text('${row.total}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(child: Text('${row.completed}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF12A35A), fontWeight: FontWeight.w800))),
            Expanded(child: Text('${row.pending}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF18722), fontWeight: FontWeight.w800))),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(money.format(row.turnover), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF8392A5)),
          ],
        ),
      ),
    );
  }
}

class _DailyProgramPanel extends StatelessWidget {
  const _DailyProgramPanel({required this.rows});

  final List<_StaffRow> rows;

  @override
  Widget build(BuildContext context) {
    final visible = rows.take(4).toList(growable: false);
    final total = visible.fold<int>(0, (sum, row) => sum + row.total);
    final completed = visible.fold<int>(0, (sum, row) => sum + row.completed);
    final pending = visible.fold<int>(0, (sum, row) => sum + row.pending);

    return _WhitePanel(
      title: 'Bugünkü İş Programı',
      action: TextButton.icon(
        onPressed: () => context.go('/manager/service-planning'),
        label: const Text('Tümünü Gör'),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('Tekniker', style: _headerStyle)),
                Expanded(child: Text('Toplam İş', textAlign: TextAlign.center, style: _headerStyle)),
                Expanded(child: Text('Tamamlanan', textAlign: TextAlign.center, style: _headerStyle)),
                Expanded(child: Text('Bekleyen', textAlign: TextAlign.center, style: _headerStyle)),
                SizedBox(width: 22),
              ],
            ),
          ),
          const Divider(height: 1),
          if (visible.isEmpty)
            const _EmptyPanelText('Bu dönemde tekniker işi bulunmuyor.')
          else
            for (final row in visible)
              InkWell(
                onTap: () => context.go('/manager/service-planning'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: _avatarColor(row.name).withValues(alpha: .14),
                              child: Text(
                                _initials(row.name),
                                style: TextStyle(color: _avatarColor(row.name), fontWeight: FontWeight.w900, fontSize: 10),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                          ],
                        ),
                      ),
                      Expanded(child: Text('${row.total}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Expanded(child: Text('${row.completed}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF12A35A), fontWeight: FontWeight.w800))),
                      Expanded(child: Text('${row.pending}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF18722), fontWeight: FontWeight.w800))),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF8392A5)),
                    ],
                  ),
                ),
              ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Expanded(flex: 4, child: Text('Toplam', style: TextStyle(fontWeight: FontWeight.w900))),
                Expanded(child: Text('$total', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
                Expanded(child: Text('$completed', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF12A35A), fontWeight: FontWeight.w900))),
                Expanded(child: Text('$pending', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF18722), fontWeight: FontWeight.w900))),
                const SizedBox(width: 22),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextButton.icon(
              onPressed: () => context.go('/manager/service-planning'),
              label: const Text('Günlük İş Programı'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: Color(0xFF68798C),
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );
}

class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final visible = rows.take(5).toList(growable: false);
    final total = rows.fold<double>(0, (sum, row) => sum + _asDouble(row['amount']));

    return _WhitePanel(
      title: 'Bugünkü Tahsilatlar',
      action: TextButton.icon(
        onPressed: () => context.go('/manager/payments'),
        label: const Text('Tümünü Gör'),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Müşteri', style: _paymentHeaderStyle)),
                Expanded(flex: 3, child: Text('İşlem', style: _paymentHeaderStyle)),
                Expanded(flex: 2, child: Text('Tutar', textAlign: TextAlign.right, style: _paymentHeaderStyle)),
                Expanded(flex: 2, child: Text('Sekreter', textAlign: TextAlign.center, style: _paymentHeaderStyle)),
                SizedBox(width: 48, child: Text('Saat', textAlign: TextAlign.right, style: _paymentHeaderStyle)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (visible.isEmpty)
            const _EmptyPanelText('Bu dönemde tahsilat bulunmuyor.')
          else
            for (final row in visible) _PaymentRow(row: row, money: money),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Expanded(child: Text('Toplam Tahsilat', style: TextStyle(fontWeight: FontWeight.w900))),
                Text(money.format(total), style: const TextStyle(color: Color(0xFF12A35A), fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextButton.icon(
              onPressed: () => context.go('/manager/payments'),
              label: const Text('Tahsilat Raporu'),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  static const _paymentHeaderStyle = TextStyle(
    color: Color(0xFF68798C),
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.row, required this.money});

  final Map<String, dynamic> row;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final customer = row['customers'];
    String customerName = 'Müşteri';
    if (customer is Map) {
      final full = customer['full_name']?.toString().trim() ?? '';
      final company = customer['company_name']?.toString().trim() ?? '';
      customerName = full.isNotEmpty ? full : (company.isNotEmpty ? company : customerName);
    }
    final service = row['_service'];
    var action = row['description']?.toString().trim() ?? '';
    var secretary = '-';
    if (service is Map) {
      final serviceType = service['service_type']?.toString().trim() ?? '';
      if (serviceType.isNotEmpty) action = serviceType;
      final secretaryName = service['secretary_name']?.toString().trim() ?? '';
      if (secretaryName.isNotEmpty) secretary = secretaryName;
    }
    if (action.isEmpty) action = 'Tahsilat';
    final date = DateTime.tryParse(row['payment_date']?.toString() ?? '')?.toLocal();

    return InkWell(
      onTap: () => context.go('/manager/payments'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
            ),
            Expanded(
              flex: 3,
              child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(money.format(_asDouble(row['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(secretary, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ),
            SizedBox(
              width: 48,
              child: Text(date == null ? '-' : DateFormat('HH:mm').format(date), textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF718197), fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessPanel extends StatelessWidget {
  const _QuickAccessPanel();

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction('Müşteriler', 'Müşteri listesine git', Icons.groups_2_outlined, const Color(0xFF2879F5), '/manager/customers'),
      _QuickAction('Yeni Servis Talebi', 'Servis talebi oluştur', Icons.add_box_outlined, const Color(0xFF7559E8), '/manager/customers'),
      _QuickAction('Servis Talepleri', 'Tüm servis talepleri', Icons.event_note_outlined, const Color(0xFFF19A39), '/manager/service-requests'),
      _QuickAction('Teknikerler', 'Tekniker listesi', Icons.engineering_outlined, const Color(0xFF2879F5), '/manager/users'),
      _QuickAction('Stok & Ürünler', 'Ürün ve stok yönetimi', Icons.inventory_2_outlined, const Color(0xFF37B766), '/manager/products'),
      _QuickAction('Tahsilatlar', 'Tahsilat işlemleri', Icons.account_balance_wallet_outlined, const Color(0xFF15B8BE), '/manager/payments'),
      _QuickAction('Raporlar', 'Tüm raporlar', Icons.bar_chart_rounded, const Color(0xFF7559E8), '/manager/reports'),
      _QuickAction('Ayarlar', 'Sistem ayarları', Icons.settings_outlined, const Color(0xFF637083), '/manager/settings'),
      _QuickAction('Bildirimler', 'Sistem bildirimleri', Icons.notifications_none_rounded, const Color(0xFFE55757), '/notifications'),
    ];

    return _WhitePanel(
      title: 'Hızlı Erişim',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth >= 660 ? 3 : constraints.maxWidth >= 420 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: count == 1 ? 4 : 2.6,
              ),
              itemBuilder: (context, index) {
                final action = actions[index];
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => context.go(action.route),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE3E9F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: action.color.withValues(alpha: .10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(action.icon, color: action.color, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(action.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                                const SizedBox(height: 2),
                                Text(action.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF718197), fontSize: 9.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.title, this.subtitle, this.icon, this.color, this.route);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}

class _WhitePanel extends StatelessWidget {
  const _WhitePanel({required this.title, this.action, required this.child});

  final String title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF071D34),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _EmptyPanelText extends StatelessWidget {
  const _EmptyPanelText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF718197), fontSize: 12),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

Color _avatarColor(String value) {
  const colors = <Color>[
    Color(0xFF7559E8),
    Color(0xFF2879F5),
    Color(0xFF2E9D6B),
    Color(0xFFE18A2D),
    Color(0xFF15A8B8),
  ];
  final index = value.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % colors.length;
  return colors[index];
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
