import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../operations/data/operations_providers.dart';
import '../../settings/data/company_app_settings.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> _future;
  Timer? _liveTimer;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
    _liveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return ref.read(operationsRepositoryProvider).dashboardWorkspace(selectedDate: _selectedDate);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(companyAppSettingsProvider).asData?.value ??
        const CompanyAppSettings(companyId: '');

    return ManagementShell(
      role: AppRole.admin,
      title: 'Ana Panel',
      subtitle: 'Canlı operasyon ve finans özeti • Her dakika yenilenir',
      dark: true,
      actions: [
        IconButton.filledTonal(tooltip: 'Önceki gün', onPressed: () { setState(() { _selectedDate = _selectedDate.subtract(const Duration(days: 1)); _future = _load(); }); }, icon: const Icon(Icons.chevron_left)),
        OutlinedButton.icon(
          onPressed: () async { final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2035)); if (d != null && mounted) setState(() { _selectedDate = d; _future = _load(); }); },
          icon: const Icon(Icons.calendar_today_rounded, size: 17),
          label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
        ),
        IconButton.filledTonal(tooltip: 'Sonraki gün', onPressed: () { setState(() { _selectedDate = _selectedDate.add(const Duration(days: 1)); _future = _load(); }); }, icon: const Icon(Icons.chevron_right)),
        TextButton(onPressed: () { setState(() { _selectedDate = DateTime.now(); _future = _load(); }); }, child: const Text('Bugün')),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Yenile',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Stack(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, dynamic>{};
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 92),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (appSettings.panelVisible('admin', 'summary')) ...[
                            _SummaryGrid(data: data, loading: !snapshot.hasData),
                            const SizedBox(height: 16),
                          ],
                          if (_maps(data['could_not_complete_today']).isNotEmpty) ...[
                            _CouldNotCompletePanel(
                              rows: _maps(data['could_not_complete_today']),
                              onOpenAll: () => context.go('/manager/service-requests/pending'),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (appSettings.panelVisible('admin', 'recent_services')) ...[
                            _RecentServices(
                              rows: _maps(data['recent_services']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final panels = <Widget>[
                                if (appSettings.panelVisible('admin', 'today_schedule'))
                                  _TodaySchedule(rows: _maps(data['today_jobs'])),
                                if (appSettings.panelVisible('admin', 'recent_payments'))
                                  _RecentPayments(rows: _maps(data['recent_payments'])),
                                if (appSettings.panelVisible(
                                  'admin',
                                  'announcements',
                                  fallback: false,
                                ))
                                  const _Announcements(),
                              ];
                              if (panels.isEmpty) return const SizedBox.shrink();
                              if (constraints.maxWidth < 980 || panels.length == 1) {
                                return Column(
                                  children: [
                                    for (var i = 0; i < panels.length; i++) ...[
                                      panels[i],
                                      if (i != panels.length - 1)
                                        const SizedBox(height: 16),
                                    ],
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < panels.length; i++) ...[
                                    Expanded(child: panels[i]),
                                    if (i != panels.length - 1)
                                      const SizedBox(width: 16),
                                  ],
                                ],
                              );
                            },
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            right: 22,
            bottom: 22,
            child: FloatingActionButton.extended(
              onPressed: () => context.go('/manager/service-requests/pending'),
              backgroundColor: const Color(0xFF08C6D1),
              foregroundColor: const Color(0xFF071521),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text(
                'Yeni İş',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
}

class _CouldNotCompletePanel extends StatelessWidget {
  const _CouldNotCompletePanel({required this.rows, required this.onOpenAll});

  final List<Map<String, dynamic>> rows;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2232),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEA7C24).withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFA65B)),
              const SizedBox(width: 8),
              Text('Bugün Tamamlanamayan İşler (${rows.length})',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton(onPressed: onOpenAll, child: const Text('Servis Taleplerine Git')),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0x3324EA7C),
                child: Icon(Icons.close_rounded, color: Color(0xFFFFA65B)),
              ),
              title: Text(row['customer_name']?.toString() ?? 'Müşteri',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              subtitle: Text(row['completion_note']?.toString().trim().isNotEmpty == true
                  ? row['completion_note'].toString()
                  : 'Tekniker işi tamamlayamadı.',
                style: const TextStyle(color: Color(0xFFA7B7C5))),
              trailing: const Chip(label: Text('Yeniden değerlendir')),
            ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.data, required this.loading});

  final Map<String, dynamic> data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final cards = [
      _MetricData(
        'Toplam Müşteri',
        loading ? '…' : '${data['active_customers'] ?? 0}',
        Icons.groups_2_rounded,
        const [Color(0xFF275EC9), Color(0xFF224DAA)],
      ),
      _MetricData(
        'Aktif Servis',
        loading ? '…' : '${data['assigned'] ?? 0}',
        Icons.home_repair_service_rounded,
        const [Color(0xFF7544C3), Color(0xFF5E35A1)],
      ),
      _MetricData(
        'Bugünkü İşler',
        loading ? '…' : '${data['today_jobs_count'] ?? 0}',
        Icons.today_rounded,
        const [Color(0xFF18895E), Color(0xFF08704B)],
      ),
      _MetricData(
        'Bugünkü Ciro',
        loading ? '…' : money.format(data['daily_revenue'] ?? 0),
        Icons.trending_up_rounded,
        const [Color(0xFFE27619), Color(0xFFC85C11)],
      ),
      _MetricData(
        'Yaklaşan Bakım',
        loading ? '…' : '${data['upcoming_maintenance'] ?? 0}',
        Icons.event_repeat_rounded,
        const [Color(0xFFD74555), Color(0xFFB82F41)],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 1240
            ? 5
            : constraints.maxWidth >= 850
                ? 3
                : constraints.maxWidth >= 560
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: count == 1 ? 2.7 : 1.72,
          ),
          itemBuilder: (context, index) => _MetricCard(data: cards[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: data.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: data.colors.last.withValues(alpha: .28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            bottom: -16,
            child: Icon(
              data.icon,
              size: 92,
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
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

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.searchController,
    required this.status,
    required this.serviceType,
    required this.startDate,
    required this.endDate,
    required this.onStatusChanged,
    required this.onServiceTypeChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String status;
  final String serviceType;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onServiceTypeChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF17C7D1),
        secondary: Color(0xFF65DDE4),
        surface: Color(0xFF102A3D),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF102A3D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF295169)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF295169)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFF17C7D1), width: 1.6),
        ),
      ),
    );
    return Theme(
      data: darkTheme,
      child: _Panel(
      title: 'Filtreler',
      icon: Icons.tune_rounded,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: searchController,
              onSubmitted: (_) => onApply(),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Müşteri ara...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: serviceType,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tüm Servis Türleri')),
                DropdownMenuItem(value: 'Filtre Değişimi', child: Text('Filtre Değişimi')),
                DropdownMenuItem(value: 'Cihaz Montajı', child: Text('Cihaz Montajı')),
                DropdownMenuItem(value: 'Arıza', child: Text('Arıza')),
                DropdownMenuItem(value: 'Bakım', child: Text('Bakım')),
              ],
              onChanged: (value) => onServiceTypeChanged(value ?? 'all'),
            ),
          ),
          SizedBox(
            width: 175,
            child: DropdownButtonFormField<String>(
              initialValue: status,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tüm Durumlar')),
                DropdownMenuItem(value: 'pending', child: Text('Beklemede')),
                DropdownMenuItem(value: 'assigned', child: Text('Atandı')),
                DropdownMenuItem(value: 'in_progress', child: Text('Devam Ediyor')),
                DropdownMenuItem(value: 'completed', child: Text('Tamamlandı')),
                DropdownMenuItem(value: 'cancelled', child: Text('İptal')),
              ],
              onChanged: (value) => onStatusChanged(value ?? 'all'),
            ),
          ),
          _DateButton(label: 'Başlangıç', value: startDate, onTap: onPickStart),
          _DateButton(label: 'Bitiş', value: endDate, onTap: onPickEnd),
          FilledButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.filter_alt_rounded),
            label: const Text('Filtrele'),
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
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text(
        value == null ? label : DateFormat('dd.MM.yyyy').format(value!),
      ),
    );
  }
}

