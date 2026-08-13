import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/core/errors/app_exception.dart';
import 'package:arn_erp_app/features/customers/data/models/customer_model.dart';
import 'package:arn_erp_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:arn_erp_app/features/customers/presentation/providers/customer_providers.dart';
import 'package:arn_erp_app/features/devices/data/models/customer_device_model.dart';
import 'package:arn_erp_app/features/devices/data/repositories/device_repository_impl.dart';
import 'package:arn_erp_app/features/devices/domain/repositories/device_repository.dart';
import 'package:arn_erp_app/features/devices/presentation/controllers/device_controller.dart';
import 'package:arn_erp_app/features/devices/presentation/providers/device_providers.dart';
import 'package:arn_erp_app/features/devices/presentation/screens/device_detail_screen.dart';
import 'package:arn_erp_app/features/devices/presentation/screens/device_form_screen.dart';
import 'package:arn_erp_app/features/devices/presentation/screens/device_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDeviceRepository implements DeviceRepository {
  FakeDeviceRepository({
    List<CustomerDeviceModel> devices = const [],
    this.deviceById,
    this.throwOnLoad = false,
    this.throwOnSave = false,
    this.hasMore = false,
    this.throwOnDelete = false,
  }) : devices = List<CustomerDeviceModel>.from(devices);

  final List<CustomerDeviceModel> devices;
  final CustomerDeviceModel? deviceById;
  final bool throwOnLoad;
  final bool throwOnSave;
  final bool hasMore;
  final bool throwOnDelete;

  CustomerDeviceModel? lastSavedDevice;
  String? lastDeletedId;
  String? lastStatusId;
  bool? lastStatusValue;
  Map<String, dynamic>? lastFilters;
  int listCallCount = 0;

  @override
  Future<CustomerDeviceModel> createDevice(CustomerDeviceModel device) async {
    if (throwOnSave) {
      throw const AppException('permission denied');
    }
    lastSavedDevice = device.copyWith(id: 'created-id');
    return lastSavedDevice!;
  }

  @override
  Future<CustomerDeviceModel> updateDevice(CustomerDeviceModel device) async {
    if (throwOnSave) {
      throw const AppException('permission denied');
    }
    lastSavedDevice = device;
    return device;
  }

  @override
  Future<void> softDeleteDevice(String id) async {
    if (throwOnDelete) {
      throw const AppException('Cihaz silinemedi.');
    }
    lastDeletedId = id;
    devices.removeWhere((device) => device.id == id);
  }

  @override
  Future<CustomerDeviceModel> changeDeviceStatus(
    String id,
    bool isActive,
  ) async {
    lastStatusId = id;
    lastStatusValue = isActive;
    final device = deviceById ?? devices.first;
    return device.copyWith(id: device.id ?? id, isActive: isActive);
  }

  @override
  Future<CustomerDeviceModel?> findByQrCode(String qrCode) async {
    return deviceById;
  }

  @override
  Future<CustomerDeviceModel?> findBySerialNumber(String serialNumber) async {
    return deviceById;
  }

  @override
  Future<CustomerDeviceModel?> getDeviceById(String id) async {
    if (deviceById != null) {
      return deviceById;
    }
    for (final device in devices) {
      if (device.id == id) {
        return device;
      }
    }
    return null;
  }

  @override
  Future<DevicePage> getDevices({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String? customerId,
    bool? isActive,
    String? deviceType,
    String? pumpType,
  }) async {
    listCallCount++;
    lastFilters = {
      'page': page,
      'pageSize': pageSize,
      'search': search,
      'customerId': customerId,
      'isActive': isActive,
      'deviceType': deviceType,
      'pumpType': pumpType,
    };
    if (throwOnLoad) {
      throw const AppException('Cihazlar yüklenemedi.');
    }
    final normalizedSearch = search.trim().toLowerCase();
    final filtered = devices
        .where((device) {
          if (customerId != null && customerId.isNotEmpty) {
            if (device.customerId != customerId) {
              return false;
            }
          }
          if (isActive != null && device.isActive != isActive) {
            return false;
          }
          if (deviceType != null && deviceType.isNotEmpty) {
            if (device.deviceType.value != deviceType) {
              return false;
            }
          }
          if (pumpType != null && pumpType.isNotEmpty) {
            if (device.pumpType.value != pumpType) {
              return false;
            }
          }
          if (normalizedSearch.isEmpty) {
            return true;
          }
          final haystack = <String>[
            device.brand ?? '',
            device.model ?? '',
            device.serialNumber ?? '',
            device.qrCode ?? '',
            device.customerName ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(normalizedSearch);
        })
        .toList(growable: false);

    return DevicePage(items: filtered, hasMore: hasMore);
  }

  @override
  Future<DevicePage> getDevicesByCustomer({
    required String customerId,
    int page = 1,
    int pageSize = 25,
    String search = '',
    bool? isActive,
    String? deviceType,
    String? pumpType,
  }) async {
    return DevicePage(
      items: devices
          .where((device) => device.customerId == customerId)
          .toList(),
      hasMore: false,
    );
  }

  @override
  Future<DevicePage> getOverdueMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async {
    return DevicePage(items: devices, hasMore: false);
  }

  @override
  Future<DevicePage> getUpcomingMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async {
    return DevicePage(items: devices, hasMore: false);
  }
}

