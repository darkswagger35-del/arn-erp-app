import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_provider.dart';

class CompanyAppSettings {
  const CompanyAppSettings({
    required this.companyId,
    this.maintenanceReminderDays = 10,
    this.showOverdueMaintenances = true,
    this.hideProductsWithoutMaintenance = true,
    this.calculateMaintenanceFromProduct = true,
    this.onlyLatestProductMaintenance = true,
    this.autoDecreaseStockOnService = true,
    this.autoAddNewProductToMainWarehouse = true,
    this.defaultInitialStock = 0,
    this.allowNegativeStock = false,
    this.criticalStockNotifications = true,
    this.allowTechnicianCustomerEdit = true,
    this.allowTechnicianHistoryEdit = false,
    this.requirePaymentToCompleteService = false,
    this.allowPartialPayment = true,
    this.defaultPaymentMethod = 'cash',
    this.enabledPaymentMethods = const ['cash', 'card', 'transfer', 'open_account'],
    this.technicianAssignmentNotifications = true,
    this.maintenanceNotifications = true,
    this.onMyWayTemplate =
        'Merhaba {{musteri}}, ARN Su Arıtma teknik servis ekibiyim. Adresinize geliyorum.',
    this.appointmentTemplate =
        'Merhaba {{musteri}}, {{tarih}} tarihli servis randevunuz oluşturulmuştur. İşlem: {{servis_turu}}. Teknik personel: {{teknisyen}}.',
    this.serviceCompletedTemplate =
        'Merhaba {{musteri}}, servis işleminiz tamamlanmıştır. Tutar: {{tutar}}.',
    this.serviceFormTitle = 'ARN SU ARITMA SERVİS FORMU',
    this.serviceFormFooter =
        'Hizmetimizi tercih ettiğiniz için teşekkür ederiz.',
    this.showPricesOnForm = true,
    this.showSignatureOnForm = true,
    this.showCustomerAddressOnForm = true,
    this.enabledServiceTypes = const [
      'new_installation',
      'filter_change',
      'fault',
      'other',
    ],
    this.permissions = defaultPermissions,
    this.serviceRules = defaultServiceRules,
    this.customerRules = defaultCustomerRules,
    this.panelVisibility = defaultPanelVisibility,
    this.backupPolicy = defaultBackupPolicy,
    this.serviceFormConfig = defaultServiceFormConfig,
  });

  final String companyId;
  final int maintenanceReminderDays;
  final bool showOverdueMaintenances;
  final bool hideProductsWithoutMaintenance;
  final bool calculateMaintenanceFromProduct;
  final bool onlyLatestProductMaintenance;
  final bool autoDecreaseStockOnService;
  final bool autoAddNewProductToMainWarehouse;
  final double defaultInitialStock;
  final bool allowNegativeStock;
  final bool criticalStockNotifications;
  final bool allowTechnicianCustomerEdit;
  final bool allowTechnicianHistoryEdit;
  final bool requirePaymentToCompleteService;
  final bool allowPartialPayment;
  final String defaultPaymentMethod;
  final List<String> enabledPaymentMethods;
  final bool technicianAssignmentNotifications;
  final bool maintenanceNotifications;
  final String onMyWayTemplate;
  final String appointmentTemplate;
  final String serviceCompletedTemplate;
  final String serviceFormTitle;
  final String serviceFormFooter;
  final bool showPricesOnForm;
  final bool showSignatureOnForm;
  final bool showCustomerAddressOnForm;
  final List<String> enabledServiceTypes;

  /// Uygulama seviyesindeki rol izinleri. Yönetici her zaman tam yetkilidir.
  final Map<String, bool> permissions;

  /// Servis akışının davranış kuralları. JSONB olarak saklanır; yeni kural
  /// eklerken veritabanı şemasını büyütmeden geriye uyumlu kalır.
  final Map<String, dynamic> serviceRules;

  /// Müşteri kayıt ve bakım davranışları.
  final Map<String, dynamic> customerRules;

  /// Yönetici / sekreter / tekniker ana panel görünürlüğü.
  final Map<String, dynamic> panelVisibility;

  /// Yedek saklama politikası. Otomatik zamanlayıcı değil; manuel yedeklerin
  /// kaç kopya tutulacağını ve varsayılan davranışı yönetir.
  final Map<String, dynamic> backupPolicy;

  /// Servis formunda hangi bölümlerin görüneceği, zorunlulukları ve sırası.
  final Map<String, dynamic> serviceFormConfig;

