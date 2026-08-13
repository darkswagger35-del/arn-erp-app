enum CustomerType {
  individual,
  corporate;

  static CustomerType fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'corporate':
        return CustomerType.corporate;
      case 'individual':
      default:
        return CustomerType.individual;
    }
  }

  String get value {
    switch (this) {
      case CustomerType.individual:
        return 'individual';
      case CustomerType.corporate:
        return 'corporate';
    }
  }

  String get label {
    switch (this) {
      case CustomerType.individual:
        return 'Bireysel';
      case CustomerType.corporate:
        return 'Kurumsal';
    }
  }
}

class CustomerModel {
  const CustomerModel({
    this.id,
    this.companyId,
    required this.customerType,
    required this.fullName,
    this.companyName,
    required this.phone,
    this.alternativePhone,
    this.email,
    this.city,
    this.district,
    this.neighborhood,
    required this.address,
    this.latitude,
    this.longitude,
    this.mapsUrl,
    this.notes,
    required this.isActive,
    this.createdBy,
    this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.registrationDate,
  });

  final String? id;
  final String? companyId;
  final CustomerType customerType;
  final String fullName;
  final String? companyName;
  final String phone;
  final String? alternativePhone;
  final String? email;
  final String? city;
  final String? district;
  final String? neighborhood;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? mapsUrl;
  final String? notes;
  final bool isActive;
  final String? createdBy;
  final String? updatedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? registrationDate;

  String get displayName => customerType == CustomerType.corporate
      ? (companyName?.trim().isNotEmpty == true ? companyName! : fullName)
      : fullName;

  String get normalizedPhone {
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('905') && digitsOnly.length == 12) {
      return '0${digitsOnly.substring(2)}';
    }
    if (digitsOnly.startsWith('90') && digitsOnly.length > 10) {
      return '0${digitsOnly.substring(2)}';
    }
    if (digitsOnly.startsWith('0')) {
      return digitsOnly;
    }
    if (digitsOnly.length == 10) {
      return '0$digitsOnly';
    }
    return digitsOnly;
  }

  String get whatsappUrl {
    final sanitized = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (sanitized.startsWith('0')) {
      return 'https://wa.me/90${sanitized.substring(1)}';
    }
    return 'https://wa.me/$sanitized';
  }

  String? get locationText {
    final parts = <String?>[
      address,
      city,
      district,
      neighborhood,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id']?.toString(),
      companyId: json['company_id']?.toString(),
      customerType: CustomerType.fromValue(json['customer_type']?.toString()),
      fullName: json['full_name']?.toString() ?? '',
      companyName: json['company_name']?.toString(),
      phone: json['phone']?.toString() ?? '',
      alternativePhone: json['alternative_phone']?.toString(),
      email: json['email']?.toString(),
      city: json['city']?.toString(),
      district: json['district']?.toString(),
      neighborhood: json['neighborhood']?.toString(),
      address: json['address']?.toString() ?? '',
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : null,
      mapsUrl: json['maps_url']?.toString(),
      notes: json['notes']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      updatedBy: json['updated_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      registrationDate: json['registration_date'] != null
          ? DateTime.tryParse(json['registration_date'].toString())
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'customer_type': customerType.value,
      'full_name': fullName,
      'company_name': companyName,
      'phone': phone,
      'alternative_phone': alternativePhone,
      'email': email,
      'city': city,
      'district': district,
      'neighborhood': neighborhood,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'maps_url': mapsUrl,
      'notes': notes,
      'is_active': isActive,
      'created_by': createdBy,
      'updated_by': updatedBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'registration_date': registrationDate?.toIso8601String(),
    };
  }

  CustomerModel copyWith({
    String? id,
    String? companyId,
    CustomerType? customerType,
    String? fullName,
    String? companyName,
    String? phone,
    String? alternativePhone,
    String? email,
    String? city,
    String? district,
    String? neighborhood,
    String? address,
    double? latitude,
    double? longitude,
    String? mapsUrl,
    String? notes,
    bool? isActive,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? registrationDate,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      customerType: customerType ?? this.customerType,
      fullName: fullName ?? this.fullName,
      companyName: companyName ?? this.companyName,
      phone: phone ?? this.phone,
      alternativePhone: alternativePhone ?? this.alternativePhone,
      email: email ?? this.email,
      city: city ?? this.city,
      district: district ?? this.district,
      neighborhood: neighborhood ?? this.neighborhood,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      registrationDate: registrationDate ?? this.registrationDate,
    );
  }
}

class CustomerPage {
  const CustomerPage({required this.items, required this.hasMore});

  final List<CustomerModel> items;
  final bool hasMore;
}
