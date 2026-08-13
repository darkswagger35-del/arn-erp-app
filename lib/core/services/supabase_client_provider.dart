import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/bootstrap/app_environment.dart';
import '../errors/app_exception.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  final environment = AppEnvironment.fromEnvironment();
  if (!environment.isConfigured) {
    throw const AppException('Supabase bağlantısı yapılandırılmadı.');
  }

  try {
    return Supabase.instance.client;
  } catch (_) {
    throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
  }
});
