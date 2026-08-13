import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../../service_requests/data/models/service_request_model.dart';
import '../../service_requests/presentation/providers/service_request_providers.dart';

enum _CalendarMode { day, week, month, list }

class ServicePlanningScreen extends ConsumerStatefulWidget {
  const ServicePlanningScreen({super.key});

  @override
  ConsumerState<ServicePlanningScreen> createState() =>
      _ServicePlanningScreenState();
}

class _ServicePlanningScreenState extends ConsumerState<ServicePlanningScreen> {
  DateTime _anchor = DateTime.now();
  _CalendarMode _mode = _CalendarMode.week;
  String _technician = 'Tümü';
  late Future<List<ServiceRequestModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(serviceRequestRepositoryProvider).getServiceRequests();
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _weekStart(DateTime value) {
    final day = _dateOnly(value);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  void _move(int direction) {
    setState(() {
      if (_mode == _CalendarMode.day) {
        _anchor = _anchor.add(Duration(days: direction));
      } else if (_mode == _CalendarMode.month) {
        _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
      } else {
        _anchor = _anchor.add(Duration(days: 7 * direction));
      }
    });
  }

  String _routePrefix(AppRole role) =>
      role == AppRole.secretary ? '/secretary' : '/manager';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final role = auth.role ?? AppRole.manager;
    final desktop = MediaQuery.sizeOf(context).width >= 1050;

    final body = Container(
      color: const Color(0xFFF4F7FA),
      child: FutureBuilder<List<ServiceRequestModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: 'Takvim yüklenemedi: ${snapshot.error}',
              onRetry: () => setState(_reload),
            );
          }

          final all = (snapshot.data ?? const <ServiceRequestModel>[])
              .where((item) => item.plannedDate != null &&
                  item.status != ServiceRequestStatus.pending &&
                  item.status != ServiceRequestStatus.deferred &&
                  item.status != ServiceRequestStatus.cancelled &&
                  item.status != ServiceRequestStatus.couldNotComplete)
              .toList()
            ..sort((a, b) => a.plannedDate!.compareTo(b.plannedDate!));
          final technicians = all
              .map((item) => item.assignedTechnicianName.trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final filtered = _technician == 'Tümü'
              ? all
              : all
                  .where((item) =>
                      item.assignedTechnicianName.trim() == _technician)
                  .toList();

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                  child: Column(
                    children: [
                      _SummaryCards(items: all),
                      const SizedBox(height: 16),
                      _CalendarToolbar(
                        anchor: _anchor,
                        mode: _mode,
                        technician: _technician,
                        technicians: technicians,
                        onTechnicianChanged: (value) {
                          setState(() => _technician = value ?? 'Tümü');
                        },
                        onModeChanged: (value) => setState(() => _mode = value),
                        onPrevious: () => _move(-1),
                        onNext: () => _move(1),
                        onToday: () => setState(() => _anchor = DateTime.now()),
                        onPickDate: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _anchor,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            locale: const Locale('tr', 'TR'),
                          );
                          if (picked != null) setState(() => _anchor = picked);
                        },
                      ),
                      const SizedBox(height: 12),
                      _Legend(),
                      const SizedBox(height: 12),
                      if (!desktop || _mode == _CalendarMode.list)
                        _ListCalendar(
                          items: filtered,
                          anchor: _anchor,
                          mode: _mode,
                          onOpen: () => context.go('${_routePrefix(role)}/service-requests'),
                        )
                      else if (_mode == _CalendarMode.day)
                        _DayCalendar(
                          items: filtered,
                          day: _dateOnly(_anchor),
                          onOpen: () => context.go('${_routePrefix(role)}/service-requests'),
                        )
                      else if (_mode == _CalendarMode.month)
                        _MonthCalendar(
                          items: filtered,
                          month: _anchor,
                          onSelectDay: (date) => setState(() {
                            _anchor = date;
                            _mode = _CalendarMode.day;
                          }),
                        )
                      else
                        _WeekCalendar(
                          items: filtered,
                          weekStart: _weekStart(_anchor),
                          onOpen: () => context.go('${_routePrefix(role)}/service-requests'),
                        ),
                      const SizedBox(height: 16),
                      _TechnicianStrip(items: all),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return ManagementShell(
      role: role,
      title: 'Takvim',
      subtitle: 'Teknikerlerin günlük, haftalık ve aylık iş programını görüntüleyin.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('${_routePrefix(role)}/customers'),
          icon: const Icon(Icons.add),
          label: const Text('Yeni Servis Talebi'),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: body,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.role,
    required this.onNewRequest,
    required this.onRefresh,
  });