class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({this.customers = const []});

  final List<CustomerModel> customers;

  @override
  Future<CustomerPage> listCustomers({
    int page = 1,
    int pageSize = 25,
    String search = '',
    bool? isActive,
    String city = '',
    String district = '',
  }) async {
    return CustomerPage(items: customers, hasMore: false);
  }

  @override
  Future<CustomerModel> createCustomer(CustomerModel customer) async =>
      customer;

  @override
  Future<CustomerModel> updateCustomer(CustomerModel customer) async =>
      customer;

  @override
  Future<void> toggleActive(String customerId, bool isActive) async {}

  @override
  Future<void> deleteCustomer(String customerId) async {}

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    for (final customer in customers) {
      if (customer.id == customerId) {
        return customer;
      }
    }
    return null;
  }
}

void main() {
  group('CustomerDeviceModel', () {
    test('parses map and exposes Turkish labels', () {
      final model = CustomerDeviceModel.fromMap({
        'id': 'd1',
        'company_id': 'c1',
        'customer_id': 'cu1',
        'brand': '  Aqua  ',
        'model': 'Pro',
        'device_type': 'reverse_osmosis',
        'pump_type': 'pumped',
        'serial_number': ' SN-001 ',
        'qr_code': ' QR-001 ',
        'installation_date': '2026-07-01T00:00:00.000Z',
        'last_maintenance_date': '2026-07-10T00:00:00.000Z',
        'next_maintenance_date': '2026-08-10T00:00:00.000Z',
        'is_active': true,
        'customer': {
          'full_name': 'Ali Veli',
          'phone': '0500',
          'address': 'İstanbul',
        },
      });

      expect(model.toMap()['device_type'], 'reverse_osmosis');
      expect(model.copyWith(model: 'Plus').model, 'Plus');
    });
  });

  group('AppRole device permissions', () {
    test('admin ve manager cihaz yönetebilir', () {
      expect(AppRole.admin.canManageDevices, isTrue);
      expect(AppRole.manager.canManageDevices, isTrue);
      expect(AppRole.secretary.canDeleteDevices, isFalse);
      expect(AppRole.technician.canEditDevices, isFalse);
    });
  });

  group('DeviceController', () {
    test('loadDevices sets loading then success', () async {
      final repository = FakeDeviceRepository(
        devices: [
          CustomerDeviceModel(
            id: 'd1',
            companyId: 'c1',
            customerId: 'cu1',
            customerName: 'Ali Veli',
            deviceType: DeviceType.reverseOsmosis,
            pumpType: PumpType.pumped,
            isActive: true,
          ),
        ],
      );
      final controller = DeviceController(repository: repository);

      final future = controller.loadDevices();
      expect(controller.state.isLoading, isTrue);
      await future;

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.items, hasLength(1));
    });

    test('loadDevices maps errors to Turkish message', () async {
      final repository = FakeDeviceRepository(throwOnLoad: true);
      final controller = DeviceController(repository: repository);

      await controller.loadDevices();

      expect(controller.state.errorMessage, 'Cihazlar yüklenemedi.');
    });

    test('createDevice stores success message', () async {
      final repository = FakeDeviceRepository();
      final controller = DeviceController(repository: repository);

      await controller.createDevice(
        const CustomerDeviceModel(
          customerId: 'cu1',
          deviceType: DeviceType.reverseOsmosis,
          pumpType: PumpType.pumped,
          serialNumber: '  SN-001  ',
          qrCode: ' QR-001 ',
          isActive: true,
        ),
      );

      expect(repository.lastSavedDevice?.serialNumber, 'SN-001');
      expect(controller.state.successMessage, 'Cihaz başarıyla kaydedildi.');
    });

    test(
      'filtre değişince deviceType raw değer olarak repositoryye gider',
      () async {
        final repository = FakeDeviceRepository();
        final controller = DeviceController(repository: repository);

        controller.updateFilters(deviceType: DeviceType.reverseOsmosis.value);
        await Future<void>.delayed(Duration.zero);

        expect(repository.lastFilters?['deviceType'], 'reverse_osmosis');
      },
    );

    test('tümü seçilince deviceType null gider', () async {
      final repository = FakeDeviceRepository();
      final controller = DeviceController(repository: repository);

      controller.updateFilters(deviceType: DeviceType.underCounter.value);
      await Future<void>.delayed(Duration.zero);
      controller.updateFilters(deviceType: null);
      await Future<void>.delayed(Duration.zero);

      expect(repository.lastFilters?['deviceType'], isNull);
    });

    test('pompa tipi raw değer olarak repositoryye gider', () async {
      final repository = FakeDeviceRepository();
      final controller = DeviceController(repository: repository);

      controller.updateFilters(pumpType: PumpType.nonPumped.value);
      await Future<void>.delayed(Duration.zero);

      expect(repository.lastFilters?['pumpType'], 'non_pumped');
    });

    test('aktif filtre bool olarak repositoryye gider', () async {
      final repository = FakeDeviceRepository();
      final controller = DeviceController(repository: repository);

      controller.updateFilters(isActive: true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.lastFilters?['isActive'], isTrue);

      controller.updateFilters(isActive: false);
      await Future<void>.delayed(Duration.zero);
      expect(repository.lastFilters?['isActive'], isFalse);
    });

    test('filtre değişince sayfa 1e döner ve eski hata temizlenir', () async {
      final repository = FakeDeviceRepository(hasMore: true);
      final controller = DeviceController(repository: repository);

      await controller.loadDevices();
      await controller.loadMoreDevices();
      expect(controller.state.page, 2);

      controller.updateFilters(deviceType: DeviceType.softener.value);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.page, 1);
      expect(controller.state.errorMessage, isNull);
    });
  });

  group('DeviceRepository payload helpers', () {
    test(
      'update payload immutable alanlari icermez ve degisen alanlari ekler',
      () {
        final current = CustomerDeviceModel(
          id: 'd1',
          companyId: 'c1',
          customerId: 'cu1',
          brand: 'Aqua',
          model: 'Pro',
          deviceType: DeviceType.reverseOsmosis,
          pumpType: PumpType.pumped,
          serialNumber: 'SN-001',
          qrCode: 'QR-001',
          isActive: true,
          createdAt: DateTime.utc(2026, 1, 1),
        );
        final next = current.copyWith(brand: 'Aqua X', serialNumber: null);

        final payload = DeviceRepositoryImpl.buildUpdatePayloadForTest(
          nextDevice: next,
          existingDevice: current,
        );

        expect(payload.containsKey('id'), isFalse);
        expect(payload.containsKey('company_id'), isFalse);
        expect(payload.containsKey('created_at'), isFalse);
        expect(payload.containsKey('customer_id'), isFalse);
        expect(payload['brand'], 'Aqua X');
        expect(payload['serial_number'], isNull);
      },
    );

    test('degisen customer_id payloada girer', () {
      final current = CustomerDeviceModel(
        id: 'd1',
        companyId: 'c1',
        customerId: 'cu1',
        deviceType: DeviceType.reverseOsmosis,
        pumpType: PumpType.pumped,
        isActive: true,
      );
      final next = current.copyWith(customerId: 'cu2');

      final payload = DeviceRepositoryImpl.buildUpdatePayloadForTest(
        nextDevice: next,
        existingDevice: current,
      );

      expect(payload['customer_id'], 'cu2');
    });

    test('status payload yalnizca is_active icerir', () {
      final payload = DeviceRepositoryImpl.buildStatusPayloadForTest(false);

      expect(payload.keys, ['is_active']);
      expect(payload['is_active'], isFalse);
    });

    test('soft delete payload yalnizca deleted_at ve is_active icerir', () {
      final payload = DeviceRepositoryImpl.buildSoftDeletePayloadForTest(
        DateTime.utc(2026, 7, 25),
      );

      expect(payload.keys.toSet(), {'deleted_at', 'is_active'});
      expect(payload['is_active'], isFalse);
      expect(payload['deleted_at'], contains('2026-07-25'));
    });

    test('customer_devices liste sorgusunda tum filtreler order/range öncesindedir', () {
      final plan = DeviceRepositoryImpl.buildListQueryOperationPlanForTest(
        hasCustomerId: true,
        hasIsActive: true,
        hasDeviceType: true,
        hasPumpType: true,
        hasSearch: true,
      );

      final orderIndex = plan.indexOf('order_created_at');
      final rangeIndex = plan.indexOf('range');
      expect(plan, contains('eq_customer_id'));
      expect(plan, contains('eq_company_id'));
      expect(plan, contains('filter_deleted_at'));
      expect(plan.indexOf('eq_customer_id'), lessThan(orderIndex));
      expect(plan.indexOf('eq_is_active'), lessThan(orderIndex));
      expect(plan.indexOf('eq_device_type'), lessThan(orderIndex));
      expect(plan.indexOf('eq_pump_type'), lessThan(orderIndex));
      expect(plan.indexOf('or_search'), lessThan(orderIndex));
      expect(orderIndex, lessThan(rangeIndex));
    });

    test('customer_devices customer detail planı customer/company/deleted filtrelerini zorunlu tutar', () {
      final plan = DeviceRepositoryImpl.buildListQueryOperationPlanForTest(
        hasCustomerId: true,
        hasIsActive: false,
        hasDeviceType: false,
        hasPumpType: false,
        hasSearch: false,
      );

      expect(plan.take(3), ['select', 'eq_company_id', 'filter_deleted_at']);
      expect(plan, contains('eq_customer_id'));
      expect(plan.indexOf('eq_customer_id'), lessThan(plan.indexOf('order_created_at')));
    });
  });

  group('Device widgets', () {
    testWidgets('ui device type seciminde raw enum degeri repositoryye gider', (
      tester,
    ) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('device-type-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ters Ozmoz').last);
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['deviceType'], 'reverse_osmosis');
    });

    testWidgets('ui pump type seciminde raw enum degeri repositoryye gider', (
      tester,
    ) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pump-type-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pompalı').last);
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['pumpType'], 'pumped');
    });

    testWidgets('ui pasif seciminde bool false repositoryye gider', (
      tester,
    ) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('is-active-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pasif').last);
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['isActive'], isFalse);
    });

    testWidgets('arama debounce sonrasi repositoryye gider', (tester) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Aqua');
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.lastFilters?['search'], isNot('Aqua'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(repository.lastFilters?['search'], 'Aqua');
    });

    testWidgets('arama temizlenince repository search bos gider', (
      tester,
    ) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Aqua');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.lastFilters?['search'], 'Aqua');

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.lastFilters?['search'], '');
    });

    testWidgets('musteri adina gore arama sonucu donebilir', (tester) async {
      final repository = FakeDeviceRepository(
        devices: [
          CustomerDeviceModel(
            id: 'd1',
            companyId: 'c1',
            customerId: 'cu1',
            customerName: 'Mehmet Demir',
            brand: 'Aqua',
            deviceType: DeviceType.reverseOsmosis,
            pumpType: PumpType.pumped,
            isActive: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mehmet');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.text('Kayıt bulunamadı.'), findsNothing);
    });

    testWidgets('filtre degisince bekleyen arama debounce sonucu ezmez', (
      tester,
    ) async {
      final repository = FakeDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Aqua');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('device-type-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ters Ozmoz').last);
      await tester.pumpAndSettle();
      final filtersAfterChange = Map<String, dynamic>.from(
        repository.lastFilters ?? const <String, dynamic>{},
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.lastFilters, filtersAfterChange);
    });

    testWidgets('soft delete basarili olunca cihaz listeden kalkar', (
      tester,
    ) async {
      final repository = FakeDeviceRepository(
        devices: [
          CustomerDeviceModel(
            id: 'd1',
            companyId: 'c1',
            customerId: 'cu1',
            customerName: 'Ali Veli',
            brand: 'Aqua',
            deviceType: DeviceType.reverseOsmosis,
            pumpType: PumpType.pumped,
            isActive: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: DeviceListScreen(role: AppRole.admin)),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil').last);
      await tester.pumpAndSettle();

      expect(find.text('Kayıt bulunamadı.'), findsOneWidget);
      expect(repository.lastDeletedId, 'd1');
    });

    testWidgets('soft delete hata verirse cihaz listede kalir', (tester) async {
      final repository = FakeDeviceRepository(
        devices: [
          CustomerDeviceModel(
            id: 'd1',
            companyId: 'c1',
            customerId: 'cu1',
            customerName: 'Ali Veli',
            brand: 'Aqua',
            deviceType: DeviceType.reverseOsmosis,
            pumpType: PumpType.pumped,
            isActive: true,
          ),
        ],
        throwOnDelete: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(home: DeviceListScreen(role: AppRole.admin)),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil').last);
      await tester.pumpAndSettle();

      expect(find.text('Ali Veli'), findsOneWidget);
    });

    testWidgets('empty list state is shown', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceRepositoryProvider.overrideWithValue(FakeDeviceRepository()),
          ],
          child: const MaterialApp(
            home: DeviceListScreen(role: AppRole.secretary),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Kayıt bulunamadı.'), findsOneWidget);
    });

    testWidgets(
      'technician does not see edit or delete buttons on detail screen',
      (tester) async {
        final device = CustomerDeviceModel(
          id: 'd1',
          companyId: 'c1',
          customerId: 'cu1',
          customerName: 'Ali Veli',
          customerPhone: '0500',
          customerAddress: 'İstanbul',
          brand: 'Aqua',
          model: 'Pro',
          deviceType: DeviceType.reverseOsmosis,
          pumpType: PumpType.pumped,
          serialNumber: 'SN-001',
          qrCode: 'QR-001',
          isActive: true,
          createdAt: DateTime.utc(2026, 7, 25),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceRepositoryProvider.overrideWithValue(
                FakeDeviceRepository(deviceById: device),
              ),
            ],
            child: const MaterialApp(
              home: DeviceDetailScreen(
                role: AppRole.technician,
                deviceId: 'd1',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Düzenle'), findsNothing);
        expect(find.text('Sil'), findsNothing);
        expect(find.text('Pasif Yap'), findsNothing);
      },
    );

    testWidgets('form validation shows required field messages', (
      tester,
    ) async {
      final customer = CustomerModel(
        id: 'cu1',
        customerType: CustomerType.individual,
        fullName: 'Ali Veli',
        phone: '0500 111 22 33',
        address: 'İstanbul',
        isActive: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceRepositoryProvider.overrideWithValue(FakeDeviceRepository()),
            customerRepositoryProvider.overrideWithValue(
              FakeCustomerRepository(customers: [customer]),
            ),
          ],
          child: const MaterialApp(
            home: DeviceFormScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Kaydet'));
      await tester.tap(find.text('Kaydet'));
      await tester.pump();

      expect(find.text('Müşteri seçimi zorunludur.'), findsOneWidget);
      expect(find.text('Cihaz tipi zorunludur.'), findsOneWidget);
      expect(find.text('Pompa tipi zorunludur.'), findsOneWidget);
    });
  });
}
