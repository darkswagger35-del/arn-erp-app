import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../models/customer_device_model.dart';
import '../../domain/repositories/device_repository.dart';

class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl({required this.client});

  final SupabaseClient client;

  static const String _selectColumns =
      'id, company_id, customer_id, brand, model, device_type, pump_type, serial_number, qr_code, membrane_type, installation_date, last_maintenance_date, next_maintenance_date, description, is_active, created_at, updated_at, deleted_at, customer:customers!customer_devices_customer_id_fkey(full_name, phone, address)';

  @visibleForTesting
  static Map<String, dynamic> buildUpdatePayloadForTest({
    required CustomerDeviceModel nextDevice,
    required CustomerDeviceModel existingDevice,
  }) {
    final payload = <String, dynamic>{};
    final normalizedCustomerId = _normalizeOptionalText(nextDevice.customerId);
    final existingCustomerId = _normalizeOptionalText(
      existingDevice.customerId,
    );
    final normalizedBrand = _normalizeOptionalText(nextDevice.brand);
    final normalizedModel = _normalizeOptionalText(nextDevice.model);
    final normalizedSerialNumber = _normalizeOptionalText(
      nextDevice.serialNumber,
    );
    final normalizedQrCode = _normalizeOptionalText(nextDevice.qrCode);
    final normalizedMembraneType = _normalizeOptionalText(
      nextDevice.membraneType,
    );
    final normalizedDescription = _normalizeOptionalText(
      nextDevice.description,
    );
    final existingBrand = _normalizeOptionalText(existingDevice.brand);
    final existingModel = _normalizeOptionalText(existingDevice.model);
    final existingSerialNumber = _normalizeOptionalText(
      existingDevice.serialNumber,
    );
    final existingQrCode = _normalizeOptionalText(existingDevice.qrCode);
    final existingMembraneType = _normalizeOptionalText(
      existingDevice.membraneType,
    );
    final existingDescription = _normalizeOptionalText(
      existingDevice.description,
    );
    final normalizedInstallationDate = _dateOnlyOrNull(
      nextDevice.installationDate,
    );
    final normalizedLastMaintenanceDate = _dateOnlyOrNull(
      nextDevice.lastMaintenanceDate,
    );
    final normalizedNextMaintenanceDate = _dateOnlyOrNull(
      nextDevice.nextMaintenanceDate,
    );
    final existingInstallationDate = _dateOnlyOrNull(
      existingDevice.installationDate,
    );
    final existingLastMaintenanceDate = _dateOnlyOrNull(
      existingDevice.lastMaintenanceDate,
    );
    final existingNextMaintenanceDate = _dateOnlyOrNull(
      existingDevice.nextMaintenanceDate,
    );

    if (normalizedCustomerId != existingCustomerId) {
      payload['customer_id'] = normalizedCustomerId;
    }
    if (normalizedBrand != existingBrand) {
      payload['brand'] = normalizedBrand;
    }
    if (normalizedModel != existingModel) {
      payload['model'] = normalizedModel;
    }
    if (nextDevice.deviceType.value != existingDevice.deviceType.value) {
      payload['device_type'] = nextDevice.deviceType.value;
    }
    if (nextDevice.pumpType.value != existingDevice.pumpType.value) {
      payload['pump_type'] = nextDevice.pumpType.value;
    }
    if (normalizedSerialNumber != existingSerialNumber) {
      payload['serial_number'] = normalizedSerialNumber;
    }
    if (normalizedQrCode != existingQrCode) {
      payload['qr_code'] = normalizedQrCode;
    }
    if (normalizedMembraneType != existingMembraneType) {
      payload['membrane_type'] = normalizedMembraneType;
    }
    if (normalizedInstallationDate != existingInstallationDate) {
      payload['installation_date'] = normalizedInstallationDate;
    }
    if (normalizedLastMaintenanceDate != existingLastMaintenanceDate) {
      payload['last_maintenance_date'] = normalizedLastMaintenanceDate;
    }
    if (normalizedNextMaintenanceDate != existingNextMaintenanceDate) {
      payload['next_maintenance_date'] = normalizedNextMaintenanceDate;
    }
    if (normalizedDescription != existingDescription) {
      payload['description'] = normalizedDescription;
    }
    if (nextDevice.isActive != existingDevice.isActive) {
      payload['is_active'] = nextDevice.isActive;
    }

    return payload;
  }

  @visibleForTesting
  static Map<String, dynamic> buildStatusPayloadForTest(bool isActive) {
    return <String, dynamic>{'is_active': isActive};
  }

  @visibleForTesting
  static Map<String, dynamic> buildSoftDeletePayloadForTest(
    DateTime timestamp,
  ) {
    return <String, dynamic>{
      'deleted_at': timestamp.toUtc().toIso8601String(),
      'is_active': false,
    };
  }

  @visibleForTesting
  static List<String> buildListQueryOperationPlanForTest({
    required bool hasCustomerId,
    required bool hasIsActive,
    required bool hasDeviceType,
    required bool hasPumpType,
    required bool hasSearch,
  }) {
    final plan = <String>['select', 'eq_company_id', 'filter_deleted_at'];
    if (hasCustomerId) {
      plan.add('eq_customer_id');
    }
    if (hasIsActive) {
      plan.add('eq_is_active');
    }
    if (hasDeviceType) {
      plan.add('eq_device_type');
    }
    if (hasPumpType) {
      plan.add('eq_pump_type');
    }
    if (hasSearch) {
      plan.add('or_search');
    }
    plan.add('order_created_at');
    plan.add('range');
    return plan;
  }

  static String? _normalizeOptionalText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String? _dateOnlyOrNull(DateTime? value) {
    if (value == null) {
      return null;
    }
    final utcValue = value.toUtc();
    final year = utcValue.year.toString().padLeft(4, '0');
    final month = utcValue.month.toString().padLeft(2, '0');
    final day = utcValue.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
  }) {
    return _listDevices(
      page: page,
      pageSize: pageSize,
      search: search,
      customerId: customerId,
      isActive: isActive,
      deviceType: deviceType,
      pumpType: pumpType,
    );
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
  }) {
    return _listDevices(
      page: page,
      pageSize: pageSize,
      search: search,
      customerId: customerId,
      isActive: isActive,
      deviceType: deviceType,
      pumpType: pumpType,
    );
  }

  @override
  Future<CustomerDeviceModel?> getDeviceById(String id) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      final response = await supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('id', id)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'getDeviceById',
        entityId: id,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'getDeviceById',
        entityId: id,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<CustomerDeviceModel> createDevice(CustomerDeviceModel device) async {
    final supabase = client;
    await _ensureWriteAccess(supabase);
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final payload = await _buildWritablePayload(
      supabase,
      device,
      companyId,
      isUpdate: false,
    );

    try {
      final response = await supabase
          .from('customer_devices')
          .insert(payload)
          .select(_selectColumns)
          .single();
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'createDevice',
        entityId: device.customerId,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'createDevice',
        entityId: device.customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<CustomerDeviceModel> updateDevice(CustomerDeviceModel device) async {
    final supabase = client;
    await _ensureWriteAccess(supabase);
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final deviceId = device.id;
    if (deviceId == null || deviceId.isEmpty) {
      throw const AppException('Cihaz bilgileri güncellenemedi.');
    }

    final existingDevice = await getDeviceById(deviceId);
    if (existingDevice == null) {
      throw const AppException('Cihaz bulunamadı.');
    }

    final payload = await _buildWritablePayload(
      supabase,
      device,
      companyId,
      isUpdate: true,
      existingDevice: existingDevice,
    );

    try {
      if (payload.isEmpty) {
        final response = await supabase
            .from('customer_devices')
            .select(_selectColumns)
            .eq('id', deviceId)
            .eq('company_id', companyId)
            .filter('deleted_at', 'is', null)
            .single();
        return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
      }

      final response = await supabase
          .from('customer_devices')
          .update(payload)
          .eq('id', deviceId)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .select(_selectColumns)
          .maybeSingle();
      if (response == null) {
        throw const AppException('Kayıt bulunamadı.');
      }
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'updateDevice',
        entityId: deviceId,
        error: error,
      );
      throw AppException(_translateError(error));
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'updateDevice',
        entityId: deviceId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<void> softDeleteDevice(String id) async {
    final supabase = client;
    await _ensureWriteAccess(supabase);
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final payload = <String, dynamic>{
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'is_active': false,
    };

    try {
      if (kDebugMode) {
        debugPrint(
          '[DeviceRepository] operation=softDeleteDevice deviceId=$id userId=${supabase.auth.currentUser?.id} companyId=$companyId payload=$payload clientHashCode=${supabase.hashCode}',
        );
      }
      _logQueryContext(
        operation: 'softDeleteDevice',
        entityId: id,
        companyId: companyId,
        filters: <String, dynamic>{
          'deviceId': id,
          'companyId': companyId,
          'deleted_at': null,
        },
      );
      await supabase
          .from('customer_devices')
          .update(payload)
          .eq('id', id)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null);
    } on PostgrestException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[DeviceRepository] PostgrestException message=${error.message} code=${error.code} details=${error.details} hint=${error.hint}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      _logPostgrestError(
        operation: 'softDeleteDevice',
        entityId: id,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateDeleteError(error));
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'softDeleteDevice',
        entityId: id,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateDeleteErrorMessage(error.toString()));
    }
  }

  @override
  Future<CustomerDeviceModel> changeDeviceStatus(
    String id,
    bool isActive,
  ) async {
    final supabase = client;
    await _ensureWriteAccess(supabase);
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      final response = await supabase
          .from('customer_devices')
          .update(buildStatusPayloadForTest(isActive))
          .eq('id', id)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .select(_selectColumns)
          .maybeSingle();
      if (response == null) {
        throw const AppException('Kayıt bulunamadı.');
      }
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'changeDeviceStatus',
        entityId: id,
        error: error,
      );
      throw AppException(_translateError(error));
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'changeDeviceStatus',
        entityId: id,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<CustomerDeviceModel?> findByQrCode(String qrCode) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final normalized = _trimToNull(qrCode);
    if (normalized == null) {
      return null;
    }

    try {
      final response = await supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .ilike('qr_code', normalized)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'findByQrCode',
        entityId: normalized,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'findByQrCode',
        entityId: normalized,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<CustomerDeviceModel?> findBySerialNumber(String serialNumber) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final normalized = serialNumber.trim();
    if (normalized.isEmpty) {
      return null;
    }

    try {
      final response = await supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .eq('serial_number', normalized)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return CustomerDeviceModel.fromMap(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'findBySerialNumber',
        entityId: normalized,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'findBySerialNumber',
        entityId: normalized,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<DevicePage> getUpcomingMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final today = DateTime.now().toUtc();
    final upperBound = today.add(const Duration(days: 30));

    try {
      final query = supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('company_id', companyId)
          .eq('is_active', true)
          .filter('deleted_at', 'is', null)
          .gte('next_maintenance_date', _dateOnly(today))
          .lte('next_maintenance_date', _dateOnly(upperBound))
          .order('created_at', ascending: false);

      final rows = await _paginate(query, page: page, pageSize: pageSize);
      return rows;
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'getUpcomingMaintenanceDevices',
        entityId: companyId,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'getUpcomingMaintenanceDevices',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  @override
  Future<DevicePage> getOverdueMaintenanceDevices({
    int page = 1,
    int pageSize = 25,
  }) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final today = DateTime.now().toUtc();

    try {
      final query = supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('company_id', companyId)
          .eq('is_active', true)
          .filter('deleted_at', 'is', null)
          .lt('next_maintenance_date', _dateOnly(today))
          .order('created_at', ascending: false);

      final rows = await _paginate(query, page: page, pageSize: pageSize);
      return rows;
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'getOverdueMaintenanceDevices',
        entityId: companyId,
        error: error,
      );
      throw AppException(_translateError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'getOverdueMaintenanceDevices',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateErrorMessage(error.toString()));
    }
  }

  Future<DevicePage> _listDevices({
    required int page,
    required int pageSize,
    required String search,
    required String? customerId,
    required bool? isActive,
    required String? deviceType,
    required String? pumpType,
  }) async {
    final supabase = client;
    final companyId = await _currentCompanyId(supabase);
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      _logQueryContext(
        operation: 'getDevices',
        entityId: companyId,
        companyId: companyId,
        filters: <String, dynamic>{
          'repositoryCalled': true,
          'search': search.trim(),
          'customerId': customerId,
          'isActive': isActive,
          'deviceType': deviceType,
          'pumpType': pumpType,
          'page': page,
          'pageSize': pageSize,
        },
      );
      PostgrestFilterBuilder<PostgrestList> filterQuery = supabase
          .from('customer_devices')
          .select(_selectColumns)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null);

      if (customerId != null && customerId.trim().isNotEmpty) {
        filterQuery = filterQuery.eq('customer_id', customerId.trim());
      }

      if (isActive != null) {
        filterQuery = filterQuery.eq('is_active', isActive);
      }

      if (deviceType != null && deviceType.trim().isNotEmpty) {
        filterQuery = filterQuery.eq('device_type', deviceType.trim());
      }

      if (pumpType != null && pumpType.trim().isNotEmpty) {
        filterQuery = filterQuery.eq('pump_type', pumpType.trim());
      }

      final term = search.trim();
      if (term.isNotEmpty) {
        final sanitizedTerm = _sanitizeSearchTerm(term);
        if (sanitizedTerm.isNotEmpty) {
          final customerIds = await _findMatchingCustomerIds(
            supabase,
            companyId: companyId,
            term: sanitizedTerm,
          );
          final filters = <String>[
            'brand.ilike.%$sanitizedTerm%',
            'model.ilike.%$sanitizedTerm%',
            'serial_number.ilike.%$sanitizedTerm%',
            'qr_code.ilike.%$sanitizedTerm%',
          ];
          if (customerIds.isNotEmpty) {
            filters.add('customer_id.in.(${customerIds.join(',')})');
          }
          filterQuery = filterQuery.or(filters.join(','));
        }
      }

      final transformQuery = filterQuery.order('created_at', ascending: false);
      final rows = await _paginate(
        transformQuery,
        page: page,
        pageSize: pageSize,
      );
      _logQueryResult(
        operation: 'getDevices',
        entityId: companyId,
        resultCount: rows.items.length,
      );
      return rows;
    } on PostgrestException catch (error, stackTrace) {
      _logPostgrestError(
        operation: 'getDevices',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateListError(error));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'getDevices',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateListErrorMessage(error.toString()));
    }
  }

  Future<DevicePage> _paginate(
    dynamic query, {
    required int page,
    required int pageSize,
  }) async {
    final start = (page - 1) * pageSize;
    final end = start + pageSize - 1;
    final response = await query.range(start, end);
    final rows = response as List<dynamic>;
    final items = rows
        .map(
          (row) => CustomerDeviceModel.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
    return DevicePage(items: items, hasMore: items.length >= pageSize);
  }

  Future<void> _ensureWriteAccess(SupabaseClient supabase) async {
    final isActive = await _isCurrentUserActive(supabase);
    if (!isActive) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final isAdmin = await _isAdmin(supabase);
    final isManager = await _isManager(supabase);
    final isSecretary = await _isSecretary(supabase);

    if (!isAdmin && !isManager && !isSecretary) {
      throw const AppException('Bu işlem için yetkiniz bulunmuyor.');
    }
  }

  Future<Map<String, dynamic>> _buildWritablePayload(
    SupabaseClient supabase,
    CustomerDeviceModel device,
    String companyId, {
    required bool isUpdate,
    CustomerDeviceModel? existingDevice,
  }) async {
    final normalizedCustomerId =
        (device.customerId ?? existingDevice?.customerId)?.trim();
    if (normalizedCustomerId == null || normalizedCustomerId.isEmpty) {
      throw const AppException('Müşteri bilgisi zorunludur.');
    }

    final normalizedBrand = _trimToNull(device.brand);
    final normalizedModel = _trimToNull(device.model);
    final normalizedSerialNumber = _trimToNull(device.serialNumber);
    final normalizedQrCode = _trimToNull(device.qrCode);
    final normalizedMembraneType = _trimToNull(device.membraneType);
    final normalizedInstallationDate = _dateOnlyOrNull(device.installationDate);
    final normalizedLastMaintenanceDate = _dateOnlyOrNull(
      device.lastMaintenanceDate,
    );
    final normalizedNextMaintenanceDate = _dateOnlyOrNull(
      device.nextMaintenanceDate,
    );
    final normalizedDescription = _trimToNull(device.description);

    final customerMatches = await supabase
        .from('customers')
        .select('id')
        .eq('id', normalizedCustomerId)
        .eq('company_id', companyId)
        .maybeSingle();
    if (customerMatches == null) {
      throw const AppException(
        'Cihaz, kendi şirketinizdeki bir müşteriye bağlı olmalıdır.',
      );
    }

    if (!isUpdate) {
      return <String, dynamic>{
        'company_id': companyId,
        'customer_id': normalizedCustomerId,
        'brand': normalizedBrand,
        'model': normalizedModel,
        'device_type': device.deviceType.value,
        'pump_type': device.pumpType.value,
        'serial_number': normalizedSerialNumber,
        'qr_code': normalizedQrCode,
        'membrane_type': normalizedMembraneType,
        'installation_date': normalizedInstallationDate,
        'last_maintenance_date': normalizedLastMaintenanceDate,
        'next_maintenance_date': normalizedNextMaintenanceDate,
        'description': normalizedDescription,
        'is_active': device.isActive,
      };
    }

    if (existingDevice == null) {
      throw const AppException('Cihaz bilgileri güncellenemedi.');
    }

    return buildUpdatePayloadForTest(
      nextDevice: device,
      existingDevice: existingDevice,
    );
  }

  Future<List<String>> _findMatchingCustomerIds(
    SupabaseClient supabase, {
    required String companyId,
    required String term,
  }) async {
    if (term.isEmpty) {
      return const <String>[];
    }

    final response = await supabase
        .from('customers')
        .select('id')
        .eq('company_id', companyId)
        .or('full_name.ilike.%$term%,company_name.ilike.%$term%')
        .limit(100);

    final rows = response as List<dynamic>;
    return rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<String?> _currentCompanyId(SupabaseClient supabase) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return null;
    }
    final response = await supabase.rpc('current_user_company_id');
    return response?.toString();
  }

  Future<bool> _isCurrentUserActive(SupabaseClient supabase) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return false;
    }
    final response = await supabase.rpc('is_current_user_active');
    return response as bool? ?? false;
  }

  Future<bool> _isAdmin(SupabaseClient supabase) async {
    final response = await supabase.rpc('is_admin');
    return response as bool? ?? false;
  }

  Future<bool> _isManager(SupabaseClient supabase) async {
    final response = await supabase.rpc('is_manager');
    return response as bool? ?? false;
  }

  Future<bool> _isSecretary(SupabaseClient supabase) async {
    final response = await supabase.rpc('is_secretary');
    return response as bool? ?? false;
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _sanitizeSearchTerm(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[%_(),]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized;
  }

  String _dateOnly(DateTime value) {
    final utcValue = value.toUtc();
    final year = utcValue.year.toString().padLeft(4, '0');
    final month = utcValue.month.toString().padLeft(2, '0');
    final day = utcValue.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _translateError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.code ?? ''}'
            .toLowerCase();
    if (message.contains('permission') ||
        message.contains('policy') ||
        message.contains('yetkiniz')) {
      return 'Bu işlem için yetkiniz bulunmuyor.';
    }
    if (message.contains('no rows') ||
        message.contains('0 rows') ||
        message.contains('json object requested')) {
      return 'Kayıt bulunamadı.';
    }
    if (message.contains('customer_devices_company_qr_normalized_unique') ||
        message.contains('idx_customer_devices_company_qr_normalized_unique') ||
        message.contains('duplicate key value violates unique constraint') ||
        message.contains('unique')) {
      return 'Bu QR kodu başka bir cihazda kullanılıyor.';
    }
    if (message.contains('network') ||
        message.contains('timeout') ||
        message.contains('socket') ||
        message.contains('failed')) {
      return 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
    }
    return 'İşlem sırasında beklenmeyen bir hata oluştu.';
  }

  String _translateListError(PostgrestException error) {
    final specific = _translateError(error);
    if (specific == 'İşlem sırasında beklenmeyen bir hata oluştu.') {
      return 'Cihazlar yüklenemedi.';
    }
    return specific;
  }

  String _translateDeleteError(PostgrestException error) {
    final specific = _translateError(error);
    if (specific == 'İşlem sırasında beklenmeyen bir hata oluştu.') {
      return 'Cihaz silinemedi.';
    }
    return specific;
  }

  String _translateErrorMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('permission') ||
        normalized.contains('policy') ||
        normalized.contains('yetkiniz')) {
      return 'Bu işlem için yetkiniz bulunmuyor.';
    }
    if (normalized.contains('no rows') ||
        normalized.contains('record not found') ||
        normalized.contains('json object requested')) {
      return 'Kayıt bulunamadı.';
    }
    if (normalized.contains('qr') && normalized.contains('unique')) {
      return 'Bu QR kodu başka bir cihazda kullanılıyor.';
    }
    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('socket') ||
        normalized.contains('failed')) {
      return 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
    }
    return 'İşlem sırasında beklenmeyen bir hata oluştu.';
  }

  String _translateListErrorMessage(String message) {
    final specific = _translateErrorMessage(message);
    if (specific == 'İşlem sırasında beklenmeyen bir hata oluştu.') {
      return 'Cihazlar yüklenemedi.';
    }
    return specific;
  }

  String _translateDeleteErrorMessage(String message) {
    final specific = _translateErrorMessage(message);
    if (specific == 'İşlem sırasında beklenmeyen bir hata oluştu.') {
      return 'Cihaz silinemedi.';
    }
    return specific;
  }

  Future<void> _logPostgrestError({
    required String operation,
    required String? entityId,
    required PostgrestException error,
    StackTrace? stackTrace,
  }) async {
    if (!kDebugMode) {
      return;
    }
    final profile = await _currentProfileSummary();
    debugPrint(
      '[DeviceRepository] operation=$operation entityId=$entityId userId=${client.auth.currentUser?.id} role=${profile?['role']} companyId=${profile?['company_id']}',
    );
    debugPrint(
      '[DeviceRepository] PostgrestException message=${error.message} code=${error.code} details=${error.details} hint=${error.hint}',
    );
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _logQueryContext({
    required String operation,
    required String? entityId,
    required String? companyId,
    required Map<String, dynamic> filters,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[DeviceRepository] operation=$operation entityId=$entityId userId=${client.auth.currentUser?.id} companyId=$companyId filters=$filters',
    );
  }

  void _logQueryResult({
    required String operation,
    required String? entityId,
    required int resultCount,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[DeviceRepository] operation=$operation entityId=$entityId resultCount=$resultCount',
    );
  }

  void _logUnexpectedError({
    required String operation,
    required String? entityId,
    required Object error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[DeviceRepository] operation=$operation entityId=$entityId userId=${client.auth.currentUser?.id} unexpectedError=$error',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  Future<Map<String, dynamic>?> _currentProfileSummary() async {
    final user = client.auth.currentUser;
    if (user == null) {
      return null;
    }
    try {
      final response = await client
          .from('profiles')
          .select('company_id, role')
          .eq('id', user.id)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return Map<String, dynamic>.from(response);
    } catch (_) {
      return null;
    }
  }
}