  final AppRole role;
  final VoidCallback onNewRequest;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3EAF0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined,
              size: 28, color: Color(0xFF0EA7B5)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Takvim',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF102033))),
                SizedBox(height: 3),
                Text('Teknisyenlerin günlük ve haftalık iş programını görüntüleyin.',
                    style: TextStyle(color: Color(0xFF718096), fontSize: 13)),
              ],
            ),
          ),
          if (role != AppRole.technician)
            FilledButton.icon(
              onPressed: onNewRequest,
              icon: const Icon(Icons.add),
              label: const Text('Yeni Servis Talebi'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF08A9B7),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
            ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.items});

  final List<ServiceRequestModel> items;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayItems = items.where((item) {
      final date = item.plannedDate!.toLocal();
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).toList();
    int count(ServiceRequestStatus status) =>
        todayItems.where((item) => item.status == status).length;
    final technicians = todayItems
        .map((e) => e.assignedTechnicianName.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;
    final todayOnly = DateTime(today.year, today.month, today.day);
    final delayed = items.where((item) {
      final planned = item.plannedDate!.toLocal();
      final plannedOnly = DateTime(planned.year, planned.month, planned.day);
      return plannedOnly.isBefore(todayOnly) &&
          item.status != ServiceRequestStatus.completed &&
          item.status != ServiceRequestStatus.cancelled;
    }).length;

    final cards = [
      _MetricData('Bugünkü Servisler', '${todayItems.length}', 'Tüm teknisyenler',
          Icons.calendar_today_outlined, const Color(0xFF2F80ED)),
      _MetricData('Tamamlanan', '${count(ServiceRequestStatus.completed)}', 'Bugün',
          Icons.check_circle_outline, const Color(0xFF20A66A)),
      _MetricData('Devam Eden', '${count(ServiceRequestStatus.inProgress)}',
          'Şu anda işlemde', Icons.timelapse, const Color(0xFFF59E0B)),
      _MetricData('Teknisyen', '$technicians', 'Bugün görevli',
          Icons.person_outline, const Color(0xFF7C3AED)),
      _MetricData('Geciken', '$delayed', 'Plan tarihi geçen',
          Icons.warning_amber_rounded, const Color(0xFFE34D59)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth > 1150 ? 5 : constraints.maxWidth > 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.25,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) => _MetricCard(data: cards[index]),
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.detail, this.icon, this.color);
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF0)),
        boxShadow: const [BoxShadow(color: Color(0x0C0B2438), blurRadius: 16, offset: Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: data.color.withOpacity(.11),
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, color: data.color, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF526175), fontSize: 12, fontWeight: FontWeight.w600)),
                Text(data.value,
                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
                Text(data.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8491A3), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.anchor,
    required this.mode,
    required this.technician,
    required this.technicians,
    required this.onTechnicianChanged,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onPickDate,
  });

  final DateTime anchor;
  final _CalendarMode mode;
  final String technician;
  final List<String> technicians;
  final ValueChanged<String?> onTechnicianChanged;
  final ValueChanged<_CalendarMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final start = anchor.subtract(Duration(days: anchor.weekday - 1));
    final end = start.add(const Duration(days: 6));
    final range = mode == _CalendarMode.month
        ? DateFormat('MMMM yyyy', 'tr_TR').format(anchor)
        : mode == _CalendarMode.day
            ? DateFormat('dd MMMM yyyy', 'tr_TR').format(anchor)
            : '${DateFormat('dd MMM', 'tr_TR').format(start)} - ${DateFormat('dd MMM yyyy', 'tr_TR').format(end)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: technician,
              decoration: _inputDecoration('Teknisyen', Icons.people_outline),
              items: ['Tümü', ...technicians]
                  .map((name) => DropdownMenuItem(value: name, child: Text(name == 'Tümü' ? 'Tüm Teknisyenler' : name)))
                  .toList(),
              onChanged: onTechnicianChanged,
            ),
          ),
          SegmentedButton<_CalendarMode>(
            segments: const [
              ButtonSegment(value: _CalendarMode.day, label: Text('Gün')),
              ButtonSegment(value: _CalendarMode.week, label: Text('Hafta')),
              ButtonSegment(value: _CalendarMode.month, label: Text('Ay')),
              ButtonSegment(value: _CalendarMode.list, label: Text('Liste')),
            ],
            selected: {mode},
            onSelectionChanged: (set) => onModeChanged(set.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton(onPressed: onToday, child: const Text('Bugün')),
          IconButton.outlined(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
          InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              constraints: const BoxConstraints(minWidth: 190),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFD8E2EA)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.calendar_month_outlined, size: 19, color: Color(0xFF0B91A0)),
                const SizedBox(width: 9),
                Text(range, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF344257))),
              ]),
            ),
          ),
          IconButton.outlined(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFD8E2EA))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFFD8E2EA))),
  );
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _LegendChip('Planlandı', Color(0xFF2F80ED)),
          _LegendChip('Devam Ediyor', Color(0xFF7C3AED)),
          _LegendChip('Tamamlandı', Color(0xFF20A66A)),
          _LegendChip('İptal', Color(0xFFE34D59)),
          _LegendChip('Atama Bekliyor', Color(0xFFF59E0B)),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE3EAF0))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF536174))),
      ]),
    );
  }
}

