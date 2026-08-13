import '../../models/company.dart';
import '../../models/user_profile.dart';
import 'app_role.dart';

class AuthState {
  const AuthState({
    this.role,
    this.user,
    this.profile,
    this.company,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.errorMessage,
    this.status = AuthStatus.initial,
  });

  final AppRole? role;
  final dynamic user;
  final UserProfile? profile;
  final Company? company;
  final bool isAuthenticated;
  final bool isLoading;
  final String? errorMessage;
  final AuthStatus status;

  AuthState copyWith({
    AppRole? role,
    dynamic user,
    UserProfile? profile,
    Company? company,
    bool? isAuthenticated,
    bool? isLoading,
    String? errorMessage,
    AuthStatus? status,
  }) {
    return AuthState(
      role: role ?? this.role,
      user: user ?? this.user,
      profile: profile ?? this.profile,
      company: company ?? this.company,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      status: status ?? this.status,
    );
  }
}

enum AuthStatus { initial, loading, unauthenticated, authenticated, error }