class _RecentServices extends StatelessWidget {
  const _RecentServices({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Son Servis Talepleri',
      icon: Icons.home_repair_service_rounded,
      action: TextButton(
        onPressed: () => context.go('/manager/service-requests'),
        child: const Text('Tümünü Gör'),
      ),
      child: rows.isEmpty
          ? const _EmptyText('Filtreye uygun servis bulunamadı.')
          : Column(
              children: [
                for (final row in rows.take(8))
                  _ServiceRow(row: row),
              ],
            ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? '';
    final statusData = _statusData(status);
    final date = DateTime.tryParse(row['planned_date']?.toString() ?? '') ??
        DateTime.tryParse(row['created_at']?.toString() ?? '');
    final price = (row['price'] as num?)?.toDouble() ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/manager/service-requests'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF19364A))),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFF12364B),
              child: Text(
                _initials(row['customer_name']?.toString() ?? '-'),
                style: const TextStyle(
                  color: Color(0xFF6CE0E7),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['customer_name']?.toString() ?? 'Müşteri',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    row['service_type']?.toString() ?? 'Servis',
                    style: const TextStyle(color: Color(0xFF86A2B4), fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                row['technician_name']?.toString() ?? 'Atanmadı',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFC1D2DC)),
              ),
            ),
            SizedBox(
              width: 105,
              child: _StatusBadge(label: statusData.$1, color: statusData.$2),
            ),
            SizedBox(
              width: 90,
              child: Text(
                date == null ? '-' : DateFormat('dd.MM.yyyy').format(date.toLocal()),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8FA9BB), fontSize: 12),
              ),
            ),
            SizedBox(
              width: 95,
              child: Text(
                NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
                    .format(price),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.rows});
  final List<Map<String, dynamic>> rows;

