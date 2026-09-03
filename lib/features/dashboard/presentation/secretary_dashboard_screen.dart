import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../operations/data/operations_providers.dart';
import '../../secretary_crm/data/secretary_crm_provider.dart';
import '../../secretary_crm/data/secretary_crm_repository.dart';
import '../../settings/data/company_app_settings.dart';

class SecretaryDashboardScreen extends ConsumerStatefulWidget {
  const SecretaryDashboardScreen({super.key});

  @override
  ConsumerState<SecretaryDashboardScreen> createState() => _SecretaryDashboardScreenState();
}

class _SecretaryDashboardData {
  const _SecretaryDashboardData({
    required this.workspace,
    required this.counts,
    required this.latestLeads,
    required this.maintenance,
    required this.performance,
  });
  final Map<String, dynamic> workspace;
  final SecretaryFollowUpCounts counts;
  final List<SecretaryLead> latestLeads;
  final List<MaintenanceReminder> maintenance;
  final Map<String, num> performance;
}

class _DashboardColumn {
  const _DashboardColumn(this.flex, this.child);
  final int flex;
  final Widget child;
}

class _SecretaryDashboardScreenState extends ConsumerState<SecretaryDashboardScreen> {
  DateTime _selectedDate = DateTime.now();
  late Future<_SecretaryDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  static const _emptyCounts = SecretaryFollowUpCounts(
    newCount: 0,
    nowCount: 0,
    todayCount: 0,
    unansweredCount: 0,
    futureCount: 0,
    overdueCount: 0,
    trackingCount: 0,
    closedCount: 0,
    wonToday: 0,
    callsToday: 0,
  );

  Future<T> _safe<T>(Future<T> future, T fallback) async {
    try {
      return await future.timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('Sekreter paneli veri yükleme uyarısı: $error');
      return fallback;
    }
  }

