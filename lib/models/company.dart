class Company {
  const Company({
    required this.id,
    required this.name,
    this.legalName,
    this.phone,
    this.email,
    this.taxNumber,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      legalName: json['legal_name']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      taxNumber: json['tax_number']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'legal_name': legalName,
      'phone': phone,
      'email': email,
      'tax_number': taxNumber,
      'is_active': isActive,
      'created_at': _formatDateTime(createdAt),
      'updated_at': _formatDateTime(updatedAt),
    };
  }

  Company copyWith({
    String? id,
    String? name,
    String? legalName,
    String? phone,
    String? email,
    String? taxNumber,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxNumber: taxNumber ?? this.taxNumber,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Company &&
        other.id == id &&
        other.name == name &&
        other.legalName == legalName &&
        other.phone == phone &&
        other.email == email &&
        other.taxNumber == taxNumber &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    legalName,
    phone,
    email,
    taxNumber,
    isActive,
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
