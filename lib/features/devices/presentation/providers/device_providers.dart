import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_client_provider.dart';
import '../../data/models/customer_device_model.dart';
import '../../data/repositories/device_repository_impl.dart';
import '../../domain/repositories/device_repository.dart';
import '../controllers/device_controller.dart';

final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  return DeviceRepositoryImpl(client: ref.watch(supabaseClientProvider));
});

final deviceControllerProvider =
    StateNotifierProvider<DeviceController, DeviceState>((ref) {
      return DeviceController(repository: ref.watch(deviceRepositoryProvider));
    });

final deviceDetailProvider =
    FutureProvider.family<CustomerDeviceModel?, String>((ref, deviceId) async {
      final repository = ref.watch(deviceRepositoryProvider);
      return repository.getDeviceById(deviceId);
    });

final devicesByCustomerProvider = FutureProvider.family<DevicePage, String>((
  ref,
  customerId,
) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getDevicesByCustomer(
    customerId: customerId,
    page: 1,
    pageSize: 100,
  );
});

final upcomingMaintenanceDevicesProvider = FutureProvider<DevicePage>((
  ref,
) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getUpcomingMaintenanceDevices(page: 1, pageSize: 100);
});

final overdueMaintenanceDevicesProvider = FutureProvider<DevicePage>((
  ref,
) async {
  final repository = ref.watch(deviceRepositoryProvider);
  return repository.getOverdueMaintenanceDevices(page: 1, pageSize: 100);
});
