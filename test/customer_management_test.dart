import 'package:arn_erp_app/features/customers/data/models/customer_model.dart';
import 'package:arn_erp_app/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:arn_erp_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:arn_erp_app/features/customers/presentation/controllers/customer_controller.dart';
import 'package:arn_erp_app/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:arn_erp_app/features/customers/presentation/screens/customer_list_screen.dart';
import 'package:arn_erp_app/features/customers/presentation/providers/customer_providers.dart';
import 'package:arn_erp_app/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:arn_erp_app/core/auth/app_role.dart';
import 'package:arn_erp_app/features/devices/data/models/customer_device_model.dart';
import 'package:arn_erp_app/features/devices/domain/repositories/device_repository.dart';
import 'package:arn_erp_app/features/devices/presentation/providers/device_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({
    List<CustomerModel> customers = const [],
    this.createDelay = Duration.zero,
  }) : customers = List<CustomerModel>.from(customers);

  final List<CustomerModel> customers;
  final Duration createDelay;
  CustomerModel? lastSavedCustomer;
  Map<String, dynamic>? lastFilters;
  int createCount = 0;
  int updateCount = 0;
  int listCallCount = 0;
  String? lastToggledCustomerId;
  bool? lastToggledIsActive;
  String? lastDeletedCustomerId;

  @override
  Future<CustomerPage> listCustomers({
    int page = 1,
    int pageSize = 25,
    String search = '',
    bool? isActive,
    String city = '',
    String district = '',
  }) async {
    listCallCount++;
    lastFilters = {
      'page': page,
      'pageSize': pageSize,
      'search': search,
      'isActive': isActive,
      'city': city,
      'district': district,
    };
    final normalizedSearch = search.trim().toLowerCase();
    final filtered = customers
        .where((customer) {
          if (isActive != null && customer.isActive != isActive) {
            return false;
          }
          if (city.trim().isNotEmpty) {
            final customerCity = (customer.city ?? '').toLowerCase();
            if (!customerCity.contains(city.trim().toLowerCase())) {
              return false;
            }
          }
          if (district.trim().isNotEmpty) {
            final customerDistrict = (customer.district ?? '').toLowerCase();
            if (!customerDistrict.contains(district.trim().toLowerCase())) {
              return false;
            }
          }
          if (normalizedSearch.isEmpty) {
            return true;
          }
          final haystack = <String>[
            customer.fullName,
            customer.companyName ?? '',
            customer.phone,
            customer.email ?? '',
            customer.address,
          ].join(' ').toLowerCase();
          return haystack.contains(normalizedSearch);
        })
        .toList(growable: false);

    return CustomerPage(items: filtered, hasMore: false);
  }

  @override
  Future<CustomerModel> createCustomer(CustomerModel customer) async {
    createCount++;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    lastSavedCustomer = customer;
    return customer.copyWith(id: 'new-id');
  }

  @override
  Future<CustomerModel> updateCustomer(CustomerModel customer) async {
    updateCount++;
    lastSavedCustomer = customer;
    return customer;
  }

  @override
  Future<void> toggleActive(String customerId, bool isActive) async {
    lastToggledCustomerId = customerId;
    lastToggledIsActive = isActive;
    final index = customers.indexWhere((customer) => customer.id == customerId);
    if (index == -1) {
      return;
    }
    customers[index] = customers[index].copyWith(isActive: isActive);
  }

  @override
  Future<void> deleteCustomer(String customerId) async {
    lastDeletedCustomerId = customerId;
  }

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

class SpyDeviceRepository implements DeviceRepository {
  String? lastDevicesByCustomerId;

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
    lastDevicesByCustomerId = customerId;
    return const DevicePage(items: [], hasMore: false);
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
  }) async => const DevicePage(items: [], hasMore: false);

  @override
  Future<CustomerDeviceModel?> getDeviceById(String id) async => null;

  @override
  Future<CustomerDeviceModel> createDevice(CustomerDeviceModel device) async =>
      device.copyWith(id: 'new-device-id');

  @override
  Future<CustomerDeviceModel> updateDevice(CustomerDeviceModel device) async =>
      device;

  @override
  Future<void> softDeleteDevice(String id) async {}

  @override
  Future<CustomerDeviceModel> changeDeviceStatus(String id, bool isActive) async =>
      CustomerDeviceModel(
        id: id,
        customerId: 'customer-id',
        deviceType: DeviceType.reverseOsmosis,
        pumpType: PumpType.pumped,
        isActive: isActive,
      );

  @override
  Future<CustomerDeviceModel?> findByQrCode(String qrCode) async => null;

  @override
  Future<CustomerDeviceModel?> findBySerialNumber(String serialNumber) async =>
      null;

  @override
  Future<DevicePage> getUpcomingMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async => const DevicePage(items: [], hasMore: false);

  @override
  Future<DevicePage> getOverdueMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async => const DevicePage(items: [], hasMore: false);
}

