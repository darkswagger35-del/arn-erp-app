import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/user_profile.dart';
import '../domain/create_user_request.dart';
import '../domain/user_management_user.dart';
import 'user_management_repository.dart';

typedef UserManagementFunctionInvoker =
    Future<dynamic> Function(String functionName, {Map<String, dynamic>? body});

class UserManagementRepositoryImpl implements UserManagementRepository {
  UserManagementRepositoryImpl({this.client, this.invoker});

  final SupabaseClient? client;
  final UserManagementFunctionInvoker? invoker;

  SupabaseClient get _client => client ?? Supabase.instance.client;

  @override
  Future<List<UserManagementUser>> listUsers({bool includeArchived = true}) async {
    final currentProfile = await _getCurrentProfile();
    if (currentProfile == null) throw const AppException('Oturum doğrulanamadı.');

    try {
      dynamic query = _client
          .from('profiles')
          .select('id, company_id, full_name, email, phone, username, role, is_active, deleted_at, last_sign_in_at, created_at, updated_at')
          .eq('company_id', currentProfile.companyId);
      if (!includeArchived) query = query.isFilter('deleted_at', null);
      final rows = await query.order('deleted_at', ascending: true).order('full_name');
      return (rows as List)
          .map((e) => UserManagementUser.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> createUser(CreateUserRequest request) async {
    final payload = await _invokeFunction('create-company-user', body: {
      'email': request.email,
      'full_name': request.fullName,
      'username': request.username,
      'phone': request.phone,
      'role': request.role.value,
      'password': request.password,
      'password_confirmation': request.passwordConfirmation,
      'is_active': request.isActive,
    });
    final data = _normalize(payload);
    if (data['success'] != true) {
      throw AppException(data['message']?.toString() ?? 'Kullanıcı oluşturulamadı.');
    }

  }

  @override
  Future<void> updateUser({
    required String userId,
    String? fullName,
    String? username,
    String? phone,
    AppRole? role,
    bool? isActive,
  }) async {
    try {
      await _client.rpc('admin_update_company_user_v31', params: {
        'p_user_id': userId,
        'p_full_name': fullName,
        'p_username': username,
        'p_phone': phone,
        'p_role': role?.value,
        'p_is_active': isActive,
      });
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> archiveUser(String userId) async {
    try {
      await _client.rpc('archive_company_user_v31', params: {'p_user_id': userId});
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> restoreUser(String userId, {required String username}) async {
    try {
      await _client.rpc('restore_company_user_v31', params: {
        'p_user_id': userId,
        'p_username': username,
      });
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> deleteUserPermanently(String userId) async {
    final data = _normalize(await _invokeFunction('delete-company-user', body: {
      'user_id': userId,
    }));
    if (data['success'] != true) {
      throw AppException(data['message']?.toString() ?? 'Kullanıcı kalıcı olarak silinemedi.');
    }
  }

  @override
  Future<PersonnelProfile> getPersonnelProfile(String userId) async {
    try {
      final response = await _client.rpc(
        'personnel_profile_v31',
        params: {'p_user_id': userId},
      );
      return PersonnelProfile.fromJson(Map<String, dynamic>.from(response as Map));
    } on PostgrestException catch (e) {
      throw AppException(e.message);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    final data = _normalize(await _invokeFunction('send-password-reset', body: {'email': email}));
    if (data['success'] != true) throw AppException(data['message']?.toString() ?? 'İşlem başarısız.');
  }

  @override
  Future<void> setUserPassword({required String userId, required String password}) async {
    final data = _normalize(await _invokeFunction('set-company-user-password', body: {
      'user_id': userId,
      'password': password,
    }));
    if (data['success'] != true) throw AppException(data['message']?.toString() ?? 'Şifre güncellenemedi.');
  }

  Future<dynamic> _invokeFunction(String name, {Map<String, dynamic>? body}) async {
    if (invoker != null) return invoker!(name, body: body);
    final response = await _client.functions.invoke(name, body: body);
    return response.data;
  }

  Future<UserProfile?> _getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Map<String, dynamic> _normalize(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }
}
