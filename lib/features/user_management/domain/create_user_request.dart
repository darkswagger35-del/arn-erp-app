import 'package:arn_erp_app/core/auth/app_role.dart';

class CreateUserRequest {
  const CreateUserRequest({
    required this.fullName,
    required this.username,
    required this.email,
    required this.phone,
    required this.role,
    required this.password,
    required this.passwordConfirmation,
    required this.isActive,
  });

  final String fullName;
  final String username;
  final String email;
  final String phone;
  final AppRole role;
  final String password;
  final String passwordConfirmation;
  final bool isActive;
}