class _WeekCalendar extends StatelessWidget {
  const _WeekCalendar({required this.items, required this.weekStart, required this.onOpen});
  final List<ServiceRequestModel> items;
  final DateTime weekStart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (index) => weekStart.add(Duration(days: index)));
    final today = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth < 1120 ? 1120 : constraints.maxWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: days.map((day) {
                  final selected = day.year == today.year &&
                      day.month == today.month &&
                      day.day == today.day;
                  final dayItems = items.where((item) {
                    final value = item.plannedDate!.toLocal();
                    return value.year == day.year &&
                        value.month == day.month &&
                        value.day == day.day;
                  }).toList();

                  return Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 360),
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Color(0xFFE5EBF0))),
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 66,
                            width: double.infinity,
                            alignment: Alignment.center,
                            color: selected ? const Color(0xFFEAF9FA) : Colors.white,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  DateFormat('EEE', 'tr_TR').format(day),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: selected ? const Color(0xFF0798A7) : const Color(0xFF344257),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  DateFormat('dd MMMM', 'tr_TR').format(day),
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF7E8A9A)),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: dayItems.isEmpty
                                ? Container(
                                    height: 84,
                                    alignment: Alignment.center,
                                    child: const Text(
                                      'Servis yok',
                                      style: TextStyle(fontSize: 11, color: Color(0xFFA0AAB7)),
                                    ),
                                  )
                                : Column(
                                    children: dayItems
                                        .map((item) => Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: _CalendarEventCard(
                                                item: item,
                                                onTap: onOpen,
                                                compact: true,
                                              ),
                                            ))
                                        .toList(),
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
        },
      ),
    );
  }
}

