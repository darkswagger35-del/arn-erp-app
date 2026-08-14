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
  _CalendarMode _mode = _CalendarMode.day;
  String _technicianFilter = 'Tümü';
  String? _selectedTechnician;
  String _technicianSearch = '';
  bool _showAllTechnicians = false;
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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inCurrentPeriod(DateTime value) {
    final local = value.toLocal();
    switch (_mode) {
      case _CalendarMode.day:
        return _sameDay(local, _anchor);
      case _CalendarMode.week:
        final start = _weekStart(_anchor);
        final end = start.add(const Duration(days: 7));
        return !local.isBefore(start) && local.isBefore(end);
      case _CalendarMode.month:
        return local.year == _anchor.year && local.month == _anchor.month;
      case _CalendarMode.list:
        return true;
    }
  }

  void _move(int direction) {
    setState(() {
      switch (_mode) {
        case _CalendarMode.day:
          _anchor = _anchor.add(Duration(days: direction));
          break;
        case _CalendarMode.week:
          _anchor = _anchor.add(Duration(days: 7 * direction));
          break;
        case _CalendarMode.month:
          _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
          break;
        case _CalendarMode.list:
          _anchor = _anchor.add(Duration(days: direction));
          break;
      }
    });
  }

  String _routePrefix(AppRole role) =>
      role == AppRole.secretary ? '/secretary' : '/manager';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final role = auth.role ?? AppRole.manager;

    return ManagementShell(
      role: role,
      title: 'Takvim',
      subtitle: 'Teknikerlerin günlük, haftalık ve aylık iş programını görüntüleyin.',
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('${_routePrefix(role)}/customers'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Yeni Servis Talebi'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF08A9B7),
            foregroundColor: Colors.white,
          ),
        ),
        IconButton.outlined(
          tooltip: 'Yenile',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh_rounded),
        ),
        OutlinedButton.icon(
          onPressed: _showHelp,
          icon: const Icon(Icons.help_outline_rounded),
          label: const Text('Yardım'),
        ),
      ],
      child: ColoredBox(
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
                .where((item) => item.plannedDate != null)
                .toList()
              ..sort((a, b) => a.plannedDate!.compareTo(b.plannedDate!));

            final technicians = all
                .map((e) => e.assignedTechnicianName.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            final periodItems = all.where((e) => _inCurrentPeriod(e.plannedDate!)).toList();
            final filteredPeriodItems = _technicianFilter == 'Tümü'
                ? periodItems
                : periodItems
                    .where((e) => e.assignedTechnicianName.trim() == _technicianFilter)
                    .toList();

            if (_selectedTechnician != null &&
                !technicians.contains(_selectedTechnician)) {
              _selectedTechnician = null;
            }

            final selectedName = _selectedTechnician ??
                (_technicianFilter != 'Tümü'
                    ? _technicianFilter
                    : (technicians.isNotEmpty ? technicians.first : null));

            final selectedItems = selectedName == null
                ? filteredPeriodItems
                : filteredPeriodItems
                    .where((e) => e.assignedTechnicianName.trim() == selectedName)
                    .toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 1080;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    constraints.maxWidth < 760 ? 12 : 22,
                    18,
                    constraints.maxWidth < 760 ? 12 : 22,
                    28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryCards(items: all),
                      const SizedBox(height: 16),
                      _CalendarToolbar(
                        anchor: _anchor,
                        mode: _mode,
                        technician: _technicianFilter,
                        technicians: technicians,
                        onTechnicianChanged: (value) {
                          setState(() {
                            _technicianFilter = value ?? 'Tümü';
                            if (_technicianFilter != 'Tümü') {
                              _selectedTechnician = _technicianFilter;
                            }
                          });
                        },
                        onModeChanged: (value) => setState(() => _mode = value),
                        onPrevious: () => _move(-1),
                        onNext: () => _move(1),
                        onToday: () => setState(() => _anchor = DateTime.now()),
                        onPickDate: _pickDate,
                        onFilter: () => _showFilterInfo(context),
                      ),
                      const SizedBox(height: 10),
                      const _Legend(),
                      const SizedBox(height: 12),
                      if (horizontal)
                        SizedBox(
                          height: 535,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 330,
                                child: _TechnicianPanel(
                                  technicians: technicians,
                                  items: periodItems,
                                  selected: selectedName,
                                  search: _technicianSearch,
                                  showAll: _showAllTechnicians,
                                  onSearchChanged: (value) =>
                                      setState(() => _technicianSearch = value),
                                  onSelect: (name) => setState(() {
                                    _selectedTechnician = name;
                                    _technicianFilter = name;
                                  }),
                                  onToggleAll: () => setState(() =>
                                      _showAllTechnicians = !_showAllTechnicians),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _SchedulePanel(
                                  technicianName: selectedName,
                                  items: selectedItems,
                                  mode: _mode,
                                  anchor: _anchor,
                                  onOpenRequests: () => context.go(
                                      '${_routePrefix(role)}/service-requests'),
                                  onNewJob: () => context.go(
                                      '${_routePrefix(role)}/customers'),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _TechnicianPanel(
                          technicians: technicians,
                          items: periodItems,
                          selected: selectedName,
                          search: _technicianSearch,
                          showAll: _showAllTechnicians,
                          onSearchChanged: (value) =>
                              setState(() => _technicianSearch = value),
                          onSelect: (name) => setState(() {
                            _selectedTechnician = name;
                            _technicianFilter = name;
                          }),
                          onToggleAll: () => setState(() =>
                              _showAllTechnicians = !_showAllTechnicians),
                        ),
                        const SizedBox(height: 14),
                        _SchedulePanel(
                          technicianName: selectedName,
                          items: selectedItems,
                          mode: _mode,
                          anchor: _anchor,
                          onOpenRequests: () => context.go(
                              '${_routePrefix(role)}/service-requests'),
                          onNewJob: () =>
                              context.go('${_routePrefix(role)}/customers'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null && mounted) setState(() => _anchor = picked);
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Takvim Kullanımı'),
        content: const Text(
          'Teknisyeni soldan seçebilir, Gün / Hafta / Ay / Liste görünümünü değiştirebilir ve tarih seçerek o dönemin işlerini görüntüleyebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  void _showFilterInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teknisyen, görünüm ve tarih seçimleri anında uygulanır.'),
        duration: Duration(seconds: 2),
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
    final todayOnly = DateTime(today.year, today.month, today.day);
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

    final delayed = items.where((item) {
      final planned = item.plannedDate!.toLocal();
      final plannedOnly = DateTime(planned.year, planned.month, planned.day);
      return plannedOnly.isBefore(todayOnly) &&
          item.status != ServiceRequestStatus.completed &&
          item.status != ServiceRequestStatus.cancelled;
    }).length;

    final cards = [
      _MetricData(
        'Bugünkü Servisler',
        '${todayItems.length}',
        'Tüm teknisyenler',
        Icons.calendar_today_outlined,
        const Color(0xFF2F80ED),
      ),
      _MetricData(
        'Tamamlanan',
        '${count(ServiceRequestStatus.completed)}',
        'Bugün',
        Icons.check_circle_outline_rounded,
        const Color(0xFF20A66A),
      ),
      _MetricData(
        'Devam Eden',
        '${count(ServiceRequestStatus.inProgress)}',
        'Şu anda',
        Icons.schedule_rounded,
        const Color(0xFFF59E0B),
      ),
      _MetricData(
        'Teknisyen',
        '$technicians',
        'Bugün görevli',
        Icons.person_outline_rounded,
        const Color(0xFF7C3AED),
      ),
      _MetricData(
        'Geciken',
        '$delayed',
        'Plan tarihi geçen',
        Icons.warning_amber_rounded,
        const Color(0xFFE34D59),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 5
            : constraints.maxWidth >= 760
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 5 ? 2.3 : 2.15,
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
      decoration: _panelDecoration(),
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
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF526175),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF102033),
                  ),
                ),
                Text(
                  data.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8491A3),
                    fontSize: 11,
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
    required this.onFilter,
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
  final VoidCallback onFilter;

  String get _dateLabel {
    if (mode == _CalendarMode.week) {
      final start = anchor.subtract(Duration(days: anchor.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return '${DateFormat('dd MMM', 'tr_TR').format(start)} - ${DateFormat('dd MMM yyyy', 'tr_TR').format(end)}';
    }
    if (mode == _CalendarMode.month) {
      return DateFormat('MMMM yyyy', 'tr_TR').format(anchor);
    }
    return DateFormat('dd MMMM yyyy', 'tr_TR').format(anchor);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: _panelDecoration(shadow: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final technicianField = SizedBox(
            width: compact ? double.infinity : 245,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('Teknisyen'),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: technician,
                  isExpanded: true,
                  decoration: _controlDecoration(Icons.people_outline_rounded),
                  items: ['Tümü', ...technicians]
                      .map(
                        (name) => DropdownMenuItem(
                          value: name,
                          child: Text(
                            name == 'Tümü' ? 'Tüm Teknisyenler' : name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onTechnicianChanged,
                ),
              ],
            ),
          );

          final viewControl = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Görünüm'),
              const SizedBox(height: 5),
              SegmentedButton<_CalendarMode>(
                segments: const [
                  ButtonSegment(value: _CalendarMode.day, label: Text('Gün')),
                  ButtonSegment(value: _CalendarMode.week, label: Text('Hafta')),
                  ButtonSegment(value: _CalendarMode.month, label: Text('Ay')),
                  ButtonSegment(value: _CalendarMode.list, label: Text('Liste')),
                ],
                selected: {mode},
                onSelectionChanged: (set) => onModeChanged(set.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          );

          final dateControl = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('Tarih'),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onPickDate,
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 205),
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFD8E2EA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 19,
                            color: Color(0xFF23334A),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              _dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF344257),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 5),
                  IconButton.outlined(
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onToday,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF08A9B7),
                      side: const BorderSide(color: Color(0xFF08A9B7)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                    child: const Text('Bugün'),
                  ),
                ],
              ),
            ],
          );

          final trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onFilter,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Filtrele'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onFilter,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          );

          if (compact) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(width: 245, child: technicianField),
                viewControl,
                dateControl,
                trailing,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              technicianField,
              const SizedBox(width: 22),
              viewControl,
              const SizedBox(width: 28),
              Expanded(child: dateControl),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF526175),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

InputDecoration _controlDecoration(IconData icon) {
  return InputDecoration(
    prefixIcon: Icon(icon, size: 19),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFD8E2EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFD8E2EA)),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 14,
        runSpacing: 7,
        children: [
          _LegendDot('Planlandı', Color(0xFF2F80ED)),
          _LegendDot('Devam Ediyor', Color(0xFF7C3AED)),
          _LegendDot('Tamamlandı', Color(0xFF20A66A)),
          _LegendDot('İptal', Color(0xFFE53935)),
          _LegendDot('Atama Bekliyor', Color(0xFFF59E0B)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF536174)),
        ),
      ],
    );
  }
}