  static const Map<String, bool> defaultPermissions = {
    'secretary_view_customers': true,
    'secretary_edit_customers': true,
    'secretary_create_service': true,
    'secretary_edit_service': true,
    'secretary_edit_completed_service': true,
    'secretary_view_prices': true,
    'secretary_view_payments': false,
    'secretary_view_stock': false,
    'secretary_excel_transfer': false,
    'technician_view_customers': true,
    'technician_edit_customers': true,
    'technician_create_service': false,
    'technician_edit_service': false,
    'technician_edit_completed_service': false,
    'technician_view_prices': true,
    'technician_view_payments': true,
    'technician_view_stock': true,
    'technician_excel_transfer': false,
  };

  static const Map<String, dynamic> defaultServiceRules = {
    'appointment_time_enabled': true,
    'completed_service_editable': true,
    'technician_can_change_products': true,
    'technician_can_change_price': false,
    'technician_can_collect_payment': true,
    'require_work_description': true,
    'require_product_for_filter_change': true,
    'require_payment_status': true,
    'allow_unassigned_service': true,
    // V61: Kart komisyon oranlarını yalnız yönetici ayarlar. Tekniker yalnız
    // taksit seçer; oran buradan otomatik okunur.
    'card_commission_rates': <String, dynamic>{
      '1': 0.0,
      '2': 0.0,
      '3': 0.0,
      '4': 0.0,
      '5': 0.0,
      '6': 0.0,
      '9': 0.0,
      '12': 0.0,
    },
  };

  static const Map<String, dynamic> defaultCustomerRules = {
    'duplicate_phone_check': true,
    'phone_required': true,
    'city_required': true,
    'district_required': true,
    'address_required': true,
    'email_visible': false,
  };

  static const Map<String, dynamic> defaultPanelVisibility = {
    'admin': {
      'summary': true,
      'technician_performance': true,
      'secretary_performance': true,
      'today_schedule': true,
      'recent_payments': true,
      'quick_access': true,
    },
    'secretary': {
      'metrics': true,
      'today_jobs': true,
      'latest_leads': true,
      'follow_up': true,
      'upcoming_maintenance': true,
      'quick_actions': true,
      'performance': true,
    },
    'technician': {
      'metrics': true,
      'morning_preparation': true,
      'performance': true,
      'products': true,
      'jobs': true,
    },
  };


  static const Map<String, dynamic> defaultServiceFormConfig = {
    'show_phone': true,
    'show_address': true,
    'show_service_type': true,
    'show_technician': true,
    'show_completed_at': true,
    'show_description': true,
    'show_completion_note': true,
    'show_products': true,
    'show_prices': true,
    'show_customer_signature': true,
    'show_technician_signature': true,
    'show_tds_in': false,
    'show_tds_out': false,
    'show_tank_pressure': false,
    'required_completion_note': false,
    'required_customer_signature': false,
    'section_order': [
      'customer',
      'service',
      'description',
      'products',
      'total',
      'signatures',
    ],
    'custom_fields': <dynamic>[],
  };

  static const Map<String, dynamic> defaultBackupPolicy = {
    'keep_count': 14,
    'include_notifications': false,
    'include_audit_logs': false,
  };

  static const _defaults = CompanyAppSettings(companyId: '');

  bool permission(String key, {bool fallback = false}) =>
      permissions[key] ?? fallback;

  bool serviceRule(String key, {bool fallback = false}) =>
      _boolValue(serviceRules[key], fallback);

  double cardCommissionRate(int installments) {
    final raw = serviceRules['card_commission_rates'];
    if (raw is Map) {
      final value = raw[installments.toString()];
      if (value is num) return value.toDouble().clamp(0, 100).toDouble();
      final parsed = double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
      if (parsed != null) return parsed.clamp(0, 100).toDouble();
    }
    return 0;
  }

  bool customerRule(String key, {bool fallback = false}) =>
      _boolValue(customerRules[key], fallback);

  bool panelVisible(
    String role,
    String key, {
    bool fallback = true,
  }) {
    final raw = panelVisibility[role];
    if (raw is Map) {
      return _boolValue(raw[key], fallback);
    }
    return fallback;
  }