  Future<_SecretaryDashboardData> _load() async {
    final crm = ref.read(secretaryCrmRepositoryProvider);
    final maintenanceRepository = MaintenanceRepository(crm.client);

    // V63: Bir Supabase sorgusu takılırsa tüm sekreter panelini sonsuza kadar
    // kilitlemiyoruz. Her bölüm bağımsız yüklenir ve 3 sn sonra güvenli varsayılanla
    // devam eder. Böylece menüler ve çalışan diğer bölümler kullanılabilir kalır.
    final results = await Future.wait<Object>([
      _safe<Map<String, dynamic>>(
        ref.read(operationsRepositoryProvider).dashboardWorkspace(selectedDate: _selectedDate),
        <String, dynamic>{
          'today_jobs': <Map<String, dynamic>>[],
          'selected_completed': 0,
          'selected_cancelled': 0,
        },
      ),
      _safe<SecretaryFollowUpCounts>(crm.counts(), _emptyCounts),
      _safe<List<SecretaryLead>>(crm.latestLeads(limit: 6), const <SecretaryLead>[]),
      _safe<List<MaintenanceReminder>>(
        maintenanceRepository.getUpcoming(days: 45),
        const <MaintenanceReminder>[],
      ),
      _safe<Map<String, num>>(crm.todayServicePerformance(), const <String, num>{}),
    ]);
    return _SecretaryDashboardData(
      workspace: results[0] as Map<String, dynamic>,
      counts: results[1] as SecretaryFollowUpCounts,
      latestLeads: results[2] as List<SecretaryLead>,
      maintenance: (results[3] as List<MaintenanceReminder>).take(5).toList(growable: false),
      performance: results[4] as Map<String, num>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  void _changeDay(int delta) {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + delta);
      _future = _load();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Görüntülenecek günü seç',
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = picked;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final name = auth.profile?.fullName.trim().isNotEmpty == true ? auth.profile!.fullName.trim() : 'Sekreter';
    final panelSettings = ref.watch(companyAppSettingsProvider).asData?.value ??
        const CompanyAppSettings(companyId: '');
    bool showPanel(String key) => panelSettings.panelVisible('secretary', key);
    return ManagementShell(
      role: AppRole.secretary,
      title: 'Günaydın, $name 👋',
      subtitle: 'Başvurularınızı, takiplerinizi ve aldığınız servis işlerini tek ekrandan yönetin.',
      actions: [
        IconButton(onPressed: () => _changeDay(-1), icon: const Icon(Icons.chevron_left_rounded)),
        OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_outlined), label: Text(DateFormat('dd MMMM yyyy, EEEE', 'tr_TR').format(_selectedDate))),
        IconButton(onPressed: () => _changeDay(1), icon: const Icon(Icons.chevron_right_rounded)),
        TextButton(onPressed: () => setState(() { _selectedDate = DateTime.now(); _future = _load(); }), child: const Text('Bugün')),
        IconButton.filledTonal(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
      ],
      child: FutureBuilder<_SecretaryDashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Sekreter paneli yüklenemedi.\n${snapshot.error}', textAlign: TextAlign.center));
          final data = snapshot.data!;
          final workspace = data.workspace;
          final jobs = _maps(workspace['today_jobs']);
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (showPanel('metrics')) _topMetrics(data, jobs),
                if (showPanel('metrics') &&
                    (showPanel('today_jobs') ||
                        showPanel('latest_leads') ||
                        showPanel('follow_up') ||
                        showPanel('upcoming_maintenance') ||
                        showPanel('quick_actions') ||
                        showPanel('performance')))
                  const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= 1160;
                  final leftItems = <Widget>[
                    if (showPanel('today_jobs')) _jobsPanel(jobs),
                    if (showPanel('latest_leads')) _latestLeadsPanel(data.latestLeads),
                  ];
                  final centerItems = <Widget>[
                    if (showPanel('follow_up')) _followUpPanel(data.counts),
                    if (showPanel('upcoming_maintenance')) _maintenancePanel(data.maintenance),
                  ];
                  final rightItems = <Widget>[
                    if (showPanel('quick_actions')) _quickActions(),
                    if (showPanel('performance')) _performancePanel(data),
                  ];
                  final columns = <_DashboardColumn>[
                    if (leftItems.isNotEmpty) _DashboardColumn(6, Column(children: _verticalGaps(leftItems, 16))),
                    if (centerItems.isNotEmpty) _DashboardColumn(4, Column(children: _verticalGaps(centerItems, 16))),
                    if (rightItems.isNotEmpty) _DashboardColumn(4, Column(children: _verticalGaps(rightItems, 16))),
                  ];
                  if (columns.isEmpty) return const SizedBox.shrink();
                  if (!wide) {
                    return Column(children: _verticalGaps(columns.map((e) => e.child).toList(), 16));
                  }
                  final rowChildren = <Widget>[];
                  for (var i = 0; i < columns.length; i++) {
                    if (i > 0) rowChildren.add(const SizedBox(width: 16));
                    rowChildren.add(Expanded(flex: columns[i].flex, child: columns[i].child));
                  }
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren);
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _verticalGaps(List<Widget> items, double gap) {
    final result = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      if (index > 0) result.add(SizedBox(height: gap));
      result.add(items[index]);
    }
    return result;
  }

