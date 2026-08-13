import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arn_erp_app/app/router.dart';
import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/features/settings/data/settings_repository.dart';
import 'package:arn_erp_app/features/settings/domain/settings_model.dart';
import 'package:arn_erp_app/features/settings/presentation/settings_controller.dart';

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({this.initialSettings, this.throwOnSave = false});

  CompanySettingsModel? initialSettings;
  bool throwOnSave;
  int saveCalls = 0;
  int uploadCalls = 0;
  CompanySettingsModel? savedSettings;
  Uint8List? uploadedBytes;
  String? uploadedFileName;
  Future<void> Function(CompanySettingsModel settings)? saveHook;

  @override
  Future<CompanySettingsModel> loadSettings() async {
    return initialSettings ?? const CompanySettingsModel(companyId: 'company-1', companyName: 'Test Firma');
  }

  @override
  Future<void> saveSettings(CompanySettingsModel settings) async {
    saveCalls += 1;
    savedSettings = settings;
    if (throwOnSave) {
      throw Exception('save failed');
    }
    if (saveHook != null) {
      await saveHook!(settings);
    }
  }

  @override
  Future<String> uploadLogo({required Uint8List bytes, required String fileName}) async {
    uploadCalls += 1;
    uploadedBytes = bytes;
    uploadedFileName = fileName;
    return 'https://example.com/logo.png';
  }
}

void main() {
  test('manager can access settings route', () {
    final redirect = resolveRouteRedirect(
      matchedLocation: '/manager/settings',
      currentRole: AppRole.manager,
      isAuthenticated: true,
      isLoginRoute: false,
    );

    expect(redirect, isNull);
  });

  test('secretary is redirected away from manager settings', () {
    final redirect = resolveRouteRedirect(
      matchedLocation: '/manager/settings',
      currentRole: AppRole.secretary,
      isAuthenticated: true,
      isLoginRoute: false,
    );

    expect(redirect, '/secretary-dashboard');
  });

  test('technician is redirected away from manager settings', () {
    final redirect = resolveRouteRedirect(
      matchedLocation: '/manager/settings',
      currentRole: AppRole.technician,
      isAuthenticated: true,
      isLoginRoute: false,
    );

    expect(redirect, '/technician-dashboard');
  });

  test('controller loads settings from repository', () async {
    final repository = FakeSettingsRepository(
      initialSettings: const CompanySettingsModel(companyId: 'company-1', companyName: 'Test Firma'),
    );
    final controller = SettingsController(repository: repository);

    await controller.loadSettings();

    expect(controller.state.settings?.companyName, 'Test Firma');
    expect(controller.state.isLoading, isFalse);
  });

  test('controller saves settings and surfaces success message', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    await controller.saveSettings(const CompanySettingsModel(companyId: 'company-1', companyName: 'Yeni Firma'));

    expect(repository.saveCalls, 1);
    expect(repository.savedSettings?.companyName, 'Yeni Firma');
    expect(controller.state.successMessage, 'Ayarlar başarıyla kaydedildi.');
  });

  test('controller blocks duplicate saves', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    repository.saveHook = (settings) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    };

    final first = controller.saveSettings(const CompanySettingsModel(companyId: 'company-1', companyName: 'A'));
    final second = controller.saveSettings(const CompanySettingsModel(companyId: 'company-1', companyName: 'B'));

    await Future.wait([first, second]);

    expect(repository.saveCalls, 1);
  });

  test('controller rejects invalid maintenance values', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    await controller.saveSettings(const CompanySettingsModel(companyId: 'company-1', companyName: 'Firma', maintenanceReminderMonths: 1));

    expect(repository.saveCalls, 0);
    expect(controller.state.errorMessage, 'Bakım süresi yalnızca 3, 6, 12 veya 24 ay olabilir.');
  });

  test('controller rejects oversized logo uploads', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    final bytes = Uint8List(2 * 1024 * 1024 + 1);
    final result = await controller.uploadLogo(bytes: bytes, fileName: 'logo.png');

    expect(result, isNull);
    expect(repository.uploadCalls, 0);
    expect(controller.state.errorMessage, 'Logo dosyası 2 MB\'dan büyük olamaz.');
  });

  test('controller rejects invalid logo extension', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    final result = await controller.uploadLogo(bytes: Uint8List.fromList([1, 2, 3]), fileName: 'logo.gif');

    expect(result, isNull);
    expect(repository.uploadCalls, 0);
    expect(controller.state.errorMessage, 'Geçersiz logo türü. Yalnızca PNG, JPG veya JPEG dosyaları yüklenebilir.');
  });
}
