import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/app_environment.dart';
import 'user_management_repository.dart';
import 'user_management_repository_impl.dart';

final userManagementRepositoryProvider = Provider<UserManagementRepository>((
  ref,
) {
  final environment = AppEnvironment.fromEnvironment();
  if (!environment.isConfigured) {
    return MockUserManagementRepository();
  }
  return UserManagementRepositoryImpl();
});