  Widget _topMetrics(_SecretaryDashboardData data, List<Map<String, dynamic>> jobs) {
    final assigned = jobs.where((e) => ['assigned','in_progress'].contains(e['status']?.toString())).length;
    final completed = (data.workspace['selected_completed'] as num?)?.toInt() ?? 0;
    final cancelled = (data.workspace['selected_cancelled'] as num?)?.toInt() ?? 0;
    final cards = [
      _Metric('Yeni Başvuru', data.counts.newCount, Icons.person_add_alt_1_rounded, const Color(0xFF2979FF), () => context.go('/secretary/follow-ups')),
      _Metric('Bugün Aranacak', data.counts.todayCount, Icons.phone_in_talk_rounded, const Color(0xFFEA8A1A), () => context.go('/secretary/follow-ups/today')),
      _Metric('Alınan İşlerim', data.counts.wonToday, Icons.handshake_outlined, const Color(0xFF7C5CE7), () => context.go('/secretary/service-requests')),
      _Metric('Teknikerde', assigned, Icons.engineering_outlined, const Color(0xFF3D8BFF), () => context.go('/secretary/service-requests')),
      _Metric('Tamamlanan', completed, Icons.check_circle_outline_rounded, const Color(0xFF18A866), () => context.go('/secretary/service-requests')),
      _Metric('Sorunlu / Gidilemedi', cancelled, Icons.warning_amber_rounded, const Color(0xFFE75454), () => context.go('/secretary/service-requests')),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1200 ? 6 : c.maxWidth >= 760 ? 3 : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: cols == 6 ? 1.75 : 2.1,
        children: cards.map((m) => InkWell(
          onTap: m.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8F0))),
            child: Row(children: [
              CircleAvatar(radius: 24, backgroundColor: m.color.withOpacity(.12), child: Icon(m.icon, color: m.color)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(m.label, style: const TextStyle(fontSize: 12, color: Color(0xFF66778A), fontWeight: FontWeight.w700)),
                Text('${m.value}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35))),
              ])),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF9AABBC)),
            ]),
          ),
        )).toList(growable: false),
      );
    });
  }

  Widget _jobsPanel(List<Map<String, dynamic>> jobs) => _panel(
    title: 'Seçili Gün İşlerim',
    trailing: TextButton(onPressed: () => context.go('/secretary/service-requests'), child: const Text('Tümünü Gör')),
    child: jobs.isEmpty
        ? const Padding(padding: EdgeInsets.all(45), child: Center(child: Text('Bu tarihte servis kaydı bulunamadı.')))
        : Column(children: jobs.take(7).map((job) {
            final customerId = job['customer_id']?.toString() ?? '';
            final status = job['status']?.toString() ?? '';
            final price = (job['price'] as num?)?.toDouble() ?? 0;
            final planned = DateTime.tryParse(job['planned_date']?.toString() ?? '')?.toLocal();
            return Column(children: [
              ListTile(
                onTap: customerId.isEmpty ? null : () => context.go('/secretary/customers/$customerId'),
                title: Text(job['customer_name']?.toString() ?? 'Müşteri', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${job['technician_name'] ?? 'Atanmadı'} • ${job['service_type'] ?? 'Servis'} • ${planned == null ? 'Gün içinde' : DateFormat('HH:mm').format(planned)}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _statusPill(status),
                  if (price > 0) Text('${price.toStringAsFixed(0)} TL', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0AAEC0))),
                ]),
              ),
              const Divider(height: 1),
            ]);
          }).toList(growable: false)),
  );

  Widget _followUpPanel(SecretaryFollowUpCounts c) {
    final rows = [
      ('Şimdi Aranacak', c.nowCount, Icons.phone_in_talk_rounded, const Color(0xFFE75454), 'now'),
      ('Bugün Aranacak', c.todayCount, Icons.phone_callback_rounded, const Color(0xFFEA8A1A), 'today'),
      ('Cevapsız Çağrılar', c.unansweredCount, Icons.phone_missed_rounded, const Color(0xFF7C5CE7), 'unanswered'),
      ('Yarın / Sonraki Gün', c.futureCount, Icons.event_outlined, const Color(0xFF2979FF), 'future'),
      ('Geciken Takipler', c.overdueCount, Icons.schedule_rounded, const Color(0xFF66778A), 'overdue'),
    ];
    return _panel(
      title: 'Takip Listesi',
      trailing: TextButton(onPressed: () => context.go('/secretary/follow-ups'), child: const Text('Tümü')),
      child: Column(children: rows.map((r) => ListTile(
        onTap: () => context.go('/secretary/follow-ups/${r.$5}'),
        leading: CircleAvatar(backgroundColor: r.$4.withOpacity(.12), child: Icon(r.$3, color: r.$4)),
        title: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: Badge(label: Text('${r.$2}'), backgroundColor: r.$4),
      )).toList(growable: false)),
    );
  }

  Widget _latestLeadsPanel(List<SecretaryLead> rows) => _panel(
    title: 'Son Eklenen Başvurular',
    trailing: TextButton(onPressed: () => context.go('/secretary/follow-ups'), child: const Text('Tümü')),
    child: rows.isEmpty
        ? const Padding(padding: EdgeInsets.all(35), child: Center(child: Text('Henüz başvuru kaydı yok.')))
        : Column(children: rows.map((lead) => ListTile(
            onTap: () => context.go('/secretary/follow-ups'),
            leading: CircleAvatar(child: Text(lead.fullName.isEmpty ? '?' : lead.fullName[0].toUpperCase())),
            title: Text(lead.fullName, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${lead.phone} • ${lead.source ?? 'Reklam'}'),
            trailing: Text(_leadLabel(lead), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7C5CE7))),
          )).toList(growable: false)),
  );

  Widget _maintenancePanel(List<MaintenanceReminder> rows) => _panel(
    title: 'Bakımı Yaklaşanlar',
    trailing: TextButton(onPressed: () => context.go('/secretary/maintenance'), child: const Text('Tümü')),
    child: rows.isEmpty
        ? const Padding(padding: EdgeInsets.all(35), child: Center(child: Text('Yaklaşan bakım bulunmuyor.')))
        : Column(children: rows.map((item) => ListTile(
            onTap: () => context.go('/secretary/customers/${item.customerId}'),
            leading: CircleAvatar(backgroundColor: const Color(0xFFFFF0D9), child: Text('${item.daysRemaining}', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900))),
            title: Text(item.customerName, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${item.productName} • ${DateFormat('dd.MM.yyyy').format(item.nextMaintenanceDate)}'),
            trailing: const Icon(Icons.chevron_right_rounded),
          )).toList(growable: false)),
  );

  Widget _quickActions() {
    final actions = [
      ('Yeni Başvuru', Icons.person_add_alt_1_rounded, const Color(0xFF2979FF), () => context.go('/secretary/follow-ups')),
      ('Servis Talebi', Icons.home_repair_service_outlined, const Color(0xFF18A866), () => context.go('/secretary/customers')),
      ('Geçmiş Müşteri Kaydı', Icons.history_rounded, const Color(0xFF7C5CE7), () => context.go('/secretary/customers/historical')),
      ('Bakımı Yaklaşanlar', Icons.notifications_active_outlined, const Color(0xFFF59E0B), () => context.go('/secretary/maintenance')),
      ('Aktif Müşteriler', Icons.person_outline_rounded, const Color(0xFF18A866), () => context.go('/secretary/customers')),
      ('Takiptekiler', Icons.schedule_rounded, const Color(0xFFF59E0B), () => context.go('/secretary/follow-ups/tracking')),
      ('Kapandı', Icons.cancel_outlined, const Color(0xFFE75454), () => context.go('/secretary/follow-ups/closed')),
    ];
    return _panel(
      title: 'Hızlı İşlemler',
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: actions.map((a) => InkWell(
          onTap: a.$4,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: a.$3.withOpacity(.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: a.$3.withOpacity(.16))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(a.$2, color: a.$3), const SizedBox(height: 7), Text(a.$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]),
          ),
        )).toList(growable: false),
      ),
    );
  }

  Widget _performancePanel(_SecretaryDashboardData d) {
    final revenue = (d.performance['revenue'] ?? 0).toDouble();
    return _panel(
      title: 'Bugünkü Performansım',
      trailing: TextButton(onPressed: () => context.go('/secretary/reports'), child: const Text('Detay')),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.8,
        children: [
          _perf('Aranan Müşteri', d.counts.callsToday, Icons.phone_outlined),
          _perf('Alınan İş', d.counts.wonToday, Icons.handshake_outlined),
          _perf('Tamamlanan', (d.performance['completed'] ?? 0).toInt(), Icons.check_circle_outline),
          _perf('Ciro', revenue.toInt(), Icons.trending_up_rounded, suffix: ' TL'),
        ],
      ),
    );
  }

  Widget _perf(String label, int value, IconData icon, {String suffix = ''}) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: const Color(0xFFF6F9FC), borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Icon(icon, color: const Color(0xFF0AAEC0)), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF66778A))), Text('$value$suffix', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))]))]),
  );

  Widget _panel({required String title, Widget? trailing, required Widget child}) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8F0))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 10, 8), child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35)))), if (trailing != null) trailing])),
      const Divider(height: 1),
      child,
    ]),
  );

  Widget _statusPill(String status) {
    final (label, color) = switch (status) {
      'completed' => ('Tamamlandı', const Color(0xFF18A866)),
      'in_progress' => ('Devam Ediyor', const Color(0xFFEA8A1A)),
      'assigned' => ('Teknikerde', const Color(0xFF7C5CE7)),
      'cancelled' || 'canceled' || 'could_not_complete' => ('Gidilemedi', const Color(0xFFE75454)),
      _ => ('Bekliyor', const Color(0xFFF59E0B)),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(20)), child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)));
  }

  String _leadLabel(SecretaryLead lead) {
    if (lead.status == 'closed') return 'Kapandı';
    if (lead.status == 'won') return 'İş Alındı';
    if (lead.outcomeCode == 'unanswered') return 'Cevapsız';
    if (lead.followUpAt != null) return DateFormat('dd.MM HH:mm').format(lead.followUpAt!.toLocal());
    return 'Yeni';
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color, this.onTap);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
