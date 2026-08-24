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
  const ServicePlanningScreen({
    super.key,
    this.initialFilter,
    this.initialTechnician,
  });

  final String? initialFilter;
  final String? initialTechnician;

  @override
  ConsumerState<ServicePlanningScreen> createState() =>
      _ServicePlanningScreenState();
}

class _ServicePlanningScreenState extends ConsumerState<ServicePlanningScreen> {
  DateTime _anchor = DateTime.now();
  _CalendarMode _mode = _CalendarMode.day;
  String _quickFilter = 'period';
  String _technicianFilter = 'Tümü';
  String? _selectedTechnician;
  String _technicianSearch = '';
  bool _showAllTechnicians = false;
  bool _sendingToSecretary = false;
  late Future<List<ServiceRequestModel>> _future;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter == 'overdue') {
      _quickFilter = 'overdue';
      _mode = _CalendarMode.list;
    }
    final initialTechnician = widget.initialTechnician?.trim() ?? '';
    if (initialTechnician.isNotEmpty) {
      _technicianFilter = initialTechnician;
      _selectedTechnician = initialTechnician;
    }
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

  bool _isOverdue(ServiceRequestModel item) {
    final planned = item.plannedDate?.toLocal();
    if (planned == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final plannedDay = DateTime(planned.year, planned.month, planned.day);
    return plannedDay.isBefore(today) &&
        item.status != ServiceRequestStatus.completed &&
        item.status != ServiceRequestStatus.cancelled &&
        item.status != ServiceRequestStatus.couldNotComplete &&
        item.status != ServiceRequestStatus.deferred;
  }

  List<ServiceRequestModel> _applyQuickFilter(
    List<ServiceRequestModel> items,
  ) {
    final now = DateTime.now();
    switch (_quickFilter) {
      case 'overdue':
        return items.where(_isOverdue).toList(growable: false);
      case 'today':
      case 'today_technicians':
        return items
            .where((item) => _sameDay(item.plannedDate!.toLocal(), now))
            .toList(growable: false);
      case 'completed_today':
        return items
            .where(
              (item) =>
                  _sameDay(item.plannedDate!.toLocal(), now) &&
                  item.status == ServiceRequestStatus.completed,
            )
            .toList(growable: false);
      case 'in_progress_today':
        return items
            .where(
              (item) =>
                  _sameDay(item.plannedDate!.toLocal(), now) &&
                  item.status == ServiceRequestStatus.inProgress,
            )
            .toList(growable: false);
      default:
        return items
            .where((item) => _inCurrentPeriod(item.plannedDate!))
            .toList(growable: false);
    }
  }

  void _selectQuickFilter(String filter) {
    setState(() {
      _quickFilter = filter;
      if (filter == 'overdue') {
        _mode = _CalendarMode.list;
        _technicianFilter = 'Tümü';
        _selectedTechnician = null;
      } else if (filter != 'period') {
        _anchor = DateTime.now();
        _mode = _CalendarMode.day;
        _technicianFilter = 'Tümü';
        _selectedTechnician = null;
      }
    });
  }

  void _move(int direction) {
    setState(() {
      _quickFilter = 'period';
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

            final periodItems = _applyQuickFilter(all);

            // Takvimde yalnızca seçili gün/hafta/ay/liste döneminde gerçekten işi
            // bulunan teknisyenleri göster. Böylece 0 işi olan teknisyen kartları
            // solda ve teknisyen filtresinde gereksiz yere görünmez.
            final technicians = periodItems
                .map((e) => e.assignedTechnicianName.trim())
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            final filteredPeriodItems = _technicianFilter == 'Tümü'
                ? periodItems
                : periodItems
                    .where((e) => e.assignedTechnicianName.trim() == _technicianFilter)
                    .toList();

            if (_selectedTechnician != null &&
                !technicians.contains(_selectedTechnician)) {
              _selectedTechnician = null;
              _technicianFilter = 'Tümü';
            }

            final selectedName = _selectedTechnician ??
                (_technicianFilter != 'Tümü' ? _technicianFilter : null);

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
                      _SummaryCards(
                        items: all,
                        selectedFilter: _quickFilter,
                        onSelectFilter: _selectQuickFilter,
                      ),
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
                            } else {
                              _selectedTechnician = null;
                            }
                          });
                        },
                        onModeChanged: (value) => setState(() {
                          _quickFilter = 'period';
                          _mode = value;
                        }),
                        onPrevious: () => _move(-1),
                        onNext: () => _move(1),
                        onToday: () => setState(() {
                          _quickFilter = 'period';
                          _anchor = DateTime.now();
                        }),
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
                                  sectionTitle: _quickFilter == 'overdue'
                                      ? 'Geciken İşler'
                                      : null,
                                  items: selectedItems,
                                  mode: _mode,
                                  anchor: _anchor,
                                  onOpenRequest: (_) => context.go(
                                      '${_routePrefix(role)}/service-requests'),
                                  onOpenCustomer: (item) {
                                    if (item.customerId.trim().isNotEmpty) {
                                      context.push('${_routePrefix(role)}/customers/${item.customerId}');
                                    }
                                  },
                                  onShowCancellation: _showCancellationReason,
                                  onNewJob: () => context.go(
                                      '${_routePrefix(role)}/customers'),
                                  showSecretaryActions: (role == AppRole.admin || role == AppRole.manager) && _quickFilter == 'overdue',
                                  busy: _sendingToSecretary,
                                  onSendAll: () => _sendAllOverdueToSecretary(selectedItems),
                                  onSendItem: _sendOverdueToSecretary,
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
                          sectionTitle: _quickFilter == 'overdue'
                              ? 'Geciken İşler'
                              : null,
                          items: selectedItems,
                          mode: _mode,
                          anchor: _anchor,
                          onOpenRequest: (_) => context.go(
                              '${_routePrefix(role)}/service-requests'),
                          onOpenCustomer: (item) {
                            if (item.customerId.trim().isNotEmpty) {
                              context.push('${_routePrefix(role)}/customers/${item.customerId}');
                            }
                          },
                          onShowCancellation: _showCancellationReason,
                          onNewJob: () =>
                              context.go('${_routePrefix(role)}/customers'),
                          showSecretaryActions: (role == AppRole.admin || role == AppRole.manager) && _quickFilter == 'overdue',
                          busy: _sendingToSecretary,
                          onSendAll: () => _sendAllOverdueToSecretary(selectedItems),
                          onSendItem: _sendOverdueToSecretary,
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

  Future<void> _showCancellationReason(ServiceRequestModel item) async {
    final primaryParts = <String>[
      item.cancellationReason.trim(),
      item.technicianUnavailableReason.trim(),
      item.technicianUnavailableNote.trim(),
    ].where((e) => e.isNotEmpty).toSet().toList(growable: false);
    final fallback = <String>[
      item.completionNote.trim(),
      item.description.trim(),
    ].where((e) => e.isNotEmpty).toList(growable: false);
    final reason = primaryParts.isNotEmpty
        ? primaryParts.join('\n')
        : (fallback.isNotEmpty
            ? fallback.first
            : 'İptal / tamamlanamama nedeni kaydedilmemiş.');
    final actor = item.cancelledByName.trim();
    final cancelledAt = item.cancelledAt?.toLocal();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.status == ServiceRequestStatus.couldNotComplete
            ? 'Tamamlanamama Nedeni'
            : 'İptal Nedeni'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.customerName.trim().isEmpty ? 'Müşteri' : item.customerName.trim(),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(reason),
              if (actor.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('İptal eden: $actor', style: const TextStyle(color: Color(0xFF65758A))),
              ],
              if (cancelledAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(cancelledAt)}',
                  style: const TextStyle(color: Color(0xFF65758A)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
          FilledButton.icon(
            onPressed: item.customerId.trim().isEmpty
                ? null
                : () {
                    Navigator.pop(dialogContext);
                    context.push('${_routePrefix(ref.read(authControllerProvider).role ?? AppRole.manager)}/customers/${item.customerId}');
                  },
            icon: const Icon(Icons.person_outline_rounded),
            label: const Text('Müşteri Kartı'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendOverdueToSecretary(ServiceRequestModel item) async {
    if (_sendingToSecretary || item.id == null || !_isOverdue(item)) return;
    setState(() => _sendingToSecretary = true);
    try {
      final secretary = await ref.read(serviceRequestRepositoryProvider).sendOverdueToSecretary(
        serviceRequestId: item.id!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.customerName} • $secretary sekretere gönderildi.')),
      );
      setState(_reload);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sekretere gönderilemedi: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingToSecretary = false);
    }
  }

  Future<void> _sendAllOverdueToSecretary(List<ServiceRequestModel> items) async {
    if (_sendingToSecretary) return;
    final overdue = items.where((item) => item.id != null && _isOverdue(item)).toList(growable: false);
    if (overdue.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tüm Gecikenleri Sekretere Gönder'),
        content: Text('${overdue.length} geciken iş sekreterlere yeniden planlama için gönderilecek. Eski kayıtlar geçmişte kalacak; sekreter yeni tarih, servis türü, ürün ve fiyatı kontrol edip yönetici onayına gönderecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: const Text('Tümünü Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sendingToSecretary = true);
    var success = 0;
    var failed = 0;
    try {
      final repo = ref.read(serviceRequestRepositoryProvider);
      for (final item in overdue) {
        try {
          await repo.sendOverdueToSecretary(serviceRequestId: item.id!);
          success++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failed == 0 ? '$success geciken iş sekreterlere gönderildi.' : '$success iş gönderildi, $failed iş gönderilemedi.')),
      );
      setState(_reload);
    } finally {
      if (mounted) setState(() => _sendingToSecretary = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null && mounted) {
      setState(() {
        _quickFilter = 'period';
        _anchor = picked;
      });
    }
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
  const _SummaryCards({
    required this.items,
    required this.selectedFilter,
    required this.onSelectFilter,
  });

  final List<ServiceRequestModel> items;
  final String selectedFilter;
  final ValueChanged<String> onSelectFilter;

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
          item.status != ServiceRequestStatus.cancelled &&
          item.status != ServiceRequestStatus.couldNotComplete &&
          item.status != ServiceRequestStatus.deferred;
    }).length;

    final cards = [
      _MetricData(
        'Bugünkü Servisler',
        '${todayItems.length}',
        'Tüm teknisyenler',
        Icons.calendar_today_outlined,
        const Color(0xFF2F80ED),
        'today',
      ),
      _MetricData(
        'Tamamlanan',
        '${count(ServiceRequestStatus.completed)}',
        'Bugün',
        Icons.check_circle_outline_rounded,
        const Color(0xFF20A66A),
        'completed_today',
      ),
      _MetricData(
        'Devam Eden',
        '${count(ServiceRequestStatus.inProgress)}',
        'Şu anda',
        Icons.schedule_rounded,
        const Color(0xFFF59E0B),
        'in_progress_today',
      ),
      _MetricData(
        'Teknisyen',
        '$technicians',
        'Bugün görevli',
        Icons.person_outline_rounded,
        const Color(0xFF7C3AED),
        'today_technicians',
      ),
      _MetricData(
        'Geciken',
        '$delayed',
        'Plan tarihi geçen',
        Icons.warning_amber_rounded,
        const Color(0xFFE34D59),
        'overdue',
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
          itemBuilder: (context, index) => _MetricCard(
            data: cards[index],
            selected: selectedFilter == cards[index].filter,
            onTap: () => onSelectFilter(cards[index].filter),
          ),
        );
      },
    );
  }
}

