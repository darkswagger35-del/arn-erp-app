import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/app_role.dart';

class ArnAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArnAppBar({
    super.key,
    required this.title,
    required this.role,
    this.fallbackRoute,
    this.actions,
    this.showBackButton = true,
  });

  final String title;
  final AppRole role;
  final String? fallbackRoute;
  final List<Widget>? actions;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
              tooltip: 'Geri',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _goBack(context),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go(fallbackRoute ?? _fallbackRoute(role));
  }

  String _fallbackRoute(AppRole role) {
    switch (role) {
      case AppRole.admin:
        return '/admin-dashboard';
      case AppRole.manager:
        return '/admin-dashboard';
      case AppRole.secretary:
        return '/secretary-dashboard';
      case AppRole.technician:
        return '/technician-dashboard';
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
