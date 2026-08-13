import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/bootstrap/app_environment.dart';

class SupabaseBootstrap {
  SupabaseBootstrap._();

  static Future<void> initialize() async {
    final environment = AppEnvironment.fromEnvironment();

    if (!environment.isConfigured) {
      debugPrint(environment.message);
      return;
    }

    try {
      await Supabase.initialize(
        url: environment.supabaseUrl,
        publishableKey: environment.supabasePublishableKey,
      );
    } catch (error) {
      debugPrint('Supabase başlatılırken bir hata oluştu: $error');
    }
  }
}
