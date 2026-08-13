import '../../models/company.dart';
import '../../models/company_settings.dart';
import '../../models/user_profile.dart';
import '../errors/app_exception.dart';
import 'app_role.dart';
import 'auth_state.dart';

export '../../features/auth/data/auth_repository_impl.dart';

abstract class AuthRepository {
  Future<void> signIn({required String identifier, required String password});
  Future<void> signOut();
  Future<UserProfile?> getCurrentProfile();
  Future<Company?> getCurrentCompany();
  Future<CompanySettings?> getCurrentCompanySettings();
  Future<dynamic> getCurrentSession();
  Stream<AuthState> authStateChanges();
}

class MockAuthRepository implements AuthRepository {
  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    if (identifier.isEmpty || password.isEmpty) {
      throw const AppException('E-posta veya şifre hatalıdır.');
    }

    if (identifier == 'test@example.com' && password == 'wrong') {
      throw const AppException('E-posta veya şifre hatalıdır.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<UserProfile?> getCurrentProfile() async {
    return const UserProfile(
      id: 'mock-profile-id',
      companyId: 'mock-company-id',
      fullName: 'Mock Kullanıcı',
      role: AppRole.admin,
      isActive: true,
    );
  }

  @override
  Future<Company?> getCurrentCompany() async {
    return const Company(id: 'mock-company-id', name: 'Mock Şirket');
  }

  @override
  Future<CompanySettings?> getCurrentCompanySettings() async {
    return const CompanySettings(
      id: 'mock-settings-id',
      companyId: 'mock-company-id',
    );
  }

  @override
  Future<dynamic> getCurrentSession() async {
    return null;
  }

  @override
  Stream<AuthState> authStateChanges() async* {
    yield const AuthState(role: AppRole.admin, isAuthenticated: true);
  }
}
