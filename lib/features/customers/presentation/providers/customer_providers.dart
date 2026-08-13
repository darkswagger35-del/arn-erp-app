import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_client_provider.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../domain/repositories/customer_repository.dart';
import '../controllers/customer_controller.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepositoryImpl(client: ref.watch(supabaseClientProvider));
});

final customerControllerProvider = ChangeNotifierProvider<CustomerController>((
  ref,
) {
  return CustomerController(repository: ref.watch(customerRepositoryProvider));
});
