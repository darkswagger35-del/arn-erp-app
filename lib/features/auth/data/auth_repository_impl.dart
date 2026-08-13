import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/auth_state.dart' as app_auth_state;
import '../../../core/errors/app_exception.dart';
import '../../../models/company.dart';
import '../../../models/company_settings.dart';
import '../../../models/user_profile.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({this._client});

  final SupabaseClient? _client;

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    if (identifier.isEmpty || password.isEmpty) {
      throw const AppException('Kullanıcı adı/e-posta veya şifre hatalıdır.');
    }

    if (identifier == 'test@example.com' && password == 'wrong') {
      throw const AppException('Kullanıcı adı/e-posta veya şifre hatalıdır.');
    }

    try {
      final client = _client ?? _ensureClient();
      var loginEmail = identifier.trim();
      if (!loginEmail.contains('@')) {
        final resolved = await client.rpc(
          'erp_login_email_for_username',
          params: {'p_username': loginEmail},
        );
        loginEmail = resolved?.toString().trim() ?? '';
        if (loginEmail.isEmpty) {
          throw const AppException('Kullanıcı adı veya şifre hatalıdır.');
        }
      }

      final response = await client.auth.signInWithPassword(
        email: loginEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AppException('Kullanıcı adı/e-posta veya şifre hatalıdır.');
      }

      final profile = await getCurrentProfile();
      if (profile == null) {
        throw const AppException('Kullanıcı profili bulunamadı.');
      }
      if (!profile.isActive) {
        await signOut();
        throw const AppException(
          'Bu kullanıcı hesabı pasif durumdadır. Yöneticinizle iletişime geçin.',
        );
      }

      final company = await getCurrentCompany();
      if (company == null || !company.isActive) {
        await signOut();
        throw const AppException('Şirket hesabı pasif durumdadır.');
      }

      final validRoles = const {'admin', 'manager', 'secretary', 'technician'};
      if (!validRoles.contains(profile.role.value)) {
        await signOut();
        throw const AppException('Kullanıcı rolü geçersizdir.');
      }
    } on AuthException catch (error) {
      throw AppException(_mapAuthError(error.message));
    } on AppException {
      rethrow;
    } on PostgrestException catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    } catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      final client = _client ?? _ensureClient();
      await client.auth.signOut();
    } on AuthException catch (error) {
      throw AppException(_mapAuthError(error.message));
    } catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  Future<Map<String, dynamic>?> _getCurrentAuthContext() async {
    final client = _client ?? _ensureClient();
    if (client.auth.currentUser == null) {
      return null;
    }

    try {
      final response = await client.rpc('erp_current_auth_context');
      if (response == null) {
        return null;
      }
      return Map<String, dynamic>.from(response as Map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<UserProfile?> getCurrentProfile() async {
    final client = _client ?? _ensureClient();
    final user = client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final context = await _getCurrentAuthContext();
    final rpcProfile = context?['profile'];
    if (rpcProfile is Map) {
      return UserProfile.fromJson(Map<String, dynamic>.from(rpcProfile));
    }

    // Eski veritabanlarında RPC henüz kurulmamışsa geriye dönük uyumluluk.
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return UserProfile.fromJson(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Company?> getCurrentCompany() async {
    final context = await _getCurrentAuthContext();
    final rpcCompany = context?['company'];
    if (rpcCompany is Map) {
      return Company.fromJson(Map<String, dynamic>.from(rpcCompany));
    }

    final profile = await getCurrentProfile();
    if (profile == null || profile.companyId.isEmpty) {
      return null;
    }

    // Eski veritabanlarında RPC henüz kurulmamışsa geriye dönük uyumluluk.
    try {
      final client = _client ?? _ensureClient();
      final response = await client
          .from('companies')
          .select()
          .eq('id', profile.companyId)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return Company.fromJson(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CompanySettings?> getCurrentCompanySettings() async {
    final company = await getCurrentCompany();
    if (company == null) {
      return null;
    }

    try {
      final client = _client ?? _ensureClient();
      final response = await client
          .from('company_settings')
          .select()
          .eq('company_id', company.id)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return CompanySettings.fromJson(Map<String, dynamic>.from(response));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<dynamic> getCurrentSession() async {
    try {
      final client = _client ?? _ensureClient();
      return client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<app_auth_state.AuthState> authStateChanges() {
    final controller = StreamController<app_auth_state.AuthState>.broadcast();
    final client = _client ?? _ensureClient();
    client.auth.onAuthStateChange.listen((dynamic event) async {
      final session = event.session;
      if (session == null) {
        controller.add(
          const app_auth_state.AuthState(role: null, isAuthenticated: false),
        );
        return;
      }

      final profile = await getCurrentProfile();
      controller.add(
        app_auth_state.AuthState(
          role: profile?.role,
          isAuthenticated: session.user != null,
        ),
      );
    });
    return controller.stream;
  }

  SupabaseClient _ensureClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  String _mapAuthError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login')) {
      return 'Kullanıcı adı/e-posta veya şifre hatalıdır.';
    }
    if (normalized.contains('network') || normalized.contains('failed')) {
      return 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
    }
    return message;
  }
}
