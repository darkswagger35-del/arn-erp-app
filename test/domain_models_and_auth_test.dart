import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/core/auth/auth_provider.dart';
import 'package:arn_erp_app/core/auth/auth_repository.dart';
import 'package:arn_erp_app/core/errors/app_exception.dart';
import 'package:arn_erp_app/models/company.dart';
import 'package:arn_erp_app/models/company_settings.dart';
import 'package:arn_erp_app/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRole', () {
    test('parses JSON values and exposes Turkish labels', () {
      expect(AppRole.fromValue('admin'), AppRole.admin);
      expect(AppRole.fromValue('secretary'), AppRole.secretary);
      expect(AppRole.fromValue('technician'), AppRole.technician);
      expect(AppRole.admin.label, 'Yönetici');
      expect(AppRole.secretary.label, 'Sekreter');
      expect(AppRole.technician.label, 'Teknisyen');
      expect(() => AppRole.fromValue('invalid'), throwsArgumentError);
    });
  });

  group('Domain models', () {
    test('Company parses from JSON and copies values', () {
      final company = Company.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Arn Test',
        'legal_name': 'Arn Test A.Ş.',
        'phone': '0212 111 22 33',
        'email': 'info@example.com',
        'tax_number': '1111111111',
        'is_active': true,
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
      });

      expect(company.name, 'Arn Test');
      expect(company.isActive, isTrue);
      expect(company.copyWith(name: 'Arn Yeni').name, 'Arn Yeni');
    });

    test('UserProfile round trips to and from JSON', () {
      final profile = UserProfile(
        id: '22222222-2222-2222-2222-222222222222',
        companyId: '11111111-1111-1111-1111-111111111111',
        fullName: 'Ali Veli',
        phone: '0555 111 22 33',
        role: AppRole.admin,
        isActive: true,
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 2),
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.fullName, profile.fullName);
      expect(restored.role, AppRole.admin);
      expect(restored.toJson()['role'], 'admin');
    });

    test('CompanySettings exposes safe defaults', () {
      final settings = CompanySettings.fromJson({});

      expect(settings.currencyCode, 'TRY');
      expect(settings.localeCode, 'tr-TR');
      expect(settings.timezone, 'Europe/Istanbul');
      expect(settings.maintenanceReminderDays, 15);
    });
  });

  group('Auth repository', () {
    test('maps auth errors to Turkish messages', () async {
      final repository = AuthRepositoryImpl();

      await expectLater(
        repository.signIn(identifier: 'test@example.com', password: 'wrong'),
        throwsA(isA<AppException>()),
      );
    });

    test('mock role sign-in continues to work', () async {
      final repository = MockAuthRepository();
      final controller = AuthController(repository: repository);

      await controller.signIn(identifier: 'test@example.com', password: 'password');

      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.role, AppRole.admin);
    });
  });
}
