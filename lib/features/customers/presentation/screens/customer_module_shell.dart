import 'package:flutter/material.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/widgets/management_shell.dart';

class CustomerModuleShell extends StatelessWidget {
  const CustomerModuleShell({
    super.key,
    required this.role,
    required this.child,
    this.title,
    this.actions = const <Widget>[],
  });

  final AppRole role;
  final Widget child;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: role,
      title: title ?? 'Müşteriler',
      actions: actions,
      child: child,
    );
  }
}
