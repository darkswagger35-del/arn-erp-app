enum AppRole {
  admin,
  manager,
  secretary,
  technician;

  static AppRole fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'admin':
        return AppRole.admin;
      case 'manager':
        return AppRole.manager;
      case 'secretary':
        return AppRole.secretary;
      case 'technician':
        return AppRole.technician;
      default:
        throw ArgumentError.value(value, 'value', 'Geçersiz rol değeri.');
    }
  }
}

extension AppRoleLabel on AppRole {
  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Admin';
      case AppRole.manager:
        return 'Yönetici';
      case AppRole.secretary:
        return 'Sekreter';
      case AppRole.technician:
        return 'Teknisyen';
    }
  }

  String get value {
    switch (this) {
      case AppRole.admin:
        return 'admin';
      case AppRole.manager:
        return 'manager';
      case AppRole.secretary:
        return 'secretary';
      case AppRole.technician:
        return 'technician';
    }
  }

  bool get canManageDevices {
    switch (this) {
      case AppRole.admin:
      case AppRole.manager:
        return true;
      case AppRole.secretary:
      case AppRole.technician:
        return false;
    }
  }

  bool get canEditDevices {
    switch (this) {
      case AppRole.admin:
      case AppRole.manager:
      case AppRole.secretary:
        return true;
      case AppRole.technician:
        return false;
    }
  }

  bool get canDeleteDevices => canManageDevices;

  bool get canChangeDeviceStatus => canManageDevices;
}
