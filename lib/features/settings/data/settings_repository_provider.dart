import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_repository.dart';
import 'settings_repository_impl.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepositoryImpl();
});
