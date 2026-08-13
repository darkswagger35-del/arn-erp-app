import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client_provider.dart';
import 'finance_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository(ref.watch(supabaseClientProvider));
});
