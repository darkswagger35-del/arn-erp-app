import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arn_erp_app/features/settings/data/settings_repository.dart';
import 'package:arn_erp_app/features/settings/domain/settings_model.dart';
import 'package:arn_erp_app/features/settings/presentation/settings_controller.dart';

class FakeSettingsRepository implements SettingsRepository {
  CompanySettingsModel? loadedSettings;
  bool saveCalled = false;
  String? uploadedUrl;

  @override
  Future<CompanySettingsModel> loadSettings() async {
    return loadedSettings ?? const CompanySettingsModel(companyId: 'company-1', companyName: 'Test Firma');
  }

  @override
  Future<void> saveSettings(CompanySettingsModel settings) async {
    saveCalled = true;
    loadedSettings = settings;
  }

  @override
  Future<String> uploadLogo({required Uint8List bytes, required String fileName}) async {
    uploadedUrl = 'https://example.com/logo.png';
    return uploadedUrl!;
  }
}

void main() {
  test('loads and saves settings', () async {
    final repository = FakeSettingsRepository();
    final controller = SettingsController(repository: repository);

    await controller.loadSettings();
    expect(controller.state.settings?.companyName, 'Test Firma');

    await controller.saveSettings(const CompanySettingsModel(companyId: 'company-1', companyName: 'Yeni Firma'));

    expect(repository.saveCalled, isTrue);
    expect(controller.state.successMessage, 'Ayarlar başarıyla kaydedildi.');
  });
}
