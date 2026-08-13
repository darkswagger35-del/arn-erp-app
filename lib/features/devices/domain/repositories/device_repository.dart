import '../../data/models/customer_device_model.dart';

abstract class DeviceRepository {
  Future<DevicePage> getDevices({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String? customerId,
    bool? isActive,
    String? deviceType,
    String? pumpType,
  });

  Future<DevicePage> getDevicesByCustomer({
    required String customerId,
    int page = 1,
    int pageSize = 25,
    String search = '',
    bool? isActive,
    String? deviceType,
    String? pumpType,
  });

  Future<CustomerDeviceModel?> getDeviceById(String id);

  Future<CustomerDeviceModel> createDevice(CustomerDeviceModel device);

  Future<CustomerDeviceModel> updateDevice(CustomerDeviceModel device);

  Future<void> softDeleteDevice(String id);

  Future<CustomerDeviceModel> changeDeviceStatus(String id, bool isActive);

  Future<CustomerDeviceModel?> findByQrCode(String qrCode);

  Future<CustomerDeviceModel?> findBySerialNumber(String serialNumber);

  Future<DevicePage> getUpcomingMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  });

  Future<DevicePage> getOverdueMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  });
}
