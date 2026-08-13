import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client_provider.dart';
import 'service_execution_repository.dart';

final serviceExecutionRepositoryProvider = Provider<ServiceExecutionRepository>(
  (ref) => ServiceExecutionRepository(ref.watch(supabaseClientProvider)),
);