void main() {
  group('CustomerController', () {
    test('yükleme sonrası müşteriler state içinde görünür', () async {
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: '1',
            customerType: CustomerType.individual,
            fullName: 'Ali Veli',
            phone: '0500 111 22 33',
            address: 'İstanbul',
            isActive: true,
          ),
        ],
      );
      final controller = CustomerController(repository: repository);

      await controller.loadCustomers();

      expect(controller.state.customers, hasLength(1));
      expect(controller.state.isLoading, isFalse);
    });

    test('yeni müşteri kaydında telefon normalize edilir', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.saveCustomer(
        CustomerModel(
          customerType: CustomerType.individual,
          fullName: 'Ayşe Yılmaz',
          phone: '+90 (505) 123 45 67',
          address: 'Kadıköy',
          isActive: true,
        ),
      );

      expect(repository.lastSavedCustomer?.phone, '05051234567');
    });

    test('geçersiz e-posta reddedilir', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.saveCustomer(
        CustomerModel(
          customerType: CustomerType.individual,
          fullName: 'Ayşe Yılmaz',
          phone: '05051234567',
          email: 'not-an-email',
          address: 'Kadıköy',
          isActive: true,
        ),
      );

      expect(controller.state.errorMessage, contains('Geçerli bir e-posta'));
      expect(repository.lastSavedCustomer, isNull);
    });

    test('geçersiz latitude reddedilir', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.saveCustomer(
        CustomerModel(
          customerType: CustomerType.individual,
          fullName: 'Ayşe Yılmaz',
          phone: '05051234567',
          address: 'Kadıköy',
          latitude: 91,
          isActive: true,
        ),
      );

      expect(controller.state.errorMessage, contains('Enlem'));
      expect(repository.lastSavedCustomer, isNull);
    });

    test('geçersiz longitude reddedilir', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.saveCustomer(
        CustomerModel(
          customerType: CustomerType.individual,
          fullName: 'Ayşe Yılmaz',
          phone: '05051234567',
          address: 'Kadıköy',
          longitude: 181,
          isActive: true,
        ),
      );

      expect(controller.state.errorMessage, contains('Boylam'));
      expect(repository.lastSavedCustomer, isNull);
    });

    test('aktiflik sadece seçilen müşteri UUIDsi ile güncellenir ve liste yenilenir', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.loadCustomers();
      final listCallsBeforeMutation = repository.listCallCount;
      await controller.toggleActive('customer-y-uuid', false);

      expect(repository.lastToggledCustomerId, 'customer-y-uuid');
      expect(repository.lastToggledIsActive, isFalse);
      expect(repository.listCallCount, listCallsBeforeMutation + 1);
      expect(controller.state.successMessage, 'Müşteri durumu güncellendi.');
    });

    test('silme seçilen müşteri UUIDsi için soft-delete deposunu çağırır ve listeyi yeniler', () async {
      final repository = FakeCustomerRepository();
      final controller = CustomerController(repository: repository);

      await controller.loadCustomers();
      final listCallsBeforeMutation = repository.listCallCount;
      await controller.deleteCustomer('customer-y-uuid');

      expect(repository.lastDeletedCustomerId, 'customer-y-uuid');
      expect(repository.listCallCount, listCallsBeforeMutation + 1);
      expect(controller.state.successMessage, 'Müşteri silindi.');
    });

    test('aktif filtre açıkken pasife alınan müşteri listeden düşer', () async {
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: 'active-customer-id',
            customerType: CustomerType.individual,
            fullName: 'Aktif Müşteri',
            phone: '05001112233',
            address: 'İstanbul',
            isActive: true,
          ),
        ],
      );
      final controller = CustomerController(repository: repository);

      await controller.loadCustomers(isActive: true);
      expect(controller.state.isActive, isTrue);
      expect(
        controller.state.customers.any((c) => c.id == 'active-customer-id'),
        isTrue,
      );

      await controller.toggleActive('active-customer-id', false);

      expect(controller.state.isActive, isTrue);
      expect(
        controller.state.customers.any((c) => c.id == 'active-customer-id'),
        isFalse,
      );
    });

    test('toggle sonrası refresh mevcut filtre ve sayfalama parametreleriyle yapılır', () async {
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: 'customer-y-uuid',
            customerType: CustomerType.individual,
            fullName: 'Müşteri Y',
            phone: '05004445566',
            address: 'Ankara',
            city: 'Ankara',
            district: 'Çankaya',
            isActive: true,
          ),
        ],
      );
      final controller = CustomerController(repository: repository);

      await controller.loadCustomers(
        search: 'Mehmet',
        city: 'Ankara',
        district: 'Çankaya',
        isActive: true,
      );

      await controller.toggleActive('customer-y-uuid', false);

      expect(repository.lastFilters?['search'], 'Mehmet');
      expect(repository.lastFilters?['city'], 'Ankara');
      expect(repository.lastFilters?['district'], 'Çankaya');
      expect(repository.lastFilters?['isActive'], isTrue);
      expect(repository.lastFilters?['page'], 1);
      expect(repository.lastFilters?['pageSize'], 25);
      expect(controller.state.successMessage, 'Müşteri durumu güncellendi.');
    });
  });

  group('CustomerDetailScreen', () {
    testWidgets('cihazlar route customer UUID ile yüklenir', (tester) async {
      final customerRepository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: 'route-customer-uuid',
            customerType: CustomerType.individual,
            fullName: 'Rota Müşterisi',
            phone: '05001112233',
            address: 'İstanbul',
            isActive: true,
          ),
        ],
      );
      final deviceRepository = SpyDeviceRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerRepositoryProvider.overrideWithValue(customerRepository),
            deviceRepositoryProvider.overrideWithValue(deviceRepository),
          ],
          child: const MaterialApp(
            home: CustomerDetailScreen(
              role: AppRole.manager,
              customerId: 'route-customer-uuid',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(deviceRepository.lastDevicesByCustomerId, 'route-customer-uuid');
    });
  });

  group('Customer search filters', () {
    test('mehmet araması tüm metin sütunlarında ilike kullanır', () {
      final expression = buildCustomerSearchOrExpression(' mehmet ');

      for (final column in customerSearchColumns) {
        expect(expression, contains('$column.ilike.%mehmet%'));
      }
    });

    test('MEHMET ilike ile Mehmet ve mehmet için case-insensitive kalır', () {
      final expression = buildCustomerSearchOrExpression('MEHMET');

      expect(expression, contains('full_name.ilike.%MEHMET%'));
    });

    test('İSMAİL araması ismail Türkçe I varyantını da üretir', () {
      final expression = buildCustomerSearchOrExpression('İSMAİL');

      expect(expression, contains('full_name.ilike.%İSMAİL%'));
      expect(expression, contains('full_name.ilike.%ismail%'));
    });

    test('PostgREST or ifadesini bozabilecek arama karakterleri temizlenir', () {
      expect(sanitizeCustomerSearchTerm(' Me(h),met%_ '), 'Me h met');
      final expression = buildCustomerSearchOrExpression(' Me(h),met%_ ');

      expect(expression, contains('full_name.ilike.%Me h met%'));
      expect(expression, isNot(contains('(')));
      expect(expression, isNot(contains(')')));
    });
  });

  group('CustomerModel', () {
    test('telefon normalize edilir', () {
      final customer = CustomerModel(
        customerType: CustomerType.individual,
        fullName: 'Ali',
        phone: '+90 (505) 123 45 67',
        address: 'İstanbul',
        isActive: true,
      );

      expect(customer.normalizedPhone, '05051234567');
      expect(customer.whatsappUrl, 'https://wa.me/905051234567');
    });
  });

  group('CustomerFormScreen', () {
    testWidgets(
      'edit form acilisinda build exception uretmez ve alanlari doldurur',
      (tester) async {
        final repository = FakeCustomerRepository(
          customers: [
            CustomerModel(
              id: '1',
              customerType: CustomerType.individual,
              fullName: 'Ali Veli',
              phone: '05001112233',
              address: 'Istanbul',
              isActive: true,
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              customerRepositoryProvider.overrideWithValue(repository),
            ],
            child: const MaterialApp(
              home: CustomerFormScreen(role: AppRole.manager, customerId: '1'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Ali Veli'), findsOneWidget);
      },
    );

    testWidgets('rebuild sonrasi kullanici girdisi ezilmez', (tester) async {
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: '1',
            customerType: CustomerType.individual,
            fullName: 'Ali Veli',
            phone: '05001112233',
            address: 'Istanbul',
            isActive: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerFormScreen(role: AppRole.manager, customerId: '1'),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Yeni Isim');
      await tester.pump();

      expect(find.text('Yeni Isim'), findsOneWidget);
    });

    testWidgets('yeni form edit initialization calistirmaz', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerFormScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Yeni Müşteri'), findsOneWidget);
      expect(find.text('Ali Veli'), findsNothing);
    });

    testWidgets('kaydet cift tiklamada tek kayit olusturur', (tester) async {
      final repository = FakeCustomerRepository(
        createDelay: const Duration(milliseconds: 200),
      );
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerFormScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Ayse');
      await tester.enterText(textFields.at(2), '05051234567');
      await tester.enterText(find.byType(TextFormField).at(8), 'Kadikoy');

      final saveButton = find.byType(ElevatedButton);
      await tester.tap(saveButton);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(repository.createCount, 1);
    });
  });

  group('CustomerListScreen', () {
    testWidgets('edit navigation list index yerine müşteri UUIDsini route parametresi olarak kullanır', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: 'customer-x-uuid',
            customerType: CustomerType.individual,
            fullName: 'Müşteri X',
            phone: '05001112233',
            address: 'İstanbul',
            isActive: true,
          ),
          CustomerModel(
            id: 'customer-y-uuid',
            customerType: CustomerType.individual,
            fullName: 'Müşteri Y',
            phone: '05004445566',
            address: 'Ankara',
            isActive: true,
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: '/manager/customers',
        overridePlatformDefaultLocation: true,
        routes: [
          GoRoute(
            path: '/manager/customers',
            builder: (_, _) => CustomerListScreen(role: AppRole.manager),
          ),
          GoRoute(
            path: '/manager/customers/:customerId/edit',
            builder: (_, state) => Scaffold(
              body: Text('edit:${state.pathParameters['customerId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.listCallCount, greaterThan(0));
      final yCard = find.byKey(const ValueKey<String?>('customer-y-uuid'));
      expect(yCard, findsOneWidget);
      await tester.tap(find.descendant(of: yCard, matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();

      expect(find.text('edit:customer-y-uuid'), findsOneWidget);
      expect(find.text('edit:customer-x-uuid'), findsNothing);
    });

    testWidgets('arama debounce sonrasi repositoryye gider', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Ali');
      await tester.pump(const Duration(milliseconds: 200));
      expect(repository.lastFilters?['search'], isNot('Ali'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(repository.lastFilters?['search'], 'Ali');
    });

    testWidgets('arama temizlenince repository search bos gider', (
      tester,
    ) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mehmet');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.lastFilters?['search'], 'Mehmet');

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.lastFilters?['search'], '');
    });

    testWidgets('arama sirasinda diger filtreler korunur', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'Istanbul');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), 'Kadikoy');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Ali');
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.lastFilters?['search'], 'Ali');
      expect(repository.lastFilters?['city'], 'Istanbul');
      expect(repository.lastFilters?['district'], 'Kadikoy');
      expect(repository.lastFilters?['isActive'], isTrue);
    });

    testWidgets('bos arama sonucu hata degil kayit bulunamadi gosterir', (
      tester,
    ) async {
      final repository = FakeCustomerRepository(
        customers: [
          CustomerModel(
            id: '1',
            customerType: CustomerType.individual,
            fullName: 'Ali Veli',
            phone: '05001112233',
            address: 'Istanbul',
            isActive: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mehmet');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Kayıt bulunamadı.'), findsOneWidget);
      expect(find.text('Müşteriler yüklenemedi.'), findsNothing);
    });

    testWidgets('search tetigi debounce ile tek kez calisir', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final callCountBeforeSearch = repository.listCallCount;
      await tester.enterText(find.byType(TextField).first, 'Mehmet');
      await tester.pump(const Duration(milliseconds: 500));

      expect(repository.listCallCount, callCountBeforeSearch + 1);
    });

    testWidgets('sehir filtresi repositoryye trimli gider', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), ' Istanbul ');
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['city'], 'Istanbul');
    });

    testWidgets('ilce filtresi repositoryye trimli gider', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), ' Kadikoy ');
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['district'], 'Kadikoy');
    });

    testWidgets('pasif musterileri goster switchi filtreyi degistirir', (
      tester,
    ) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(repository.lastFilters?['isActive'], isTrue);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(repository.lastFilters?['isActive'], isNull);
    });

    testWidgets('filtre alani bosaltilinca eski filtre kalmaz', (tester) async {
      final repository = FakeCustomerRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [customerRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: CustomerListScreen(role: AppRole.manager),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'Ankara');
      await tester.pumpAndSettle();
      expect(repository.lastFilters?['city'], 'Ankara');

      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.pumpAndSettle();
      expect(repository.lastFilters?['city'], '');
    });
  });
}
