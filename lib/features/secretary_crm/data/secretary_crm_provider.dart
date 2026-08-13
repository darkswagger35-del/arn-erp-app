import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client_provider.dart';
import 'secretary_crm_repository.dart';

final secretaryCrmRepositoryProvider = Provider<SecretaryCrmRepository>((ref) {
  return SecretaryCrmRepository(ref.watch(supabaseClientProvider));
});
