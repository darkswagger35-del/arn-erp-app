import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client_provider.dart';
import 'operations_repository.dart';

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository(ref.watch(supabaseClientProvider));
});
