class CompanySettingsModel {
  const CompanySettingsModel({
    required this.companyId,
    required this.companyName,
    this.authorizedName,
    this.phone,
    this.email,
    this.taxOffice,
    this.taxNumber,
    this.address,
    this.logoUrl,
    this.maintenanceReminderMonths = 6,
    this.qrValidationRequired = false,
    this.customerSignatureRequired = false,
    this.servicePhotoRequired = false,
    this.paymentRequired = false,
    this.pdfAutoCreate = false,
    this.whatsappServiceFormEnabled = false,
    this.pdfShowLogo = true,
    this.pdfShowSeal = true,
    this.pdfShowSignature = true,
    this.whatsappNotificationsEnabled = true,
    this.smsNotificationsEnabled = false,
    this.emailNotificationsEnabled = true,
  });

  final String companyId;
  final String companyName;
  final String? authorizedName;
  final String? phone;
  final String? email;
  final String? taxOffice;
  final String? taxNumber;
  final String? address;
  final String? logoUrl;
  final int maintenanceReminderMonths;
  final bool qrValidationRequired;
  final bool customerSignatureRequired;
  final bool servicePhotoRequired;
  final bool paymentRequired;
  final bool pdfAutoCreate;
  final bool whatsappServiceFormEnabled;
  final bool pdfShowLogo;
  final bool pdfShowSeal;
  final bool pdfShowSignature;
  final bool whatsappNotificationsEnabled;
  final bool smsNotificationsEnabled;
  final bool emailNotificationsEnabled;

  CompanySettingsModel copyWith({
    String? companyId,
    String? companyName,
    String? authorizedName,
    String? phone,
    String? email,
    String? taxOffice,
    String? taxNumber,
    String? address,
    String? logoUrl,
    int? maintenanceReminderMonths,
    bool? qrValidationRequired,
    bool? customerSignatureRequired,
    bool? servicePhotoRequired,
    bool? paymentRequired,
    bool? pdfAutoCreate,
    bool? whatsappServiceFormEnabled,
    bool? pdfShowLogo,
    bool? pdfShowSeal,
    bool? pdfShowSignature,
    bool? whatsappNotificationsEnabled,
    bool? smsNotificationsEnabled,
    bool? emailNotificationsEnabled,
  }) {
    return CompanySettingsModel(
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      authorizedName: authorizedName ?? this.authorizedName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxOffice: taxOffice ?? this.taxOffice,
      taxNumber: taxNumber ?? this.taxNumber,
      address: address ?? this.address,
      logoUrl: logoUrl ?? this.logoUrl,
      maintenanceReminderMonths:
          maintenanceReminderMonths ?? this.maintenanceReminderMonths,
      qrValidationRequired: qrValidationRequired ?? this.qrValidationRequired,
      customerSignatureRequired:
          customerSignatureRequired ?? this.customerSignatureRequired,
      servicePhotoRequired: servicePhotoRequired ?? this.servicePhotoRequired,
      paymentRequired: paymentRequired ?? this.paymentRequired,
      pdfAutoCreate: pdfAutoCreate ?? this.pdfAutoCreate,
      whatsappServiceFormEnabled:
          whatsappServiceFormEnabled ?? this.whatsappServiceFormEnabled,
      pdfShowLogo: pdfShowLogo ?? this.pdfShowLogo,
      pdfShowSeal: pdfShowSeal ?? this.pdfShowSeal,
      pdfShowSignature: pdfShowSignature ?? this.pdfShowSignature,
      whatsappNotificationsEnabled:
          whatsappNotificationsEnabled ?? this.whatsappNotificationsEnabled,
      smsNotificationsEnabled:
          smsNotificationsEnabled ?? this.smsNotificationsEnabled,
      emailNotificationsEnabled:
          emailNotificationsEnabled ?? this.emailNotificationsEnabled,
    );
  }
}