class _TechnicianPanel extends StatelessWidget {
  const _TechnicianPanel({
    required this.technicians,
    required this.items,
    required this.selected,
    required this.search,
    required this.showAll,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onToggleAll,
  });

  final List<String> technicians;
  final List<ServiceRequestModel> items;
  final String? selected;
  final String search;
  final bool showAll;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final filtered = technicians.where((name) {
      final q = search.trim().toLowerCase();
      return q.isEmpty || name.toLowerCase().contains(q);
    }).toList();
    final visible = showAll ? filtered : filtered.take(4).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Teknisyenler',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF16263A),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Teknisyen ara...',
              suffixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFDDE5EC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFDDE5EC)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Teknisyen bulunamadı.',
                  style: TextStyle(color: Color(0xFF8A97A8)),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final name = visible[index];
                  final techItems = items
                      .where((e) => e.assignedTechnicianName.trim() == name)
                      .toList();
                  return _TechnicianCard(
                    name: name,
                    items: techItems,
                    selected: selected == name,
                    onTap: () => onSelect(name),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (filtered.length > 4)
            OutlinedButton.icon(
              onPressed: onToggleAll,
              icon: Icon(
                showAll
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(showAll ? 'Daralt' : 'Tümünü Genişlet'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF08A9B7),
                side: const BorderSide(color: Color(0xFF08A9B7)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({
    required this.name,
    required this.items,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final List<ServiceRequestModel> items;
  final bool selected;
  final VoidCallback onTap;

  int _count(ServiceRequestStatus status) =>
      items.where((e) => e.status == status).length;

  @override
  Widget build(BuildContext context) {
    final assigned = _count(ServiceRequestStatus.assigned);
    final inProgress = _count(ServiceRequestStatus.inProgress);
    final completed = _count(ServiceRequestStatus.completed);
    final cancelled = _count(ServiceRequestStatus.cancelled) +
        _count(ServiceRequestStatus.couldNotComplete);
    final awaiting = _count(ServiceRequestStatus.approved) +
        _count(ServiceRequestStatus.pending);

    return Material(
      color: selected ? const Color(0xFFF1FBFC) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF08A9B7)
                  : const Color(0xFFE1E8EF),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xFF13B7C3),
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2D42),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${items.length} iş',
                      style: const TextStyle(
                        color: Color(0xFF2F80ED),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  _MiniCount(assigned, const Color(0xFF2F80ED)),
                  _MiniCount(inProgress, const Color(0xFF7C3AED)),
                  _MiniCount(completed, const Color(0xFF20A66A)),
                  _MiniCount(cancelled, const Color(0xFFE53935)),
                  _MiniCount(awaiting, const Color(0xFFF59E0B)),
                  const Spacer(),
                  Text(
                    'Toplam ${items.length} iş',
                    style: const TextStyle(
                      color: Color(0xFF657287),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount(this.value, this.color);
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({
    required this.technicianName,
    required this.items,
    required this.mode,
    required this.anchor,
    required this.onOpenRequests,
    required this.onNewJob,
  });

  final String? technicianName;
  final List<ServiceRequestModel> items;
  final _CalendarMode mode;
  final DateTime anchor;
  final VoidCallback onOpenRequests;
  final VoidCallback onNewJob;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panelDecoration(shadow: false),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF13B7C3),
                  child: Text(
                    technicianName == null ? '—' : _initials(technicianName!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    technicianName ?? 'Tüm İşler',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF17263A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${items.length} iş',
                    style: const TextStyle(
                      color: Color(0xFF2F80ED),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _printHint(context),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Takvimi Yazdır'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5EBF0)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 25, child: Text('Müşteri', style: _headerStyle)),
                Expanded(flex: 36, child: Text('Adres', style: _headerStyle)),
                Expanded(flex: 19, child: Text('Durum', style: _headerStyle)),
                Expanded(flex: 14, child: Text('Fiyat', style: _headerStyle)),
                SizedBox(width: 30),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5EBF0)),
          Expanded(
            child: items.isEmpty
                ? _EmptySchedule(mode: mode, anchor: anchor)
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0xFFE9EEF3)),
                    itemBuilder: (context, index) => _ScheduleRow(
                      item: items[index],
                      onTap: onOpenRequests,
                    ),
                  ),
          ),
          InkWell(
            onTap: onNewJob,
            child: Container(
              height: 52,
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: const Color(0xFFD6E4EA),
                  style: BorderStyle.solid,
                ),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: Color(0xFF08A9B7)),
                  SizedBox(width: 7),
                  Text(
                    'Yeni iş ekle',
                    style: TextStyle(
                      color: Color(0xFF08A9B7),
                      fontWeight: FontWeight.w800,
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

  static const _headerStyle = TextStyle(
    color: Color(0xFF4E5D71),
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );

  void _printHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Takvim yazdırma görünümü hazırlanıyor.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.item, required this.onTap});
  final ServiceRequestModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    final address = [
      item.customerAddress.trim(),
      [item.customerDistrict.trim(), item.customerCity.trim()]
          .where((e) => e.isNotEmpty)
          .join(' / '),
    ].where((e) => e.isNotEmpty).join('\n');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 25,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.customerName.trim().isEmpty
                          ? 'Müşteri'
                          : item.customerName.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF17263A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 36,
              child: Text(
                address.isEmpty ? 'Adres bilgisi yok' : address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF4C5C71),
                  height: 1.4,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              flex: 19,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(status: item.status),
              ),
            ),
            Expanded(
              flex: 14,
              child: Text(
                _money(item.price),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF29384D),
                ),
              ),
            ),
            SizedBox(
              width: 30,
              child: PopupMenuButton<String>(
                tooltip: 'İşlemler',
                onSelected: (_) => onTap(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'open', child: Text('Servis talebini aç')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _statusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule({required this.mode, required this.anchor});
  final _CalendarMode mode;
  final DateTime anchor;

  @override
  Widget build(BuildContext context) {
    final label = mode == _CalendarMode.day
        ? DateFormat('dd MMMM yyyy', 'tr_TR').format(anchor)
        : 'seçilen dönem';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_available_outlined,
            size: 40,
            color: Color(0xFFB2BCC8),
          ),
          const SizedBox(height: 9),
          Text(
            '$label için planlanmış servis yok.',
            style: const TextStyle(color: Color(0xFF7D899A)),
          ),
        ],
      ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
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
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration({bool shadow = true}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFE1E8EF)),
    boxShadow: shadow
        ? const [
            BoxShadow(
              color: Color(0x0B102235),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ]
        : const [],
  );
}

Color _statusColor(ServiceRequestStatus status) {
  switch (status) {
    case ServiceRequestStatus.assigned:
      return const Color(0xFF2F80ED);
    case ServiceRequestStatus.inProgress:
      return const Color(0xFF7C3AED);
    case ServiceRequestStatus.completed:
      return const Color(0xFF20A66A);
    case ServiceRequestStatus.cancelled:
    case ServiceRequestStatus.couldNotComplete:
      return const Color(0xFFE53935);
    case ServiceRequestStatus.pending:
    case ServiceRequestStatus.approved:
      return const Color(0xFFF59E0B);
    case ServiceRequestStatus.deferred:
      return const Color(0xFF64748B);
  }
}

String _statusLabel(ServiceRequestStatus status) {
  switch (status) {
    case ServiceRequestStatus.assigned:
      return 'Planlandı';
    case ServiceRequestStatus.inProgress:
      return 'Devam Ediyor';
    case ServiceRequestStatus.completed:
      return 'Tamamlandı';
    case ServiceRequestStatus.cancelled:
    case ServiceRequestStatus.couldNotComplete:
      return 'İptal';
    case ServiceRequestStatus.pending:
    case ServiceRequestStatus.approved:
      return 'Atama Bekliyor';
    case ServiceRequestStatus.deferred:
      return 'Tehir';
  }
}

String _money(double value) {
  if (value <= 0) return '—';
  final formatted = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  ).format(value);
  return formatted;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
