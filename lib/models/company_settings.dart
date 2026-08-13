class CompanySettings {
  const CompanySettings({
    required this.id,
    required this.companyId,
    this.currencyCode = 'TRY',
    this.localeCode = 'tr-TR',
    this.timezone = 'Europe/Istanbul',
    this.maintenanceReminderDays = 15,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String currencyCode;
  final String localeCode;
  final String timezone;
  final int maintenanceReminderDays;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CompanySettings.fromJson(Map<String, dynamic> json) {
    return CompanySettings(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      currencyCode: json['currency_code']?.toString() ?? 'TRY',
      localeCode: json['locale_code']?.toString() ?? 'tr-TR',
      timezone: json['timezone']?.toString() ?? 'Europe/Istanbul',
      maintenanceReminderDays:
          int.tryParse(json['maintenance_reminder_days']?.toString() ?? '') ??
          15,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'currency_code': currencyCode,
      'locale_code': localeCode,
      'timezone': timezone,
      'maintenance_reminder_days': maintenanceReminderDays,
      'created_at': _formatDateTime(createdAt),
      'updated_at': _formatDateTime(updatedAt),
    };
  }

  CompanySettings copyWith({
    String? id,
    String? companyId,
    String? currencyCode,
    String? localeCode,
    String? timezone,
    int? maintenanceReminderDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanySettings(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      currencyCode: currencyCode ?? this.currencyCode,
      localeCode: localeCode ?? this.localeCode,
      timezone: timezone ?? this.timezone,
      maintenanceReminderDays:
          maintenanceReminderDays ?? this.maintenanceReminderDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CompanySettings &&
        other.id == id &&
        other.companyId == companyId &&
        other.currencyCode == currencyCode &&
        other.localeCode == localeCode &&
        other.timezone == timezone &&
        other.maintenanceReminderDays == maintenanceReminderDays &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    currencyCode,
    localeCode,
    timezone,
    maintenanceReminderDays,
    createdAt,
    updatedAt,
  );
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

String? _formatDateTime(DateTime? value) {
  return value?.toUtc().toIso8601String();
}