class _MetricData {
  const _MetricData(
    this.label,
    this.value,
    this.detail,
    this.icon,
    this.color,
    this.filter,
  );
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final String filter;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _MetricData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? data.color.withOpacity(.045) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? data.color : const Color(0xFFE1E8EF),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B102235),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ],
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
              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Color(0xFF9AA7B5),
              ),
            ],
          ),
        ),
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
    this.sectionTitle,
    required this.items,
    required this.mode,
    required this.anchor,
    required this.onOpenRequest,
    required this.onOpenCustomer,
    required this.onShowCancellation,
    required this.onNewJob,
    required this.showSecretaryActions,
    required this.busy,
    required this.onSendAll,
    required this.onSendItem,
  });

  final String? technicianName;
  final String? sectionTitle;
  final List<ServiceRequestModel> items;
  final _CalendarMode mode;
  final DateTime anchor;
  final ValueChanged<ServiceRequestModel> onOpenRequest;
  final ValueChanged<ServiceRequestModel> onOpenCustomer;
  final ValueChanged<ServiceRequestModel> onShowCancellation;
  final VoidCallback onNewJob;
  final bool showSecretaryActions;
  final bool busy;
  final VoidCallback onSendAll;
  final ValueChanged<ServiceRequestModel> onSendItem;

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
                    sectionTitle == null
                        ? (technicianName ?? 'Tüm İşler')
                        : technicianName == null
                            ? '$sectionTitle • Tüm Teknikerler'
                            : '$sectionTitle • $technicianName',
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
                if (showSecretaryActions && items.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: busy ? null : onSendAll,
                    icon: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.forward_to_inbox_outlined, size: 18),
                    label: const Text('Tümünü Sekretere Gönder'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE14B4B), foregroundColor: Colors.white),
                  ),
                ],
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
                Expanded(flex: 22, child: Text('Müşteri', style: _headerStyle)),
                Expanded(flex: 28, child: Text('Adres', style: _headerStyle)),
                Expanded(flex: 20, child: Text('Tekniker', style: _headerStyle)),
                Expanded(flex: 17, child: Text('Durum', style: _headerStyle)),
                Expanded(flex: 13, child: Text('Fiyat', style: _headerStyle)),
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
                      onOpenRequest: () => onOpenRequest(items[index]),
                      onOpenCustomer: () => onOpenCustomer(items[index]),
                      onShowCancellation: () => onShowCancellation(items[index]),
                      showSecretaryAction: showSecretaryActions,
                      busy: busy,
                      onSendSecretary: () => onSendItem(items[index]),
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
  const _ScheduleRow({
    required this.item,
    required this.onOpenRequest,
    required this.onOpenCustomer,
    required this.onShowCancellation,
    required this.showSecretaryAction,
    required this.busy,
    required this.onSendSecretary,
  });

  final ServiceRequestModel item;
  final VoidCallback onOpenRequest;
  final VoidCallback onOpenCustomer;
  final VoidCallback onShowCancellation;
  final bool showSecretaryAction;
  final bool busy;
  final VoidCallback onSendSecretary;

  bool get _isCancelled =>
      item.status == ServiceRequestStatus.cancelled ||
      item.status == ServiceRequestStatus.couldNotComplete;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    final address = [
      item.customerAddress.trim(),
      [item.customerDistrict.trim(), item.customerCity.trim()]
          .where((e) => e.isNotEmpty)
          .join(' / '),
    ].where((e) => e.isNotEmpty).join('\n');

    // Satırın tamamını tıklanabilir yapmıyoruz. Böylece özellikle iptal
    // durumuna tıklarken kullanıcı yanlışlıkla Bölgeler & Rota gibi başka bir
    // ekrana gitmez. Müşteri adı, durum rozeti ve üç nokta ayrı işlevlere sahip.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 22,
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Tooltip(
                    message: 'Müşteri kartını aç',
                    child: InkWell(
                      onTap: item.customerId.trim().isEmpty ? null : onOpenCustomer,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          item.customerName.trim().isEmpty
                              ? 'Müşteri'
                              : item.customerName.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF17263A),
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 28,
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
            flex: 20,
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 15,
                  color: Color(0xFF60758B),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    item.assignedTechnicianName.trim().isEmpty
                        ? 'Atanmadı'
                        : item.assignedTechnicianName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.assignedTechnicianName.trim().isEmpty
                          ? const Color(0xFFE34D59)
                          : const Color(0xFF405269),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 17,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: _isCancelled ? 'İptal nedenini göster' : _statusLabel(item.status),
                child: InkWell(
                  onTap: _isCancelled ? onShowCancellation : null,
                  borderRadius: BorderRadius.circular(16),
                  child: _StatusPill(status: item.status),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 13,
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
              enabled: !busy,
              onSelected: (value) {
                if (value == 'send_secretary') {
                  onSendSecretary();
                } else if (value == 'customer') {
                  onOpenCustomer();
                } else if (value == 'cancel_reason') {
                  onShowCancellation();
                } else {
                  onOpenRequest();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'open',
                  child: Text('Servis talebini aç'),
                ),
                if (item.customerId.trim().isNotEmpty)
                  const PopupMenuItem(
                    value: 'customer',
                    child: Text('Müşteri kartını aç'),
                  ),
                if (_isCancelled)
                  const PopupMenuItem(
                    value: 'cancel_reason',
                    child: Text('İptal nedenini göster'),
                  ),
                if (showSecretaryAction)
                  const PopupMenuItem(
                    value: 'send_secretary',
                    child: Row(
                      children: [
                        Icon(Icons.forward_to_inbox_outlined, size: 18, color: Color(0xFFE14B4B)),
                        SizedBox(width: 8),
                        Text('Sekretere Gönder'),
                      ],
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