class _DayCalendar extends StatelessWidget {
  const _DayCalendar({required this.items, required this.day, required this.onOpen});
  final List<ServiceRequestModel> items;
  final DateTime day;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dayItems = items.where((item) {
      final date = item.plannedDate!.toLocal();
      return date.year == day.year && date.month == day.month && date.day == day.day;
    }).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3EAF0))),
      child: dayItems.isEmpty
          ? const _EmptyCalendar(message: 'Bu tarih için planlanmış servis bulunmuyor.')
          : Column(
              children: dayItems.map((item) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _CalendarEventCard(item: item, onTap: onOpen))).toList(),
            ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({required this.items, required this.month, required this.onSelectDay});
  final List<ServiceRequestModel> items;
  final DateTime month;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final gridStart = first.subtract(Duration(days: offset));
    final days = List.generate(42, (index) => gridStart.add(Duration(days: index)));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3EAF0))),
      child: Column(
        children: [
          Row(children: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'].map((name) => Expanded(child: Padding(padding: const EdgeInsets.all(9), child: Center(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF536174))))))).toList()),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.25),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final dayItems = items.where((item) {
                final date = item.plannedDate!.toLocal();
                return date.year == day.year && date.month == day.month && date.day == day.day;
              }).toList();
              final activeMonth = day.month == month.month;
              return InkWell(
                onTap: () => onSelectDay(day),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: activeMonth ? const Color(0xFFFBFCFD) : const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFE5EBF0)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${day.day}', style: TextStyle(fontWeight: FontWeight.w800, color: activeMonth ? const Color(0xFF263449) : const Color(0xFFA8B0BC))),
                    const SizedBox(height: 5),
                    ...dayItems.take(3).map((item) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(item.status).withOpacity(.12), borderRadius: BorderRadius.circular(5)),
                      child: Text(item.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _statusColor(item.status))),
                    )),
                    if (dayItems.length > 3) Text('+${dayItems.length - 3} daha', style: const TextStyle(fontSize: 9, color: Color(0xFF758195))),
                  ]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ListCalendar extends StatelessWidget {
  const _ListCalendar({required this.items, required this.anchor, required this.mode, required this.onOpen});
  final List<ServiceRequestModel> items;
  final DateTime anchor;
  final _CalendarMode mode;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final start = mode == _CalendarMode.month
        ? DateTime(anchor.year, anchor.month, 1)
        : anchor.subtract(Duration(days: anchor.weekday - 1));
    final end = mode == _CalendarMode.month
        ? DateTime(anchor.year, anchor.month + 1, 1)
        : start.add(const Duration(days: 7));
    final visible = items.where((item) {
      final date = item.plannedDate!.toLocal();
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3EAF0))),
      child: visible.isEmpty
          ? const _EmptyCalendar(message: 'Seçilen dönemde planlanmış servis bulunmuyor.')
          : Column(children: visible.map((item) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _CalendarEventCard(item: item, onTap: onOpen))).toList()),
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({required this.item, required this.onTap, this.compact = false});
  final ServiceRequestModel item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return Material(
      color: color.withOpacity(.10),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 63 : 72),
          padding: EdgeInsets.all(compact ? 7 : 11),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: color.withOpacity(.26))),
          child: compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.customerName.isEmpty ? 'Müşteri' : item.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
                  const SizedBox(height: 3),
                  Text(item.serviceType.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF46556A))),
                  Text(item.customerAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: Color(0xFF657287))),
                  const SizedBox(height: 3),
                  Text(item.assignedTechnicianName.isEmpty ? 'Atama bekliyor' : item.assignedTechnicianName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFF657287))),
                ])
              : Row(children: [
                  Container(width: 4, height: 46, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.customerName.isEmpty ? 'Müşteri' : item.customerName, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF243248))),
                    Text('${item.serviceType.label} • ${item.customerAddress}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF657287))),
                  ])),
                  const SizedBox(width: 10),
                  Text(item.assignedTechnicianName.isEmpty ? 'Atama bekliyor' : item.assignedTechnicianName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF46556A))),
                  const SizedBox(width: 14),
                  _StatusBadge(status: item.status),
                  const SizedBox(width: 7),
                  const Icon(Icons.chevron_right, color: Color(0xFF8290A2)),
                ]),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

Color _statusColor(ServiceRequestStatus status) {
  switch (status) {
    case ServiceRequestStatus.pending:
      return const Color(0xFFF59E0B);
    case ServiceRequestStatus.approved:
      return const Color(0xFF0891B2);
    case ServiceRequestStatus.deferred:
      return const Color(0xFF64748B);
    case ServiceRequestStatus.assigned:
      return const Color(0xFF2F80ED);
    case ServiceRequestStatus.inProgress:
      return const Color(0xFF7C3AED);
    case ServiceRequestStatus.completed:
      return const Color(0xFF20A66A);
    case ServiceRequestStatus.cancelled:
    case ServiceRequestStatus.couldNotComplete:
      return const Color(0xFFE34D59);
  }
}

class _TechnicianStrip extends StatelessWidget {
  const _TechnicianStrip({required this.items});
  final List<ServiceRequestModel> items;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<ServiceRequestModel>>{};
    for (final item in items) {
      final name = item.assignedTechnicianName.trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => []).add(item);
    }
    if (grouped.isEmpty) return const SizedBox.shrink();
    final entries = grouped.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3EAF0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Teknisyenler', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF243248))),
        const SizedBox(height: 11),
        SizedBox(
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final complete = entry.value.where((e) => e.status == ServiceRequestStatus.completed).length;
              final ongoing = entry.value.where((e) => e.status == ServiceRequestStatus.inProgress).length;
              return Container(
                width: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFAFCFD), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE3EAF0))),
                child: Row(children: [
                  CircleAvatar(backgroundColor: const Color(0xFFE5F8F9), child: Text(_initials(entry.key), style: const TextStyle(color: Color(0xFF0798A7), fontWeight: FontWeight.w900))),
                  const SizedBox(width: 11),
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF243248))),
                    const SizedBox(height: 6),
                    Text('${entry.value.length} servis • $ongoing işlemde', style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
                    Text('$complete tamamlandı', style: const TextStyle(fontSize: 11, color: Color(0xFF20A66A), fontWeight: FontWeight.w700)),
                  ])),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _EmptyCalendar extends StatelessWidget {
  const _EmptyCalendar({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 55),
      child: Column(children: [
        const Icon(Icons.event_busy_outlined, size: 48, color: Color(0xFFB2BEC9)),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(color: Color(0xFF718096))),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 50, color: Color(0xFFE34D59)),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tekrar Dene')),
      ]),
    );
  }
}

