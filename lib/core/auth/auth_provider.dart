import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap/app_environment.dart';
import '../../models/company.dart';
import '../../models/user_profile.dart';
import '../errors/app_exception.dart';
import 'app_role.dart';
import 'auth_repository.dart';
import 'auth_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final environment = AppEnvironment.fromEnvironment();
  return environment.isConfigured ? AuthRepositoryImpl() : MockAuthRepository();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController({required this.repository}) : super(const AuthState());

  final AuthRepository repository;

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      status: AuthStatus.loading,
    );

    try {
      await repository.signIn(identifier: identifier, password: password);

      final profile = await repository.getCurrentProfile();
      if (profile == null) {
        await repository.signOut();
        throw const AppException('Kullanıcı profili bulunamadı.');
      }

      if (!profile.isActive) {
        await repository.signOut();
        throw const AppException(
          'Bu kullanıcı hesabı pasif durumdadır. Yöneticinizle iletişime geçin.',
        );
      }

      final company = await repository.getCurrentCompany();
      if (company == null || !company.isActive) {
        await repository.signOut();
        throw const AppException('Şirket hesabı pasif durumdadır.');
      }

      final validRoles = const {'admin', 'manager', 'secretary', 'technician'};
      if (!validRoles.contains(profile.role.value)) {
        await repository.signOut();
        throw const AppException('Kullanıcı rolü geçersizdir.');
      }

      final session = await repository.getCurrentSession();
      final user = session?.user;

      state = state.copyWith(
        role: profile.role,
        user: user,
        profile: profile,
        company: company,
        isAuthenticated: true,
        isLoading: false,
        errorMessage: null,
        status: AuthStatus.authenticated,
      );
    } on AppException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.message,
        status: AuthStatus.error,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Bağlantı kurulamadı. Lütfen tekrar deneyin.',
        status: AuthStatus.error,
      );
    }
  }

  Future<void> restoreSession() async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      status: AuthStatus.loading,
    );

    try {
      final profile = await repository.getCurrentProfile();
      if (profile == null) {
        await repository.signOut();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      if (!profile.isActive) {
        await repository.signOut();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      final company = await repository.getCurrentCompany();
      if (company == null || !company.isActive) {
        await repository.signOut();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      final validRoles = const {'admin', 'manager', 'secretary', 'technician'};
      if (!validRoles.contains(profile.role.value)) {
        await repository.signOut();
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      final session = await repository.getCurrentSession();
      final user = session?.user;

      state = state.copyWith(
        role: profile.role,
        user: user,
        profile: profile,
        company: company,
        isAuthenticated: true,
        isLoading: false,
        errorMessage: null,
        status: AuthStatus.authenticated,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Bağlantı kurulamadı. Lütfen tekrar deneyin.',
        status: AuthStatus.error,
      );
    }
  }

  void signInForDevelopment(AppRole role) {
    final roleName = switch (role) {
      AppRole.admin => 'Yönetici',
      AppRole.manager => 'Yönetici',
      AppRole.secretary => 'Sekreter',
      AppRole.technician => 'Teknisyen',
    };

    state = AuthState(
      role: role,
      profile: UserProfile(
        id: 'development-${role.value}',
        companyId: 'development-company',
        fullName: '$roleName Test Kullanıcısı',
        role: role,
        isActive: true,
      ),
      company: const Company(
        id: 'development-company',
        name: 'ARN ERP Geliştirme',
        isActive: true,
      ),
      isAuthenticated: true,
      isLoading: false,
      status: AuthStatus.authenticated,
    );
  }

  Future<void> signOut() async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      status: AuthStatus.loading,
    );

    try {
      await repository.signOut();
      state = const AuthState(status: AuthStatus.unauthenticated);
    } on AppException catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: error.message,
        status: AuthStatus.error,
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Çıkış sırasında bir hata oluştu.',
        status: AuthStatus.error,
      );
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final repository = ref.watch(authRepositoryProvider);
    return AuthController(repository: repository);
  },
);
