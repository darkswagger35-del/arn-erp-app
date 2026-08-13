import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/features/user_management/domain/create_user_request.dart';
import 'package:arn_erp_app/features/user_management/domain/user_management_user.dart';

abstract class UserManagementRepository {
  Future<List<UserManagementUser>> listUsers({bool includeArchived = true});
  Future<void> createUser(CreateUserRequest request);
  Future<void> updateUser({
    required String userId,
    String? fullName,
    String? username,
    String? phone,
    AppRole? role,
    bool? isActive,
  });
  Future<void> sendPasswordReset(String email);
  Future<void> setUserPassword({required String userId, required String password});
  Future<void> archiveUser(String userId);
  Future<void> restoreUser(String userId, {required String username});
  Future<void> deleteUserPermanently(String userId);
  Future<PersonnelProfile> getPersonnelProfile(String userId);
}

class MockUserManagementRepository implements UserManagementRepository {
  @override
  Future<List<UserManagementUser>> listUsers({bool includeArchived = true}) async => const [];
  @override
  Future<void> createUser(CreateUserRequest request) async {}
  @override
  Future<void> updateUser({required String userId, String? fullName, String? username, String? phone, AppRole? role, bool? isActive}) async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> setUserPassword({required String userId, required String password}) async {}
  @override
  Future<void> archiveUser(String userId) async {}
  @override
  Future<void> restoreUser(String userId, {required String username}) async {}
  @override
  Future<void> deleteUserPermanently(String userId) async {}
  @override
  Future<PersonnelProfile> getPersonnelProfile(String userId) async => const PersonnelProfile(
    completedJobs: 0, monthJobs: 0, openedServices: 0,
    monthOpenedServices: 0, turnover: 0, monthTurnover: 0,
    recentJobs: [], usedProducts: [],
  );
}