  Map<String, dynamic> get appearanceConfig {
    final raw = panelVisibility['_appearance'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  String appearanceString(String key, {required String fallback}) {
    final value = appearanceConfig[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  bool appearanceBool(String key, {bool fallback = false}) =>
      _boolValue(appearanceConfig[key], fallback);

  int get backupKeepCount {
    final raw = backupPolicy['keep_count'];
    final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return (value ?? 14).clamp(1, 50).toInt();
  }

  factory CompanyAppSettings.fromMap(
    Map<String, dynamic> map, {
    required String companyId,
  }) {
    final technicianEdit =
        map['allow_technician_customer_edit'] as bool? ?? true;
    final technicianHistoryEdit =
        map['allow_technician_history_edit'] as bool? ?? false;

    final permissions = _mergedBoolMap(
      defaultPermissions,
      map['permissions'],
    );
    if (map['permissions'] == null) {
      permissions['technician_edit_customers'] = technicianEdit;
      permissions['technician_edit_completed_service'] = technicianHistoryEdit;
    }

    return CompanyAppSettings(
      companyId: companyId,
      maintenanceReminderDays:
          (map['maintenance_reminder_days'] as num?)?.toInt() ?? 10,
      showOverdueMaintenances:
          map['show_overdue_maintenances'] as bool? ?? true,
      hideProductsWithoutMaintenance:
          map['hide_products_without_maintenance'] as bool? ?? true,
      calculateMaintenanceFromProduct:
          map['calculate_maintenance_from_product'] as bool? ?? true,
      onlyLatestProductMaintenance:
          map['only_latest_product_maintenance'] as bool? ?? true,
      autoDecreaseStockOnService:
          map['auto_decrease_stock_on_service'] as bool? ?? true,
      autoAddNewProductToMainWarehouse:
          map['auto_add_new_product_to_main_warehouse'] as bool? ?? true,
      defaultInitialStock:
          (map['default_initial_stock'] as num?)?.toDouble() ?? 0,
      allowNegativeStock: map['allow_negative_stock'] as bool? ?? false,
      criticalStockNotifications:
          map['critical_stock_notifications'] as bool? ?? true,
      allowTechnicianCustomerEdit: technicianEdit,
      allowTechnicianHistoryEdit: technicianHistoryEdit,
      requirePaymentToCompleteService:
          map['require_payment_to_complete_service'] as bool? ?? false,
      allowPartialPayment: map['allow_partial_payment'] as bool? ?? true,
      defaultPaymentMethod:
          map['default_payment_method']?.toString() ?? 'cash',
      enabledPaymentMethods: List<String>.from(
        map['enabled_payment_methods'] as List? ??
            _defaults.enabledPaymentMethods,
      ),
      technicianAssignmentNotifications:
          map['technician_assignment_notifications'] as bool? ?? true,
      maintenanceNotifications:
          map['maintenance_notifications'] as bool? ?? true,
      onMyWayTemplate:
          map['on_my_way_template']?.toString() ?? _defaults.onMyWayTemplate,
      appointmentTemplate: map['appointment_template']?.toString() ??
          _defaults.appointmentTemplate,
      serviceCompletedTemplate:
          map['service_completed_template']?.toString() ??
              _defaults.serviceCompletedTemplate,
      serviceFormTitle:
          map['service_form_title']?.toString() ?? _defaults.serviceFormTitle,
      serviceFormFooter:
          map['service_form_footer']?.toString() ?? _defaults.serviceFormFooter,
      showPricesOnForm: map['show_prices_on_form'] as bool? ?? true,
      showSignatureOnForm: map['show_signature_on_form'] as bool? ?? true,
      showCustomerAddressOnForm:
          map['show_customer_address_on_form'] as bool? ?? true,
      enabledServiceTypes: List<String>.from(
        map['enabled_service_types'] as List? ?? _defaults.enabledServiceTypes,
      ),
      permissions: permissions,
      serviceRules: _mergedDynamicMap(
        defaultServiceRules,
        map['service_rules'],
      ),
      customerRules: _mergedDynamicMap(
        defaultCustomerRules,
        map['customer_rules'],
      ),
      panelVisibility: _mergedNestedMap(
        defaultPanelVisibility,
        map['panel_visibility'],
      ),
      backupPolicy: _mergedDynamicMap(
        defaultBackupPolicy,
        map['backup_policy'],
      ),
      serviceFormConfig: _mergedDynamicMap(
        defaultServiceFormConfig,
        map['service_form_config'],
      ),
    );
  }

  Map<String, dynamic> toMap() {
    final technicianEdit =
        permissions['technician_edit_customers'] ?? allowTechnicianCustomerEdit;
    final technicianHistoryEdit =
        permissions['technician_edit_completed_service'] ??
            allowTechnicianHistoryEdit;

    return {
      'company_id': companyId,
      'maintenance_reminder_days': maintenanceReminderDays.clamp(1, 365),
      'show_overdue_maintenances': showOverdueMaintenances,
      'hide_products_without_maintenance': hideProductsWithoutMaintenance,
      'calculate_maintenance_from_product': calculateMaintenanceFromProduct,
      'only_latest_product_maintenance': onlyLatestProductMaintenance,
      'auto_decrease_stock_on_service': autoDecreaseStockOnService,
      'auto_add_new_product_to_main_warehouse':
          autoAddNewProductToMainWarehouse,
      'default_initial_stock': defaultInitialStock < 0 ? 0 : defaultInitialStock,
      'allow_negative_stock': allowNegativeStock,
      'critical_stock_notifications': criticalStockNotifications,
      'allow_technician_customer_edit': technicianEdit,
      'allow_technician_history_edit': technicianHistoryEdit,
      'require_payment_to_complete_service': requirePaymentToCompleteService,
      'allow_partial_payment': allowPartialPayment,
      'default_payment_method': defaultPaymentMethod,
      'enabled_payment_methods': enabledPaymentMethods,
      'technician_assignment_notifications':
          technicianAssignmentNotifications,
      'maintenance_notifications': maintenanceNotifications,
      'on_my_way_template': onMyWayTemplate.trim(),
      'appointment_template': appointmentTemplate.trim(),
      'service_completed_template': serviceCompletedTemplate.trim(),
      'service_form_title': serviceFormTitle.trim(),
      'service_form_footer': serviceFormFooter.trim(),
      'show_prices_on_form': showPricesOnForm,
      'show_signature_on_form': showSignatureOnForm,
      'show_customer_address_on_form': showCustomerAddressOnForm,
      'enabled_service_types': enabledServiceTypes,
      'permissions': permissions,
      'service_rules': serviceRules,
      'customer_rules': customerRules,
      'panel_visibility': panelVisibility,
      'backup_policy': backupPolicy,
      'service_form_config': serviceFormConfig,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  CompanyAppSettings copyWith({
    int? maintenanceReminderDays,
    bool? showOverdueMaintenances,
    bool? hideProductsWithoutMaintenance,
    bool? calculateMaintenanceFromProduct,
    bool? onlyLatestProductMaintenance,
    bool? autoDecreaseStockOnService,
    bool? autoAddNewProductToMainWarehouse,
    double? defaultInitialStock,
    bool? allowNegativeStock,
    bool? criticalStockNotifications,
    bool? allowTechnicianCustomerEdit,
    bool? allowTechnicianHistoryEdit,
    bool? requirePaymentToCompleteService,
    bool? allowPartialPayment,
    String? defaultPaymentMethod,
    List<String>? enabledPaymentMethods,
    bool? technicianAssignmentNotifications,
    bool? maintenanceNotifications,
    String? onMyWayTemplate,
    String? appointmentTemplate,
    String? serviceCompletedTemplate,
    String? serviceFormTitle,
    String? serviceFormFooter,
    bool? showPricesOnForm,
    bool? showSignatureOnForm,
    bool? showCustomerAddressOnForm,
    List<String>? enabledServiceTypes,
    Map<String, bool>? permissions,
    Map<String, dynamic>? serviceRules,
    Map<String, dynamic>? customerRules,
    Map<String, dynamic>? panelVisibility,
    Map<String, dynamic>? backupPolicy,
    Map<String, dynamic>? serviceFormConfig,
  }) {
    return CompanyAppSettings(
      companyId: companyId,
      maintenanceReminderDays:
          maintenanceReminderDays ?? this.maintenanceReminderDays,
      showOverdueMaintenances:
          showOverdueMaintenances ?? this.showOverdueMaintenances,
      hideProductsWithoutMaintenance:
          hideProductsWithoutMaintenance ?? this.hideProductsWithoutMaintenance,
      calculateMaintenanceFromProduct: calculateMaintenanceFromProduct ??
          this.calculateMaintenanceFromProduct,
      onlyLatestProductMaintenance:
          onlyLatestProductMaintenance ?? this.onlyLatestProductMaintenance,
      autoDecreaseStockOnService:
          autoDecreaseStockOnService ?? this.autoDecreaseStockOnService,
      autoAddNewProductToMainWarehouse: autoAddNewProductToMainWarehouse ??
          this.autoAddNewProductToMainWarehouse,
      defaultInitialStock: defaultInitialStock ?? this.defaultInitialStock,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      criticalStockNotifications:
          criticalStockNotifications ?? this.criticalStockNotifications,
      allowTechnicianCustomerEdit:
          allowTechnicianCustomerEdit ?? this.allowTechnicianCustomerEdit,
      allowTechnicianHistoryEdit:
          allowTechnicianHistoryEdit ?? this.allowTechnicianHistoryEdit,
      requirePaymentToCompleteService: requirePaymentToCompleteService ??
          this.requirePaymentToCompleteService,
      allowPartialPayment: allowPartialPayment ?? this.allowPartialPayment,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      enabledPaymentMethods:
          enabledPaymentMethods ?? this.enabledPaymentMethods,
      technicianAssignmentNotifications: technicianAssignmentNotifications ??
          this.technicianAssignmentNotifications,
      maintenanceNotifications:
          maintenanceNotifications ?? this.maintenanceNotifications,
      onMyWayTemplate: onMyWayTemplate ?? this.onMyWayTemplate,
      appointmentTemplate: appointmentTemplate ?? this.appointmentTemplate,
      serviceCompletedTemplate:
          serviceCompletedTemplate ?? this.serviceCompletedTemplate,
      serviceFormTitle: serviceFormTitle ?? this.serviceFormTitle,
      serviceFormFooter: serviceFormFooter ?? this.serviceFormFooter,
      showPricesOnForm: showPricesOnForm ?? this.showPricesOnForm,
      showSignatureOnForm: showSignatureOnForm ?? this.showSignatureOnForm,
      showCustomerAddressOnForm:
          showCustomerAddressOnForm ?? this.showCustomerAddressOnForm,
      enabledServiceTypes: enabledServiceTypes ?? this.enabledServiceTypes,
      permissions: permissions ?? this.permissions,
      serviceRules: serviceRules ?? this.serviceRules,
      customerRules: customerRules ?? this.customerRules,
      panelVisibility: panelVisibility ?? this.panelVisibility,
      backupPolicy: backupPolicy ?? this.backupPolicy,
      serviceFormConfig: serviceFormConfig ?? this.serviceFormConfig,
    );
  }
}

class CompanyAppSettingsRepository {
  CompanyAppSettingsRepository(this._client);

  final SupabaseClient _client;

  Future<CompanyAppSettings> load(String companyId) async {
    if (companyId.isEmpty) return const CompanyAppSettings(companyId: '');
    final row = await _client
        .from('company_app_settings')
        .select()
        .eq('company_id', companyId)
        .maybeSingle();
    return row == null
        ? CompanyAppSettings(companyId: companyId)
        : CompanyAppSettings.fromMap(row, companyId: companyId);
  }

  Future<void> save(CompanyAppSettings settings) async {
    await _client
        .from('company_app_settings')
        .upsert(settings.toMap(), onConflict: 'company_id');
  }
}

final companyAppSettingsRepositoryProvider =
    Provider<CompanyAppSettingsRepository>((ref) {
  return CompanyAppSettingsRepository(Supabase.instance.client);
});

final companyAppSettingsProvider =
    FutureProvider.autoDispose<CompanyAppSettings>((ref) async {
  final companyId = ref.watch(authControllerProvider).profile?.companyId ?? '';
  return ref.watch(companyAppSettingsRepositoryProvider).load(companyId);
});

bool _boolValue(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

Map<String, bool> _mergedBoolMap(
  Map<String, bool> defaults,
  Object? raw,
) {
  final result = Map<String, bool>.from(defaults);
  if (raw is Map) {
    for (final entry in raw.entries) {
      result[entry.key.toString()] = _boolValue(entry.value, false);
    }
  }
  return result;
}

Map<String, dynamic> _mergedDynamicMap(
  Map<String, dynamic> defaults,
  Object? raw,
) {
  final result = Map<String, dynamic>.from(defaults);
  if (raw is Map) {
    for (final entry in raw.entries) {
      result[entry.key.toString()] = entry.value;
    }
  }
  return result;
}

Map<String, dynamic> _mergedNestedMap(
  Map<String, dynamic> defaults,
  Object? raw,
) {
  final result = <String, dynamic>{};
  for (final entry in defaults.entries) {
    result[entry.key] = entry.value is Map
        ? Map<String, dynamic>.from(entry.value as Map)
        : entry.value;
  }
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (entry.value is Map && result[key] is Map) {
        result[key] = {
          ...Map<String, dynamic>.from(result[key] as Map),
          ...Map<String, dynamic>.from(entry.value as Map),
        };
      } else {
        result[key] = entry.value;
      }
    }
  }
  return result;
}
