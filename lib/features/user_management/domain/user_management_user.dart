import 'package:arn_erp_app/core/auth/app_role.dart';

class UserManagementUser {
  const UserManagementUser({
    required this.id,
    required this.companyId,
    required this.fullName,
    required this.email,
    required this.username,
    required this.phone,
    required this.role,
    required this.isActive,
    this.deletedAt,
    this.lastSignInAt,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String fullName;
  final String email;
  final String username;
  final String phone;
  final AppRole role;
  final bool isActive;
  final DateTime? deletedAt;
  final DateTime? lastSignInAt;
  final DateTime? createdAt;

  bool get isArchived => deletedAt != null;

  factory UserManagementUser.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) => value == null
        ? null
        : DateTime.tryParse(value.toString())?.toLocal();

    return UserManagementUser(
      id: json['id']?.toString() ?? '',
      companyId: json['company_id']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: AppRole.fromValue(json['role']?.toString()),
      isActive: json['is_active'] as bool? ?? true,
      deletedAt: parseDate(json['deleted_at']),
      lastSignInAt: parseDate(json['last_sign_in_at']),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class PersonnelProfile {
  const PersonnelProfile({
    required this.completedJobs,
    required this.monthJobs,
    required this.openedServices,
    required this.monthOpenedServices,
    required this.turnover,
    required this.monthTurnover,
    required this.recentJobs,
    required this.usedProducts,
  });

  final int completedJobs;
  final int monthJobs;
  final int openedServices;
  final int monthOpenedServices;
  final double turnover;
  final double monthTurnover;
  final List<Map<String, dynamic>> recentJobs;
  final List<Map<String, dynamic>> usedProducts;

  factory PersonnelProfile.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(Object? value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }

    return PersonnelProfile(
      completedJobs: (json['completed_jobs'] as num?)?.toInt() ?? 0,
      monthJobs: (json['month_jobs'] as num?)?.toInt() ?? 0,
      openedServices: (json['opened_services'] as num?)?.toInt() ?? 0,
      monthOpenedServices:
          (json['month_opened_services'] as num?)?.toInt() ?? 0,
      turnover: (json['turnover'] as num?)?.toDouble() ?? 0,
      monthTurnover: (json['month_turnover'] as num?)?.toDouble() ?? 0,
      recentJobs: rows(json['recent_jobs']),
      usedProducts: rows(json['used_products']),
    );
  }
}