class _CalendarSidebar extends StatelessWidget {
  const _CalendarSidebar({required this.role, required this.displayName});
  final AppRole role;
  final String displayName;

  String get prefix => role == AppRole.secretary ? '/secretary' : '/manager';
  String get dashboard => role == AppRole.secretary ? '/secretary-dashboard' : '/admin-dashboard';

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, String route, {bool selected = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Material(
          color: selected ? const Color(0xFF0D5368) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            leading: Icon(icon, color: selected ? const Color(0xFF16D0DB) : const Color(0xFFC5D2DD), size: 21),
            title: Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFFD7E1E9), fontWeight: FontWeight.w600)),
            onTap: () => context.go(route),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF071C2D),
      child: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 16, 24),
            child: Row(children: [
              Icon(Icons.water_drop_rounded, color: Color(0xFF13C7D3), size: 40),
              SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ARN', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                Text('SU ARITMA', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.4)),
              ]),
            ]),
          ),
          item(Icons.dashboard_outlined, role == AppRole.secretary ? 'Ana Sayfa' : 'Dashboard', dashboard),
          if (role == AppRole.secretary) ...[
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.people_alt_outlined, color: Color(0xFFC5D2DD), size: 21),
                title: const Text('Müşteriler', style: TextStyle(color: Color(0xFFD7E1E9), fontWeight: FontWeight.w700)),
                iconColor: const Color(0xFF16D0DB),
                collapsedIconColor: const Color(0xFF8DA0B2),
                children: [
                  item(Icons.groups_2_outlined, 'Müşteri Listesi', '$prefix/customers'),
                  item(Icons.person_add_alt_1_outlined, 'Yeni Müşteri', '$prefix/customers/new'),
                  item(Icons.history_rounded, 'Geçmiş Müşteri Kaydı', '$prefix/customers/historical'),
                ],
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.work_outline, color: Color(0xFF16D0DB), size: 21),
                title: const Text('Servis Talepleri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                iconColor: const Color(0xFF16D0DB),
                collapsedIconColor: const Color(0xFF8DA0B2),
                children: [
                  item(Icons.assignment_outlined, 'Servis Talepleri', '$prefix/service-requests'),
                  item(Icons.calendar_month_outlined, 'Takvim', '$prefix/service-planning', selected: true),
                ],
              ),
            ),
            item(Icons.notifications_active_outlined, 'Bakımı Yaklaşanlar', '$prefix/maintenance'),
            item(Icons.notifications_none_rounded, 'Bildirimler', '/notifications'),
          ] else ...[
            item(Icons.people_alt_outlined, 'Müşteriler', '$prefix/customers'),
            item(Icons.work_outline, 'Servis Talepleri', '$prefix/service-requests'),
            item(Icons.calendar_month_outlined, 'Takvim', '$prefix/service-planning', selected: true),
          ],
          if (role != AppRole.secretary) ...[
            item(Icons.inventory_2_outlined, 'Ürünler', '$prefix/products'),
            item(Icons.payments_outlined, 'Tahsilatlar', '/manager/payments'),
            item(Icons.assessment_outlined, 'Raporlar', '/manager/reports'),
            item(Icons.badge_outlined, 'Personeller', '/manager/users'),
            item(Icons.settings_outlined, 'Ayarlar', '/manager/settings'),
          ],
          const Spacer(),
          const Divider(color: Color(0xFF17364A)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFF18C7D1), child: Icon(Icons.person_outline, color: Colors.white)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                Text(role.label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
            ]),
          ),
        ]),
      ),
    );
  }
}
