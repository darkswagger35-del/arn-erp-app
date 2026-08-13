import '../core/auth/app_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.companyId,
    required this.fullName,
    this.phone,
    required this.role,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String fullName;
  final String? phone;
  final AppRole role;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      role: AppRole.fromValue(json['role']?.toString()),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'full_name': fullName,
      'phone': phone,
      'role': role.name,
      'is_active': isActive,
      'created_at': _formatDateTime(createdAt),
      'updated_at': _formatDateTime(updatedAt),
    };
  }

  UserProfile copyWith({
    String? id,
    String? companyId,
    String? fullName,
    String? phone,
    AppRole? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
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
    return other is UserProfile &&
        other.id == id &&
        other.companyId == companyId &&
        other.fullName == fullName &&
        other.phone == phone &&
        other.role == role &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    fullName,
    phone,
    role,
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
