import 'package:flutter/foundation.dart';
import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/core/errors/app_exception.dart';
import '../data/user_management_repository.dart';
import '../domain/create_user_request.dart';
import '../domain/user_management_user.dart';

class UserManagementState {
  const UserManagementState({
    this.users = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
  });
  final List<UserManagementUser> users;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;

  UserManagementState copyWith({
    List<UserManagementUser>? users,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? successMessage,
  }) => UserManagementState(
    users: users ?? this.users,
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: errorMessage,
    successMessage: successMessage,
  );
}

class UserManagementController extends ChangeNotifier {
  UserManagementController({required this.repository});
  final UserManagementRepository repository;
  UserManagementState _state = const UserManagementState();
  UserManagementState get state => _state;

  Future<void> loadUsers() async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();
    try {
      _state = _state.copyWith(users: await repository.listUsers(), isLoading: false);
    } catch (e) {
      _state = _state.copyWith(isLoading: false, errorMessage: _message(e));
    }
    notifyListeners();
  }

  Future<bool> createUser({
    required String fullName,
    required String username,
    required String email,
    required String phone,
    required AppRole role,
    required String password,
    required String passwordConfirmation,
    required bool isActive,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (fullName.trim().isEmpty || email.trim().isEmpty || normalizedUsername.isEmpty) {
      return _fail('Ad soyad, kullanıcı adı ve e-posta zorunludur.');
    }
    if (!RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(normalizedUsername)) {
      return _fail('Kullanıcı adı 3-30 karakter olmalı; harf, rakam, nokta, tire ve alt çizgi kullanılabilir.');
    }
    if (_state.users.any((u) => !u.isArchived && u.username.toLowerCase() == normalizedUsername)) {
      return _fail('Bu kullanıcı adı zaten kullanılıyor.');
    }
    if (password.length < 6 || password != passwordConfirmation) {
      return _fail(password.length < 6 ? 'Şifre en az 6 karakter olmalıdır.' : 'Şifreler eşleşmiyor.');
    }
    return _run(
      () => repository.createUser(CreateUserRequest(
        fullName: fullName.trim(), username: normalizedUsername,
        email: email.trim().toLowerCase(), phone: phone.trim(), role: role,
        password: password, passwordConfirmation: passwordConfirmation,
        isActive: isActive,
      )),
      'Kullanıcı oluşturuldu.',
    );
  }

  Future<bool> updateUser({
    required String userId,
    String? fullName,
    String? username,
    String? phone,
    AppRole? role,
    bool? isActive,
  }) => _run(
    () => repository.updateUser(
      userId: userId, fullName: fullName, username: username?.trim().toLowerCase(),
      phone: phone, role: role, isActive: isActive,
    ),
    'Kullanıcı bilgileri güncellendi.',
  );

  Future<bool> archiveUser(String id) => _run(() => repository.archiveUser(id), 'Kullanıcı arşive alındı.');
  Future<bool> restoreUser(String id, String username) {
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(normalizedUsername)) {
      return Future.value(_fail(
        'Kullanıcı adı 3-30 karakter olmalı; harf, rakam, nokta, tire ve alt çizgi kullanılabilir.',
      ));
    }
    if (_state.users.any((u) =>
        u.id != id &&
        !u.isArchived &&
        u.username.toLowerCase() == normalizedUsername)) {
      return Future.value(_fail('Bu kullanıcı adı zaten kullanılıyor.'));
    }
    return _run(
      () => repository.restoreUser(id, username: normalizedUsername),
      'Kullanıcı geri yüklendi.',
    );
  }
  Future<bool> deleteUserPermanently(String id) => _run(() => repository.deleteUserPermanently(id), 'Kullanıcı kalıcı olarak silindi.');
  Future<bool> setUserPassword(String id, String password) => password.length < 6
      ? Future.value(_fail('Şifre en az 6 karakter olmalıdır.'))
      : _run(() => repository.setUserPassword(userId: id, password: password), 'Şifre güncellendi.', reload: false);
  Future<PersonnelProfile> getPersonnelProfile(String id) => repository.getPersonnelProfile(id);

  bool _fail(String message) {
    _state = _state.copyWith(errorMessage: message, successMessage: null);
    notifyListeners();
    return false;
  }

  Future<bool> _run(Future<void> Function() action, String success, {bool reload = true}) async {
    _state = _state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await action();
      if (reload) {
        final users = await repository.listUsers();
        _state = _state.copyWith(users: users, isSaving: false, successMessage: success);
      } else {
        _state = _state.copyWith(isSaving: false, successMessage: success);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(isSaving: false, errorMessage: _message(e));
      notifyListeners();
      return false;
    }
  }

  String _message(Object error) => error is AppException ? error.message : error.toString();
}