  String _timeLabel(Map<String, dynamic> row) {
    final raw = row['planned_date']?.toString();
    final date = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null || ((date.hour == 0 || date.hour == 3) && date.minute == 0)) {
      return 'Gün İçinde';
    }
    return DateFormat('HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Bugünkü İş Programı',
      icon: Icons.today_rounded,
      action: TextButton(
        onPressed: () => context.go('/manager/service-planning'),
        child: const Text('Takvim'),
      ),
      child: rows.isEmpty
          ? const _EmptyText('Bugün için planlı iş bulunmuyor.')
          : Column(
              children: [
                for (final row in rows.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 72,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10384B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _timeLabel(row),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF67DFE5),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      row['customer_name']?.toString() ?? 'Müşteri',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      row['service_type']?.toString() ?? 'Servis',
                      style: const TextStyle(color: Color(0xFF8FA9BB)),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _RecentPayments extends StatelessWidget {
  const _RecentPayments({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Son Tahsilatlar',
      icon: Icons.payments_rounded,
      action: TextButton(
        onPressed: () => context.go('/manager/payments'),
        child: const Text('Tümünü Gör'),
      ),
      child: rows.isEmpty
          ? const _EmptyText('Henüz tahsilat bulunmuyor.')
          : Column(
              children: [
                for (final row in rows.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF123B3E),
                      child: Icon(Icons.check_rounded, color: Color(0xFF57D6A4)),
                    ),
                    title: Text(
                      row['customer_name']?.toString() ?? 'Müşteri',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      row['payment_method_label']?.toString() ?? 'Tahsilat',
                      style: const TextStyle(color: Color(0xFF8FA9BB)),
                    ),
                    trailing: Text(
                      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0)
                          .format(row['amount'] ?? 0),
                      style: const TextStyle(
                        color: Color(0xFF6BE1B0),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Announcements extends StatelessWidget {
  const _Announcements();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      title: 'Duyurular',
      icon: Icons.campaign_rounded,
      child: Column(
        children: [
          _AnnouncementItem(
            icon: Icons.auto_awesome_rounded,
            title: 'MOTUS günlük kullanıma hazır',
            subtitle: 'Servis ve müşteri akışlarınızı panelden takip edebilirsiniz.',
          ),
          SizedBox(height: 10),
          _AnnouncementItem(
            icon: Icons.backup_outlined,
            title: 'Düzenli yedek alın',
            subtitle: 'Canlı kullanım öncesinde Supabase yedeğinizi güncel tutun.',
          ),
        ],
      ),
    );
  }
}

class _AnnouncementItem extends StatelessWidget {
  const _AnnouncementItem({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF60DDE4)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF8FA9BB), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child, this.action});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2233),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A3B51)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF58DCE4), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(text, style: const TextStyle(color: Color(0xFF819BAC))),
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon, this.colors);
  final String label;
  final String value;
  final IconData icon;
  final List<Color> colors;
}

(String, Color) _statusData(String status) {
  switch (status) {
    case 'completed':
      return ('Tamamlandı', const Color(0xFF66DEA8));
    case 'in_progress':
      return ('Devam Ediyor', const Color(0xFF65C7FF));
    case 'assigned':
      return ('Atandı', const Color(0xFFB59BFF));
    case 'cancelled':
      return ('İptal', const Color(0xFFFF7E8C));
    case 'could_not_complete':
      return ('Tamamlanamadı', const Color(0xFFFFA65B));
    default:
      return ('Beklemede', const Color(0xFFFFC857));
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '-';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String _time(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '--:--' : DateFormat('HH:mm').format(date.toLocal());
}
