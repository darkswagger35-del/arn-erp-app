import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/app_role.dart';
import '../auth/auth_provider.dart';

class ManagementShell extends ConsumerWidget {
  const ManagementShell({
    super.key,
    required this.role,
    required this.child,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.dark = false,
  });

  final AppRole role;
  final Widget child;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool dark;

  String get _prefix => switch (role) {
        AppRole.secretary => '/secretary',
        AppRole.technician => '/technician',
        _ => '/manager',
      };

  String get _dashboardRoute => switch (role) {
        AppRole.secretary => '/secretary-dashboard',
        AppRole.technician => '/technician-dashboard',
        _ => '/admin-dashboard',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 980;
    final authState = ref.watch(authControllerProvider);
    final displayName = (authState.profile?.fullName.trim().isNotEmpty ?? false)
        ? authState.profile!.fullName.trim()
        : role.label;
    final currentPath = GoRouterState.of(context).uri.path;
    final sidebar = _ManagementSidebar(
      role: role,
      prefix: _prefix,
      dashboardRoute: _dashboardRoute,
      currentPath: currentPath,
      displayName: displayName,
    );

    final content = ColoredBox(
      color: dark ? const Color(0xFF07111B) : const Color(0xFFF4F7FB),
      child: Column(
        children: [
          _ManagementHeader(
            title: title,
            subtitle: subtitle,
            actions: actions,
            showMenuButton: !isDesktop,
            onMenuPressed: () => Scaffold.of(context).openDrawer(),
            dark: dark,
          ),
          Expanded(
            child: dark
                ? Theme(
                    data: ThemeData(
                      brightness: Brightness.dark,
                      scaffoldBackgroundColor: const Color(0xFF07111B),
                      cardColor: const Color(0xFF0D1A26),
                      dividerColor: const Color(0xFF223241),
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFF12B8C4),
                        secondary: Color(0xFF12B8C4),
                        surface: Color(0xFF0D1A26),
                        error: Color(0xFFFF6B6B),
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFF101F2C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A3A48)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A3A48)),
                        ),
                      ),
                      cardTheme: CardThemeData(
                        color: const Color(0xFF0D1A26),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF223241)),
                        ),
                      ),
                    ),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: dark ? const Color(0xFF07111B) : const Color(0xFFF4F7FB),
        drawer: Drawer(width: 250, child: sidebar),
        body: SafeArea(
          child: Builder(
            builder: (innerContext) => ColoredBox(
            color: dark ? const Color(0xFF07111B) : const Color(0xFFF4F7FB),
            child: Column(
              children: [
                _ManagementHeader(
                  title: title,
                  subtitle: subtitle,
                  actions: actions,
                  showMenuButton: true,
                  onMenuPressed: () => Scaffold.of(innerContext).openDrawer(),
                  dark: dark,
                ),
                Expanded(
            child: dark
                ? Theme(
                    data: ThemeData(
                      brightness: Brightness.dark,
                      scaffoldBackgroundColor: const Color(0xFF07111B),
                      cardColor: const Color(0xFF0D1A26),
                      dividerColor: const Color(0xFF223241),
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFF12B8C4),
                        secondary: Color(0xFF12B8C4),
                        surface: Color(0xFF0D1A26),
                        error: Color(0xFFFF6B6B),
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: const Color(0xFF101F2C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A3A48)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF2A3A48)),
                        ),
                      ),
                      cardTheme: CardThemeData(
                        color: const Color(0xFF0D1A26),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF223241)),
                        ),
                      ),
                    ),
                    child: child,
                  )
                : child,
          ),
              ],
            ),
          ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF07111B) : const Color(0xFFF4F7FB),
      body: Row(
        children: [
          SizedBox(width: 220, child: sidebar),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _ManagementHeader extends StatelessWidget {
  const _ManagementHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.showMenuButton,
    required this.onMenuPressed,
    required this.dark,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showMenuButton;
  final VoidCallback onMenuPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final titleStyle = TextStyle(
          fontSize: compact ? 20 : 24,
          fontWeight: FontWeight.w900,
          color: dark ? Colors.white : const Color(0xFF0B1F35),
        );
        final subtitleStyle = TextStyle(
          color: dark ? const Color(0xFF91A4B7) : const Color(0xFF6D7C91),
          fontSize: compact ? 12 : 14,
        );

        Widget titleBlock() => Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                  if (subtitle != null && !compact) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
                  ],
                ],
              ),
            );

        Widget menuButton() => IconButton(
              tooltip: 'Menüyü aç',
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu_rounded),
            );

        final headerColor = dark ? const Color(0xFF0B1622) : Colors.white;
        final borderColor = dark ? const Color(0xFF203140) : const Color(0xFFE4EAF2);

        if (compact) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (showMenuButton) menuButton(),
                    if (showMenuButton) const SizedBox(width: 4),
                    titleBlock(),
                  ],
                ),
                if (subtitle != null) ...[
                  Padding(
                    padding: EdgeInsets.only(left: showMenuButton ? 52 : 4, right: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 2),
                          ...actions.map((action) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: action,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: headerColor,
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              if (showMenuButton) ...[
                menuButton(),
                const SizedBox(width: 6),
              ],
              titleBlock(),
              if (actions.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ManagementSidebar extends ConsumerWidget {
  const _ManagementSidebar({
    required this.role,
    required this.prefix,
    required this.dashboardRoute,
    required this.currentPath,
    required this.displayName,
  });

  final AppRole role;
  final String prefix;
  final String dashboardRoute;
  final String currentPath;
  final String displayName;

  bool _selected(String route) =>
      currentPath == route || currentPath.startsWith('$route/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final technicianItems = <_SideItem>[
            _SideItem(Icons.dashboard_outlined, 'Ana Sayfa', dashboardRoute),
            const _SideItem(Icons.calendar_month_outlined, 'Günlük İşler', '/technician/jobs'),
          ];

    final managerGroups = <_SideGroup>[
      _SideGroup(
        icon: Icons.home_repair_service_outlined,
        label: 'Servis Yönetimi',
        children: const [
          _SideItem(Icons.assignment_outlined, 'Servis Talepleri', '/manager/service-requests'),
          _SideItem(Icons.location_on_outlined, 'Bölgeler & Rota', '/manager/dispatch'),
          _SideItem(Icons.calendar_month_outlined, 'Takvim', '/manager/service-planning'),
          _SideItem(Icons.description_outlined, 'Servis Formları', '/manager/service-documents'),
          _SideItem(Icons.design_services_outlined, 'Form Tasarımcısı', '/manager/service-form-designer'),
        ],
      ),
      _SideGroup(
        icon: Icons.inventory_2_outlined,
        label: 'Stok & Ürünler',
        children: const [
          _SideItem(Icons.inventory_2_outlined, 'Ürünler', '/manager/products'),
          _SideItem(Icons.warehouse_outlined, 'Depolar', '/manager/warehouses'),
          _SideItem(Icons.swap_horiz_rounded, 'Stok Hareketleri', '/manager/stock-movements'),
        ],
      ),
      _SideGroup(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Finans & Raporlar',
        children: const [
          _SideItem(Icons.payments_outlined, 'Tahsilatlar', '/manager/payments'),
          _SideItem(Icons.assessment_outlined, 'Raporlar', '/manager/reports'),
        ],
      ),
      _SideGroup(
        icon: Icons.admin_panel_settings_outlined,
        label: 'Yönetim',
        children: const [
          _SideItem(Icons.manage_accounts_outlined, 'Kullanıcılar', '/manager/users'),
          _SideItem(Icons.table_view_rounded, 'Excel Aktarım', '/manager/excel-transfer'),
          _SideItem(Icons.notifications_none_rounded, 'Bildirimler', '/notifications'),
          _SideItem(Icons.settings_outlined, 'Ayarlar', '/manager/settings'),
        ],
      ),
    ];

    return ColoredBox(
      color: const Color(0xFF071C2D),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 14, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFF10BAC6),
                    child: Icon(Icons.water_drop_rounded, color: Colors.white, size: 28),
                  ),
                  SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MOTUS', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
                      Text('SERVİS YÖNETİM PLATFORMU', style: TextStyle(color: Colors.white70, fontSize: 7.5, letterSpacing: .9)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: role == AppRole.manager || role == AppRole.admin
                    ? [
                        _sideTile(context, _SideItem(Icons.dashboard_outlined, 'Ana Panel', dashboardRoute)),
                        _sideTile(context, _SideItem(Icons.people_alt_outlined, 'Müşteriler', '$prefix/customers')),
                        const SizedBox(height: 4),
                        ...managerGroups.map((group) => _groupTile(context, group)),
                      ]
                    : role == AppRole.secretary
                        ? [
                            _sideTile(context, _SideItem(Icons.dashboard_outlined, 'Ana Sayfa', dashboardRoute)),
                            _sideTile(context, _SideItem(Icons.people_alt_outlined, 'Müşteriler', '$prefix/customers')),
                            _sideTile(context, _SideItem(Icons.home_repair_service_outlined, 'Servis Talepleri', '$prefix/service-requests')),
                            _sideTile(context, _SideItem(Icons.fact_check_outlined, 'Takip Listesi', '$prefix/follow-ups')),
                            _sideTile(context, _SideItem(Icons.notifications_active_outlined, 'Bakımı Yaklaşanlar', '$prefix/maintenance')),
                            _sideTile(context, _SideItem(Icons.person_outline_rounded, 'Aktif Müşteriler', '$prefix/customers')),
                            _sideTile(context, _SideItem(Icons.schedule_rounded, 'Takiptekiler', '$prefix/follow-ups/tracking')),
                            _sideTile(context, _SideItem(Icons.cancel_outlined, 'Kapandı', '$prefix/follow-ups/closed')),
                            _sideTile(context, _SideItem(Icons.bar_chart_rounded, 'Raporlar', '$prefix/reports')),
                          ]
                        : technicianItems.map((item) => _sideTile(context, item)).toList(),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF17364A)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF18C7D1),
                    child: Icon(Icons.person_outline, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        Text(role.label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Çıkış',
                    onPressed: () async {
                      await ref.read(authControllerProvider.notifier).signOut();
                      if (context.mounted) context.go('/login');
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.white70, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideTile(BuildContext context, _SideItem item, {bool nested = false}) {
    final selected = _selected(item.route);
    return Padding(
      padding: EdgeInsets.fromLTRB(nested ? 12 : 0, 2, 0, 2),
      child: Material(
        color: selected ? const Color(0xFF0D6578) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          minLeadingWidth: 24,
          leading: Icon(item.icon, size: nested ? 18 : 20,
              color: selected ? const Color(0xFF22D3DC) : const Color(0xFFC4D1DC)),
          title: Text(item.label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFD5E0E8),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                fontSize: nested ? 12.5 : 13,
              )),
          onTap: () => context.go(item.route),
        ),
      ),
    );
  }

  Widget _groupTile(BuildContext context, _SideGroup group) {
    final active = group.children.any((item) => _selected(item.route));
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('sidebar-${group.label}'),
        initiallyExpanded: active,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(group.icon, size: 20,
            color: active ? const Color(0xFF22D3DC) : const Color(0xFFC4D1DC)),
        title: Text(group.label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFFD5E0E8),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            )),
        iconColor: const Color(0xFF22D3DC),
        collapsedIconColor: const Color(0xFF7F93A4),
        children: group.children.map((item) => _sideTile(context, item, nested: true)).toList(),
      ),
    );
  }

}

class _SideGroup {
  const _SideGroup({required this.icon, required this.label, required this.children});

  final IconData icon;
  final String label;
  final List<_SideItem> children;
}

class _SideItem {
  const _SideItem(this.icon, this.label, this.route);

  final IconData icon;
  final String label;
  final String route;
}
