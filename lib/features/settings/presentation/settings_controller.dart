import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../data/settings_repository.dart';
import '../domain/settings_model.dart';

class SettingsState {
  const SettingsState({
    this.settings,
    this.isLoading = false,
    this.isSaving = false,
    this.isUploadingLogo = false,
    this.errorMessage,
    this.successMessage,
  });

  final CompanySettingsModel? settings;
  final bool isLoading;
  final bool isSaving;
  final bool isUploadingLogo;
  final String? errorMessage;
  final String? successMessage;

  SettingsState copyWith({
    CompanySettingsModel? settings,
    bool? isLoading,
    bool? isSaving,
    bool? isUploadingLogo,
    String? errorMessage,
    String? successMessage,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isUploadingLogo: isUploadingLogo ?? this.isUploadingLogo,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsController({required this.repository});

  final SettingsRepository repository;
  SettingsState _state = const SettingsState();

  SettingsState get state => _state;

  Future<void> loadSettings() async {
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      final settings = await repository.loadSettings();
      _state = _state.copyWith(
        settings: settings,
        isLoading: false,
        errorMessage: null,
      );
    } on AppException catch (error) {
      _state = _state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Ayarlar yüklenemedi.',
      );
    }
    notifyListeners();
  }

  Future<void> saveSettings(CompanySettingsModel settings) async {
    if (_state.isSaving || _state.isUploadingLogo) {
      return;
    }

    final validationError = _validateSettings(settings);
    if (validationError != null) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: validationError,
        successMessage: null,
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      await repository.saveSettings(settings);
      _state = _state.copyWith(
        settings: settings,
        isSaving: false,
        successMessage: 'Ayarlar başarıyla kaydedildi.',
      );
    } on AppException catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Ayarlar kaydedilemedi.',
      );
    }
    notifyListeners();
  }

  Future<String?> uploadLogo({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (_state.isUploadingLogo || _state.isSaving) {
      return null;
    }

    final validationError = _validateLogo(bytes, fileName);
    if (validationError != null) {
      _state = _state.copyWith(
        isUploadingLogo: false,
        errorMessage: validationError,
        successMessage: null,
      );
      notifyListeners();
      return null;
    }

    _state = _state.copyWith(isUploadingLogo: true, errorMessage: null);
    notifyListeners();

    try {
      final url = await repository.uploadLogo(bytes: bytes, fileName: fileName);
      final currentSettings = _state.settings?.copyWith(logoUrl: url);
      _state = _state.copyWith(
        settings: currentSettings,
        isUploadingLogo: false,
        successMessage: null,
      );
      return url;
    } on AppException catch (error) {
      _state = _state.copyWith(
        isUploadingLogo: false,
        errorMessage: error.message,
      );
    } catch (_) {
      _state = _state.copyWith(
        isUploadingLogo: false,
        errorMessage: 'Logo yüklenemedi.',
      );
    }
    notifyListeners();
    return null;
  }

  Future<void> deleteLogo() async {
    if (_state.isUploadingLogo || _state.isSaving) return;
    _state = _state.copyWith(isUploadingLogo: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await repository.deleteLogo();
      final current = _state.settings;
      _state = _state.copyWith(
        settings: current?.copyWith(logoUrl: ''),
        isUploadingLogo: false,
        successMessage: 'Logo silindi.',
      );
    } on AppException catch (error) {
      _state = _state.copyWith(isUploadingLogo: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(isUploadingLogo: false, errorMessage: 'Logo silinemedi.');
    }
    notifyListeners();
  }

  String? _validateSettings(CompanySettingsModel settings) {
    if (!const {3, 6, 12, 24}.contains(settings.maintenanceReminderMonths)) {
      return 'Bakım süresi yalnızca 3, 6, 12 veya 24 ay olabilir.';
    }
    if (settings.companyName.trim().isEmpty) {
      return 'Firma adı zorunludur.';
    }
    return null;
  }

  String? _validateLogo(Uint8List bytes, String fileName) {
    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      return 'Logo dosyası 2 MB\'dan büyük olamaz.';
    }

    final lowerName = fileName.toLowerCase();
    if (!lowerName.endsWith('.png') &&
        !lowerName.endsWith('.jpg') &&
        !lowerName.endsWith('.jpeg')) {
      return 'Geçersiz logo türü. Yalnızca PNG, JPG veya JPEG dosyaları yüklenebilir.';
    }

    return null;
  }
}
