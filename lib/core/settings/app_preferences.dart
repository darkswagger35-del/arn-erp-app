import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesState {
  const AppPreferencesState({
    this.themeMode = ThemeMode.system,
    this.seedColorValue = 0xFF176B87,
    this.compactCards = false,
    this.rememberMe = true,
    this.savedIdentifier = '',
    this.onMyWayTemplate =
        'Merhaba {{musteri}}, ARN Su Arıtma teknik servis ekibiyim. Adresinize geliyorum.',
    this.appointmentTemplate =
        'Merhaba {{musteri}}, servis randevunuz {{tarih}} tarihinde oluşturulmuştur. İşlem: {{servis_turu}}.',
    this.serviceFormTitle = 'ARN SU ARITMA SERVİS FORMU',
    this.serviceFormFooter =
        'Hizmetimizi tercih ettiğiniz için teşekkür ederiz.',
    this.showPricesOnForm = true,
    this.showSignatureOnForm = true,
    this.isLoaded = false,
  });

  final ThemeMode themeMode;
  final int seedColorValue;
  final bool compactCards;
  final bool rememberMe;
  final String savedIdentifier;
  final String onMyWayTemplate;
  final String appointmentTemplate;
  final String serviceFormTitle;
  final String serviceFormFooter;
  final bool showPricesOnForm;
  final bool showSignatureOnForm;
  final bool isLoaded;

  AppPreferencesState copyWith({
    ThemeMode? themeMode,
    int? seedColorValue,
    bool? compactCards,
    bool? rememberMe,
    String? savedIdentifier,
    String? onMyWayTemplate,
    String? appointmentTemplate,
    String? serviceFormTitle,
    String? serviceFormFooter,
    bool? showPricesOnForm,
    bool? showSignatureOnForm,
    bool? isLoaded,
  }) {
    return AppPreferencesState(
      themeMode: themeMode ?? this.themeMode,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      compactCards: compactCards ?? this.compactCards,
      rememberMe: rememberMe ?? this.rememberMe,
      savedIdentifier: savedIdentifier ?? this.savedIdentifier,
      onMyWayTemplate: onMyWayTemplate ?? this.onMyWayTemplate,
      appointmentTemplate: appointmentTemplate ?? this.appointmentTemplate,
      serviceFormTitle: serviceFormTitle ?? this.serviceFormTitle,
      serviceFormFooter: serviceFormFooter ?? this.serviceFormFooter,
      showPricesOnForm: showPricesOnForm ?? this.showPricesOnForm,
      showSignatureOnForm: showSignatureOnForm ?? this.showSignatureOnForm,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class AppPreferencesController extends StateNotifier<AppPreferencesState> {
  AppPreferencesController() : super(const AppPreferencesState()) {
    load();
  }

  static const _themeKey = 'ui_theme_mode';
  static const _colorKey = 'ui_seed_color';
  static const _compactKey = 'ui_compact_cards';
  static const _rememberKey = 'auth_remember_me';
  static const _identifierKey = 'auth_saved_identifier';
  static const _onMyWayKey = 'message_on_my_way';
  static const _appointmentKey = 'message_appointment';
  static const _formTitleKey = 'service_form_title';
  static const _formFooterKey = 'service_form_footer';
  static const _formPricesKey = 'service_form_show_prices';
  static const _formSignatureKey = 'service_form_show_signature';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_themeKey) ?? 'system';
    final themeMode = ThemeMode.values.firstWhere(
      (item) => item.name == themeName,
      orElse: () => ThemeMode.system,
    );
    state = state.copyWith(
      themeMode: themeMode,
      seedColorValue: prefs.getInt(_colorKey) ?? state.seedColorValue,
      compactCards: prefs.getBool(_compactKey) ?? false,
      rememberMe: prefs.getBool(_rememberKey) ?? true,
      savedIdentifier: prefs.getString(_identifierKey) ?? '',
      onMyWayTemplate: prefs.getString(_onMyWayKey) ?? state.onMyWayTemplate,
      appointmentTemplate:
          prefs.getString(_appointmentKey) ?? state.appointmentTemplate,
      serviceFormTitle:
          prefs.getString(_formTitleKey) ?? state.serviceFormTitle,
      serviceFormFooter:
          prefs.getString(_formFooterKey) ?? state.serviceFormFooter,
      showPricesOnForm: prefs.getBool(_formPricesKey) ?? true,
      showSignatureOnForm: prefs.getBool(_formSignatureKey) ?? true,
      isLoaded: true,
    );
  }

  Future<void> updateAppearance({
    required ThemeMode themeMode,
    required int seedColorValue,
    required bool compactCards,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeMode.name);
    await prefs.setInt(_colorKey, seedColorValue);
    await prefs.setBool(_compactKey, compactCards);
    state = state.copyWith(
      themeMode: themeMode,
      seedColorValue: seedColorValue,
      compactCards: compactCards,
    );
  }

  Future<void> updateLoginPreference({
    required bool rememberMe,
    required String identifier,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_identifierKey, identifier.trim());
    } else {
      await prefs.remove(_identifierKey);
    }
    state = state.copyWith(
      rememberMe: rememberMe,
      savedIdentifier: rememberMe ? identifier.trim() : '',
    );
  }

  Future<void> updateMessages({
    required String onMyWayTemplate,
    required String appointmentTemplate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_onMyWayKey, onMyWayTemplate.trim());
    await prefs.setString(_appointmentKey, appointmentTemplate.trim());
    state = state.copyWith(
      onMyWayTemplate: onMyWayTemplate.trim(),
      appointmentTemplate: appointmentTemplate.trim(),
    );
  }

  Future<void> updateServiceForm({
    required String title,
    required String footer,
    required bool showPrices,
    required bool showSignature,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_formTitleKey, title.trim());
    await prefs.setString(_formFooterKey, footer.trim());
    await prefs.setBool(_formPricesKey, showPrices);
    await prefs.setBool(_formSignatureKey, showSignature);
    state = state.copyWith(
      serviceFormTitle: title.trim(),
      serviceFormFooter: footer.trim(),
      showPricesOnForm: showPrices,
      showSignatureOnForm: showSignature,
    );
  }
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferencesState>(
  (ref) => AppPreferencesController(),
);
