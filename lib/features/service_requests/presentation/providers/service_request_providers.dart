import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_client_provider.dart';
import '../../data/repositories/service_request_repository_impl.dart';
import '../../domain/repositories/service_request_repository.dart';
import '../controllers/service_request_controller.dart';

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((
  ref,
) {
  return ServiceRequestRepositoryImpl(
    client: ref.watch(supabaseClientProvider),
  );
});

final serviceRequestControllerProvider =
    ChangeNotifierProvider<ServiceRequestController>((ref) {
      return ServiceRequestController(
        repository: ref.watch(serviceRequestRepositoryProvider),
      );
    });
