import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exception.dart';
import '../../data/models/customer_model.dart';
import '../../domain/repositories/customer_repository.dart';

/// Columns searched by the customer text search (`or()` ilike expression).
const List<String> customerSearchColumns = [
  'full_name',
];

/// Removes characters that would otherwise break a PostgREST `or()` filter
/// expression (`%`, `_`, `(`, `)`, `,`) and collapses/trims whitespace.
String sanitizeCustomerSearchTerm(String value) {
  return value
      .replaceAll(RegExp(r'[%_(),]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Standard `ilike` is already case-insensitive for regular Latin letters
/// (and even for accented Turkish letters such as ç/Ç, ğ/Ğ, ö/Ö, ş/Ş, ü/Ü,
/// which have a simple one-to-one case mapping). The one pair that default
/// (non-Turkish) case folding does **not** unify is the dotted/dotless "I":
/// `İ`/`i` and `I`/`ı`. This helper produces the sanitized term plus, when
/// applicable, one extra variant with those four characters swapped so the
/// `or()` expression can also match records saved with the other spelling.
///
/// This is a best-effort, app-level mitigation only. It has not been
/// validated against a live Postgres collation and does not guarantee full
/// Turkish case-folding correctness (see repository notes).
List<String> turkishSearchTermVariants(String sanitizedTerm) {
  if (sanitizedTerm.isEmpty) {
    return const [];
  }

  final variants = <String>{sanitizedTerm};
  final canonical = sanitizedTerm
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i');
  variants.add(canonical);
  final buffer = StringBuffer();
  for (final rune in sanitizedTerm.runes) {
    final ch = String.fromCharCode(rune);
    switch (ch) {
      case 'i':
        buffer.write('İ');
        break;
      case 'I':
        buffer.write('ı');
        break;
      case 'İ':
        buffer.write('i');
        break;
      case 'ı':
        buffer.write('I');
        break;
      default:
        buffer.write(ch);
    }
  }
  final swapped = buffer.toString();
  if (swapped != sanitizedTerm) {
    variants.add(swapped);
  }

  return variants.toList(growable: false);
}

/// Builds the PostgREST `or()` filter expression for the customer text
/// search, covering [customerSearchColumns] and Turkish I/İ/ı variants.
/// Returns an empty string when [rawTerm] sanitizes to nothing.
String buildCustomerSearchOrExpression(String rawTerm) {
  final sanitized = sanitizeCustomerSearchTerm(rawTerm);
  if (sanitized.isEmpty) {
    return '';
  }

  final variants = turkishSearchTermVariants(sanitized);
  return variants
      .expand(
        (variant) =>
            customerSearchColumns.map((column) => '$column.ilike.%$variant%'),
      )
      .join(',');
}

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl({this.client});

  final SupabaseClient? client;

  @override
  Future<CustomerPage> listCustomers({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String phone = '',
    bool? isActive,
    String city = '',
    String district = '',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final companyId = profile['company_id']?.toString();
    final role = profile['role']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      _logQueryContext(
        operation: 'listCustomers',
        entityId: companyId,
        companyId: companyId,
        filters: <String, dynamic>{
          'repositoryCalled': true,
          'search': search.trim(),
          'phone': phone.trim(),
          'isActive': isActive,
          'city': city.trim(),
          'district': district.trim(),
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'page': page,
          'pageSize': pageSize,
          'role': role,
        },
      );
      PostgrestFilterBuilder<PostgrestList> filterQuery = supabase
          .from('customers')
          .select(
            'id, company_id, customer_type, full_name, company_name, phone, alternative_phone, email, city, district, neighborhood, address, latitude, longitude, maps_url, notes, is_active, created_by, updated_by, created_at, updated_at, registration_date',
          )
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null);

      if (role == 'secretary') {
        // Sekreter yalnızca kendi oluşturduğu müşterileri görür; aktif/pasif
        // filtresi de yönetici ekranındakiyle aynı şekilde uygulanır.
        filterQuery = filterQuery.eq('created_by', profile['id']);
        if (isActive != null) {
          filterQuery = filterQuery.eq('is_active', isActive);
        }
      } else if (role == 'technician') {
        filterQuery = filterQuery.eq('is_active', true);
      } else if (isActive != null) {
        filterQuery = filterQuery.eq('is_active', isActive);
      }

      if (search.trim().isNotEmpty) {
        final orExpression = buildCustomerSearchOrExpression(search);
        if (orExpression.isNotEmpty) {
          filterQuery = filterQuery.or(orExpression);
        }
      }

      if (phone.trim().isNotEmpty) {
        final rawPhone = phone
            .trim()
            .replaceAll(RegExp(r'[%_(),]'), '')
            .replaceAll(RegExp(r'\s+'), ' ');
        final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
        final phoneVariants = <String>{};
        if (rawPhone.isNotEmpty) phoneVariants.add(rawPhone);
        if (normalizedPhone.isNotEmpty) phoneVariants.add(normalizedPhone);
        if (normalizedPhone.length >= 10) {
          phoneVariants.add(normalizedPhone.substring(normalizedPhone.length - 10));
        }
        if (phoneVariants.isNotEmpty) {
          filterQuery = filterQuery.or(
            phoneVariants.map((value) => 'phone.ilike.%$value%').join(','),
          );
        }
      }

      if (city.trim().isNotEmpty) {
        filterQuery = filterQuery.ilike('city', '%${city.trim()}%');
      }

      if (district.trim().isNotEmpty) {
        filterQuery = filterQuery.ilike('district', '%${district.trim()}%');
      }

      // Müşteri kayıt/yapım tarihi filtresi. Eski kayıtların da doğru
      // aralıkta bulunabilmesi için registration_date alanı kullanılır.
      if (startDate != null) {
        final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
        filterQuery = filterQuery.gte('registration_date', startOfDay.toIso8601String());
      }
      if (endDate != null) {
        final nextDay = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
        filterQuery = filterQuery.lt('registration_date', nextDay.toIso8601String());
      }

      final start = (page - 1) * pageSize;
      final end = start + pageSize - 1;
      final transformQuery = filterQuery
          .order('is_active', ascending: false)
          .order('full_name', ascending: true)
          .range(start, end);
      final response = await transformQuery;
      final rows = response as List<dynamic>;
      final items = rows
          .map((row) => CustomerModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      _logQueryResult(
        operation: 'listCustomers',
        entityId: companyId,
        resultCount: items.length,
      );
      return CustomerPage(items: items, hasMore: items.length >= pageSize);
    } on PostgrestException catch (error, stackTrace) {
      _logPostgrestError(
        operation: 'listCustomers',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateListError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'listCustomers',
        entityId: companyId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateListError(error.toString()));
    }
  }

  @override
  Future<CustomerModel> createCustomer(CustomerModel customer) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final role = profile['role']?.toString();
    if (role != 'manager' && role != 'secretary' && role != 'admin') {
      throw const AppException('Bu işlem için yetkiniz bulunmuyor.');
    }

    final payload = await _buildPayload(
      supabase,
      customer,
      profile,
      isUpdate: false,
    );
    try {
      final response = await supabase
          .from('customers')
          .insert(payload)
          .select()
          .single();
      return CustomerModel.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'createCustomer',
        entityId: profile['id']?.toString(),
        error: error,
      );
      throw AppException(_translateError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'createCustomer',
        entityId: profile['id']?.toString(),
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.toString()));
    }
  }

  @override
  Future<CustomerModel> updateCustomer(CustomerModel customer) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final role = profile['role']?.toString();
    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }
    final technicianMayEdit = role == 'technician' &&
        await _companyPermission(
          supabase,
          companyId,
          'technician_edit_customers',
          fallback: true,
        );
    if (role != 'manager' &&
        role != 'secretary' &&
        role != 'admin' &&
        !technicianMayEdit) {
      throw const AppException('Bu işlem için yetkiniz bulunmuyor.');
    }

    final customerId = customer.id;
    if (customerId == null || customerId.isEmpty) {
      throw const AppException('Müşteri bilgileri güncellenemedi.');
    }

    final payload = await _buildPayload(
      supabase,
      customer,
      profile,
      isUpdate: true,
    );
    try {
      final response = await supabase
          .from('customers')
          .update(payload)
          .eq('id', customerId)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .select()
          .single();
      return CustomerModel.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'updateCustomer',
        entityId: customerId,
        error: error,
      );
      throw AppException(_translateError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'updateCustomer',
        entityId: customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.toString()));
    }
  }

  @override
  Future<void> toggleActive(String customerId, bool isActive) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final role = profile['role']?.toString();
    if (role != 'manager' && role != 'secretary' && role != 'admin') {
      throw const AppException('Bu işlem için yetkiniz bulunmuyor.');
    }

    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      await supabase
          .from('customers')
          .update({'is_active': isActive, 'updated_by': profile['id']})
          .eq('id', customerId)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null);
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'toggleActive',
        entityId: customerId,
        error: error,
      );
      throw AppException(_translateError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'toggleActive',
        entityId: customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.toString()));
    }
  }

  @override
  Future<void> deleteCustomer(String customerId) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final role = profile['role']?.toString();
    if (role != 'manager' && role != 'secretary' && role != 'admin') {
      throw const AppException('Bu işlem için yetkiniz bulunmuyor.');
    }

    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      await supabase.rpc(
        'hard_delete_customer',
        params: {'p_customer_id': customerId},
      );
    } on PostgrestException catch (error, stackTrace) {
      _logPostgrestError(
        operation: 'deleteCustomer',
        entityId: customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'deleteCustomer',
        entityId: customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.toString()));
    }
  }

  @override
  Future<CustomerModel?> getCustomer(String customerId) async {
    final supabase = client ?? _ensureClient();
    final profile = await _currentProfile(supabase);
    if (profile == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    try {
      final response = await supabase
          .from('customers')
          .select()
          .eq('id', customerId)
          .eq('company_id', companyId)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      if (response == null) {
        return null;
      }
      return CustomerModel.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (error) {
      _logPostgrestError(
        operation: 'getCustomer',
        entityId: customerId,
        error: error,
      );
      throw AppException(_translateError(error.message));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        operation: 'getCustomer',
        entityId: customerId,
        error: error,
        stackTrace: stackTrace,
      );
      throw AppException(_translateError(error.toString()));
    }
  }

  Future<Map<String, dynamic>?> _currentProfile(SupabaseClient supabase) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return null;
    }

    final response = await supabase
        .from('profiles')
        .select('id, company_id, role')
        .eq('id', user.id)
        .maybeSingle();
    if (response == null) {
      return null;
    }
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> _companyBehaviorSettings(
    SupabaseClient supabase,
    String companyId,
  ) async {
    try {
      final row = await supabase
          .from('company_app_settings')
          .select('permissions, customer_rules')
          .eq('company_id', companyId)
          .maybeSingle();
      return row == null ? const <String, dynamic>{} : Map<String, dynamic>.from(row);
    } catch (_) {
      // Yeni kontrol merkezi migrationı henüz uygulanmadıysa mevcut güvenli
      // varsayılanlarla çalışmaya devam et.
      return const <String, dynamic>{};
    }
  }

  Future<bool> _companyPermission(
    SupabaseClient supabase,
    String companyId,
    String key, {
    required bool fallback,
  }) async {
    final settings = await _companyBehaviorSettings(supabase, companyId);
    final raw = settings['permissions'];
    if (raw is Map && raw[key] is bool) return raw[key] as bool;
    return fallback;
  }

  Future<Map<String, dynamic>> _buildPayload(
    SupabaseClient supabase,
    CustomerModel customer,
    Map<String, dynamic> profile, {
    required bool isUpdate,
  }) async {
    final normalizedPhone = _normalizePhone(customer.phone);
    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final behavior = await _companyBehaviorSettings(supabase, companyId);
    final customerRules = behavior['customer_rules'];
    bool rule(String key, bool fallback) {
      if (customerRules is Map && customerRules[key] is bool) {
        return customerRules[key] as bool;
      }
      return fallback;
    }

    final phoneRequired = rule('phone_required', true);
    final duplicatePhoneCheck = rule('duplicate_phone_check', true);
    if (normalizedPhone.isEmpty && phoneRequired) {
      throw const AppException('Telefon alanı zorunludur.');
    }

    if (normalizedPhone.isNotEmpty && duplicatePhoneCheck) {
      final duplicateId = await supabase.rpc(
        'find_customer_by_phone_v9',
        params: {
          'p_phone': normalizedPhone,
          'p_exclude_customer_id': isUpdate ? customer.id : null,
        },
      );

      if (duplicateId != null && duplicateId.toString().isNotEmpty) {
        throw const AppException(
          'Bu telefon numarasıyla kayıtlı bir müşteri bulunuyor.',
        );
      }
    }

    final payload = <String, dynamic>{
      'company_id': companyId,
      'customer_type': customer.customerType.value,
      'full_name': customer.fullName.trim(),
      'company_name': customer.companyName?.trim().isNotEmpty == true
          ? customer.companyName!.trim()
          : null,
      'phone': normalizedPhone,
      'alternative_phone': customer.alternativePhone?.trim().isNotEmpty == true
          ? _normalizePhone(customer.alternativePhone!)
          : null,
      'email': customer.email?.trim().isNotEmpty == true
          ? customer.email!.trim()
          : null,
      'city': customer.city?.trim().isNotEmpty == true
          ? customer.city!.trim()
          : null,
      'district': customer.district?.trim().isNotEmpty == true
          ? customer.district!.trim()
          : null,
      'neighborhood': customer.neighborhood?.trim().isNotEmpty == true
          ? customer.neighborhood!.trim()
          : null,
      'address': customer.address.trim(),
      'latitude': customer.latitude,
      'longitude': customer.longitude,
      'maps_url': customer.mapsUrl?.trim().isNotEmpty == true
          ? customer.mapsUrl!.trim()
          : null,
      'notes': customer.notes?.trim().isNotEmpty == true
          ? customer.notes!.trim()
          : null,
      'is_active': customer.isActive,
      'updated_by': profile['id'],
      'created_by': isUpdate
          ? customer.createdBy ?? profile['id']
          : profile['id'],
      'registration_date': (customer.registrationDate ?? DateTime.now()).toUtc().toIso8601String(),
    };

    if (!isUpdate) {
      payload['created_at'] = (customer.registrationDate ?? DateTime.now()).toUtc().toIso8601String();
    }

    return payload;
  }

  String _normalizePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final numeric = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeric.startsWith('90') && numeric.length > 10) {
      return '0${numeric.substring(2)}';
    }
    if (numeric.startsWith('0')) {
      return numeric;
    }
    if (numeric.length == 10) {
      return '0$numeric';
    }
    return numeric;
  }

  String _translateError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('permission') || normalized.contains('policy')) {
      return 'Bu işlem için yetkiniz bulunmuyor.';
    }
    if (normalized.contains('no rows') ||
        normalized.contains('record not found') ||
        normalized.contains('json object requested')) {
      return 'Kayıt bulunamadı.';
    }
    if ((normalized.contains('duplicate') || normalized.contains('unique')) &&
        (normalized.contains('phone') || normalized.contains('telefon') || normalized.contains('customers_company_phone'))) {
      return 'Bu telefon numarasıyla kayıtlı bir müşteri bulunuyor.';
    }
    if (normalized.contains('duplicate') || normalized.contains('unique')) {
      return 'Aynı bilgilerle kayıtlı başka bir kayıt bulunuyor.';
    }
    if (normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('socket') ||
        normalized.contains('failed')) {
      return 'Bağlantı kurulamadı. Lütfen tekrar deneyin.';
    }
    if (normalized.contains('pgrst202') || normalized.contains('hard_delete_customer')) {
      return 'Müşteri silme veritabanı güncellemesi eksik. V15 SQL dosyasını çalıştırın.';
    }
    return 'İşlem sırasında beklenmeyen bir hata oluştu: $message';
  }

  String _translateListError(String message) {
    final specific = _translateError(message);
    if (specific == 'İşlem sırasında beklenmeyen bir hata oluştu.') {
      return 'Müşteriler yüklenemedi.';
    }
    return specific;
  }

  void _logPostgrestError({
    required String operation,
    required String? entityId,
    required PostgrestException error,
    StackTrace? stackTrace,
  }) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[CustomerRepository] operation=$operation entityId=$entityId userId=${client?.auth.currentUser?.id ?? Supabase.instance.client.auth.currentUser?.id}',
    );
    debugPrint(
      '[CustomerRepository] PostgrestException message=${error.message} code=${error.code} details=${error.details} hint=${error.hint}',
    );
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
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
      '[CustomerRepository] operation=$operation entityId=$entityId userId=${client?.auth.currentUser?.id ?? Supabase.instance.client.auth.currentUser?.id} unexpectedError=$error',
    );
    debugPrintStack(stackTrace: stackTrace);
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
      '[CustomerRepository] operation=$operation entityId=$entityId userId=${client?.auth.currentUser?.id ?? Supabase.instance.client.auth.currentUser?.id} companyId=$companyId filters=$filters',
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
      '[CustomerRepository] operation=$operation entityId=$entityId resultCount=$resultCount',
    );
  }

  SupabaseClient _ensureClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }
}
