import 'dart:typed_data';

import '../domain/settings_model.dart';

abstract class SettingsRepository {
  Future<CompanySettingsModel> loadSettings();
  Future<void> saveSettings(CompanySettingsModel settings);
  Future<void> deleteLogo();
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String fileName,
  });
}
