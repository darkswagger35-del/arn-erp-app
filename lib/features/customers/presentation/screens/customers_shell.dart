import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/app_role.dart';
import 'customer_list_screen.dart';

class CustomersShell extends ConsumerWidget {
  const CustomersShell({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomerListScreen(role: role);
  }
}
