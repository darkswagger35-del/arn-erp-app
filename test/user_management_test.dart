import 'package:arn_erp_app/app/router.dart';
import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/core/errors/app_exception.dart';
import 'package:arn_erp_app/features/user_management/data/user_management_repository.dart';
import 'package:arn_erp_app/features/user_management/data/user_management_repository_impl.dart';
import 'package:arn_erp_app/features/user_management/domain/create_user_request.dart';
import 'package:arn_erp_app/features/user_management/domain/user_management_user.dart';
import 'package:arn_erp_app/features/user_management/presentation/user_management_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class MockUserManagementRepository implements UserManagementRepository {
  @override
  Future<List<UserManagementUser>> listUsers() async {
    return const [
      UserManagementUser(
        id: '1',
        companyId: 'c1',
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        phone: '0555',
        role: AppRole.secretary,
        isActive: true,
      ),
    ];
  }

  @override
  Future<void> createUser(CreateUserRequest request) async {}

  @override
  Future<void> updateUser({required String userId, String? fullName, String? phone, AppRole? role, bool? isActive}) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}
}

class RecordingUserManagementRepository implements UserManagementRepository {
  int createCalls = 0;
  int updateCalls = 0;
  int resetCalls = 0;
  bool throwOnReset = false;

  @override
  Future<List<UserManagementUser>> listUsers() async {
    return [
      const UserManagementUser(
        id: '1',
        companyId: 'c1',
        fullName: 'Ali Veli',
        email: 'ali@example.com',
        phone: '0555',
        role: AppRole.secretary,
        isActive: true,
      ),
      if (createCalls > 0)
        const UserManagementUser(
          id: '2',
          companyId: 'c1',
          fullName: 'Ayşe',
          email: 'ayse@example.com',
          phone: '0555',
          role: AppRole.technician,
          isActive: true,
        ),
    ];
  }

  @override
  Future<void> createUser(CreateUserRequest request) async {
    createCalls += 1;
  }

  @override
  Future<void> updateUser({required String userId, String? fullName, String? phone, AppRole? role, bool? isActive}) async {
    updateCalls += 1;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resetCalls += 1;
    if (throwOnReset) {
      throw AppException('Şifre sıfırlama iptal edildi.');
    }
  }
}

void main() {
  group('UserManagementController', () {
    test('rejects empty email and short password', () async {
      final controller = UserManagementController(repository: MockUserManagementRepository());

      await controller.createUser(
        fullName: '  ',
        email: '',
        phone: '',
        role: AppRole.secretary,
        password: '123',
        passwordConfirmation: '123',
        isActive: true,
      );

      expect(controller.state.errorMessage, contains('E-posta'));
      expect(controller.state.isSaving, isFalse);
    });

    test('rejects empty full name', () async {
      final controller = UserManagementController(repository: MockUserManagementRepository());

      await controller.createUser(
        fullName: '   ',
        email: 'new@example.com',
        phone: '',
        role: AppRole.secretary,
        password: '123456',
        passwordConfirmation: '123456',
        isActive: true,
      );

      expect(controller.state.errorMessage, contains('Ad soyad'));
    });

    test('rejects invalid email format', () async {
      final controller = UserManagementController(repository: MockUserManagementRepository());

      await controller.createUser(
        fullName: 'Ali',
        email: 'ali-example.com',
        phone: '',
        role: AppRole.secretary,
        password: '123456',
        passwordConfirmation: '123456',
        isActive: true,
      );

      expect(controller.state.errorMessage, contains('Geçerli'));
    });

    test('rejects mismatched password confirmation', () async {
      final controller = UserManagementController(repository: MockUserManagementRepository());

      await controller.createUser(
        fullName: 'Ali',
        email: 'ali@example.com',
        phone: '',
        role: AppRole.secretary,
        password: '123456',
        passwordConfirmation: '654321',
        isActive: true,
      );

      expect(controller.state.errorMessage, contains('eşleş'));
    });

    test('rejects duplicate email addresses in current user list', () async {
      final controller = UserManagementController(repository: MockUserManagementRepository());
      await controller.loadUsers();

      await controller.createUser(
        fullName: 'Ali',
        email: 'ali@example.com',
        phone: '',
        role: AppRole.secretary,
        password: '123456',
        passwordConfirmation: '123456',
        isActive: true,
      );

      expect(controller.state.errorMessage, contains('zaten kullanılıyor'));
    });

    test('maps roles to Turkish labels', () {
      expect(AppRole.secretary.label, 'Sekreter');
      expect(AppRole.technician.label, 'Teknisyen');
      expect(AppRole.manager.label, 'Yönetici');
    });

    test('router should allow manager access', () {
      expect(AppRole.fromValue('manager').value, 'manager');
      expect(AppRole.fromValue('admin').value, 'admin');
    });

    test('router denies secretary and technician access to the manager users route', () {
      expect(
        resolveRouteRedirect(
          matchedLocation: '/manager/users',
          currentRole: AppRole.secretary,
          isAuthenticated: true,
          isLoginRoute: false,
        ),
        '/secretary-dashboard',
      );
      expect(
        resolveRouteRedirect(
          matchedLocation: '/manager/users',
          currentRole: AppRole.technician,
          isAuthenticated: true,
          isLoginRoute: false,
        ),
        '/technician-dashboard',
      );
    });

    test('create user repository does not include company_id in the request body', () async {
      Map<String, dynamic>? capturedBody;
      final repository = UserManagementRepositoryImpl(
        invoker: (functionName, {body}) async {
          capturedBody = body;
          return {'success': true};
        },
      );

      await repository.createUser(
        CreateUserRequest(
          fullName: 'Aylin Demir',
          email: 'aylin@example.com',
          phone: '0555',
          role: AppRole.secretary,
          password: '123456',
          passwordConfirmation: '123456',
          isActive: true,
        ),
      );

      expect(capturedBody, isNotNull);
      expect(capturedBody, isA<Map<String, dynamic>>());
      expect(capturedBody!.containsKey('company_id'), isFalse);
      expect(capturedBody!['email'], 'aylin@example.com');
    });

    test('create flow refreshes the user list after a successful create', () async {
      final repository = RecordingUserManagementRepository();
      final controller = UserManagementController(repository: repository);

      await controller.createUser(
        fullName: 'Ayşe',
        email: 'ayse@example.com',
        phone: '0555',
        role: AppRole.technician,
        password: '123456',
        passwordConfirmation: '123456',
        isActive: true,
      );

      expect(repository.createCalls, 1);
      expect(controller.state.users.length, 2);
      expect(controller.state.successMessage, contains('Kullanıcı oluşturuldu'));
    });

    test('update flow refreshes the user list after a successful update', () async {
      final repository = RecordingUserManagementRepository();
      final controller = UserManagementController(repository: repository);

      await controller.updateUser(userId: '1', isActive: false);

      expect(repository.updateCalls, 1);
      expect(controller.state.successMessage, contains('güncellendi'));
    });

    test('password reset errors are surfaced as safe Turkish messages', () async {
      final repository = RecordingUserManagementRepository()..throwOnReset = true;
      final controller = UserManagementController(repository: repository);

      await controller.sendPasswordReset('ali@example.com');

      expect(controller.state.errorMessage, contains('Şifre sıfırlama'));
      expect(controller.state.isSaving, isFalse);
    });
  });
}
