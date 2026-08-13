import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_exception.dart';
import '../../data/models/customer_model.dart';
import '../../domain/repositories/customer_repository.dart';

class CustomerState {
  const CustomerState({
    this.customers = const [],
    this.currentCustomer,
    this.isLoading = false,
    this.isSaving = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.errorMessage,
    this.successMessage,
    this.page = 1,
    this.pageSize = 25,
    this.search = '',
    this.isActive,
    this.city = '',
    this.district = '',
    this.startDate,
    this.endDate,
  });

  final List<CustomerModel> customers;
  final CustomerModel? currentCustomer;
  final bool isLoading;
  final bool isSaving;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final String? successMessage;
  final int page;
  final int pageSize;
  final String search;
  final bool? isActive;
  final String city;
  final String district;
  final DateTime? startDate;
  final DateTime? endDate;

  static const Object _unset = Object();

  T? _pick<T>(Object? value, T? current) {
    if (identical(value, _unset)) {
      return current;
    }
    return value as T?;
  }

  CustomerState copyWith({
    List<CustomerModel>? customers,
    Object? currentCustomer = _unset,
    bool? isLoading,
    bool? isSaving,
    bool? isLoadingMore,
    bool? hasMore,
    Object? errorMessage = _unset,
    Object? successMessage = _unset,
    int? page,
    int? pageSize,
    String? search,
    Object? isActive = _unset,
    String? city,
    String? district,
    Object? startDate = _unset,
    Object? endDate = _unset,
  }) {
    return CustomerState(
      customers: customers ?? this.customers,
      currentCustomer: _pick<CustomerModel?>(
        currentCustomer,
        this.currentCustomer,
      ),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: _pick<String?>(errorMessage, this.errorMessage),
      successMessage: _pick<String?>(successMessage, this.successMessage),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      isActive: _pick<bool?>(isActive, this.isActive),
      city: city ?? this.city,
      district: district ?? this.district,
      startDate: _pick<DateTime?>(startDate, this.startDate),
      endDate: _pick<DateTime?>(endDate, this.endDate),
    );
  }
}

class CustomerController extends ChangeNotifier {
  CustomerController({required this.repository});

  final CustomerRepository repository;
  CustomerState _state = const CustomerState();
  Timer? _debounceTimer;
  int _requestSequence = 0;
  int _customerRequestSequence = 0;

  CustomerState get state => _state;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> refresh() => loadCustomers(resetPage: true);

  Future<void> loadCustomers({
    String? search,
    Object? isActive = CustomerState._unset,
    String? city,
    String? district,
    Object? startDate = CustomerState._unset,
    Object? endDate = CustomerState._unset,
    bool resetPage = true,
  }) async {
    final normalizedSearch = search?.trim();
    final normalizedCity = city?.trim();
    final normalizedDistrict = district?.trim();
    _state = _state.copyWith(
      search: normalizedSearch ?? _state.search,
      isActive: isActive,
      city: normalizedCity ?? _state.city,
      district: normalizedDistrict ?? _state.district,
      startDate: startDate,
      endDate: endDate,
    );

    final requestId = ++_requestSequence;
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
      page: resetPage ? 1 : _state.page,
    );
    notifyListeners();

    try {
      final page = resetPage ? 1 : _state.page;
      final response = await repository.listCustomers(
        page: page,
        pageSize: _state.pageSize,
        search: _state.search,
        isActive: _state.isActive,
        city: _state.city,
        district: _state.district,
        startDate: _state.startDate,
        endDate: _state.endDate,
      );
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        customers: response.items,
        isLoading: false,
        hasMore: response.hasMore,
        page: page,
      );
    } on AppException catch (error) {
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Müşteriler yüklenemedi.',
      );
    }
    notifyListeners();
  }

  Future<void> loadMoreCustomers({
    String? search,
    Object? isActive = CustomerState._unset,
    String? city,
    String? district,
    Object? startDate = CustomerState._unset,
    Object? endDate = CustomerState._unset,
  }) async {
    if (_state.isLoadingMore || !_state.hasMore) {
      return;
    }

    final normalizedSearch = search?.trim();
    final normalizedCity = city?.trim();
    final normalizedDistrict = district?.trim();
    _state = _state.copyWith(
      search: normalizedSearch ?? _state.search,
      isActive: isActive,
      city: normalizedCity ?? _state.city,
      district: normalizedDistrict ?? _state.district,
      startDate: startDate,
      endDate: endDate,
    );

    final requestId = ++_requestSequence;
    _state = _state.copyWith(isLoadingMore: true, errorMessage: null);
    notifyListeners();

    try {
      final nextPage = _state.page + 1;
      final response = await repository.listCustomers(
        page: nextPage,
        pageSize: _state.pageSize,
        search: _state.search,
        isActive: _state.isActive,
        city: _state.city,
        district: _state.district,
        startDate: _state.startDate,
        endDate: _state.endDate,
      );
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        customers: [..._state.customers, ...response.items],
        isLoadingMore: false,
        hasMore: response.hasMore,
        page: nextPage,
      );
    } on AppException catch (error) {
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        isLoadingMore: false,
        errorMessage: error.message,
      );
    } catch (_) {
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Daha fazla müşteri yüklenemedi.',
      );
    }
    notifyListeners();
  }

  void updateSearch(String value) {
    final normalized = value.trim();
    _debounceTimer?.cancel();
    _state = _state.copyWith(
      search: normalized,
      page: 1,
      errorMessage: null,
      successMessage: null,
      customers: const <CustomerModel>[],
    );
    notifyListeners();

    // Arama kutusunda yazılan değer doğrudan veritabanına uygulanır.
    // Kısa gecikme sadece hızlı yazarken gereksiz istekleri azaltır.
    _debounceTimer = Timer(const Duration(milliseconds: 120), () {
      loadCustomers(search: normalized, resetPage: true);
    });
  }

  void updateFilters({
    required String city,
    required String district,
    required bool? isActive,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    _debounceTimer?.cancel();
    _requestSequence++;
    _state = _state.copyWith(
      city: city.trim(),
      district: district.trim(),
      isActive: isActive,
      startDate: startDate,
      endDate: endDate,
      page: 1,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();
    loadCustomers(resetPage: true);
  }

  Future<void> saveCustomer(
    CustomerModel customer, {
    bool phoneRequired = true,
    bool addressRequired = true,
  }) async {
    if (_state.isSaving) {
      return;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    final validationError = _validate(
      customer,
      phoneRequired: phoneRequired,
      addressRequired: addressRequired,
    );
    if (validationError != null) {
      _state = _state.copyWith(isSaving: false, errorMessage: validationError);
      notifyListeners();
      return;
    }

    final normalizedCustomer = customer.copyWith(
      fullName: customer.fullName.trim(),
      phone: _normalizePhone(customer.phone),
      alternativePhone: customer.alternativePhone != null
          ? _normalizePhone(customer.alternativePhone!)
          : null,
      companyName: customer.companyName?.trim(),
      address: customer.address.trim(),
      email: customer.email?.trim(),
      city: customer.city?.trim(),
      district: customer.district?.trim(),
      neighborhood: customer.neighborhood?.trim(),
      mapsUrl: customer.mapsUrl?.trim(),
    );

    try {
      if (normalizedCustomer.id == null || normalizedCustomer.id!.isEmpty) {
        await repository.createCustomer(
          normalizedCustomer.copyWith(isActive: true),
        );
      } else {
        await repository.updateCustomer(normalizedCustomer);
      }
      await loadCustomers(resetPage: true);
      _state = _state.copyWith(
        isSaving: false,
        successMessage: 'Müşteri başarıyla kaydedildi.',
      );
      if (normalizedCustomer.id != null &&
          _state.currentCustomer?.id == normalizedCustomer.id) {
        await loadCustomer(normalizedCustomer.id!);
      }
    } on AppException catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Müşteri kaydedilemedi.',
      );
    }
    notifyListeners();
  }

  Future<void> loadCustomer(String customerId) async {
    final requestId = ++_customerRequestSequence;
    // Clear any previously loaded customer immediately so a screen can never
    // display stale data (e.g. a different customer's details) while the
    // new one is being fetched.
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      currentCustomer: null,
    );
    notifyListeners();

    try {
      final customer = await repository.getCustomer(customerId);
      if (requestId != _customerRequestSequence) {
        // A newer loadCustomer() call superseded this one; discard the
        // result to avoid a race where an older response overwrites the
        // correct, more recent customer.
        return;
      }
      _state = _state.copyWith(currentCustomer: customer, isLoading: false);
    } on AppException catch (error) {
      if (requestId != _customerRequestSequence) {
        return;
      }
      _state = _state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      if (requestId != _customerRequestSequence) {
        return;
      }
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Müşteri yüklenemedi.',
      );
    }
    notifyListeners();
  }

  /// Clears the currently selected customer from shared state. Screens
  /// should call this when they no longer own/display a customer detail so
  /// stale data cannot leak into the next screen that reuses this
  /// controller.
  void clearCurrentCustomer() {
    ++_customerRequestSequence;
    _state = _state.copyWith(currentCustomer: null);
    notifyListeners();
  }

  Future<void> toggleActive(String customerId, bool isActive) async {
    if (_state.isSaving) {
      return;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      // Freeze criteria at mutation start to ensure the refresh uses the
      // currently selected filters/pagination (including active/passive mode).
      final criteria = _state;
      _debounceTimer?.cancel();
      _requestSequence++;
      await repository.toggleActive(customerId, isActive);
      await _reloadCustomersForMutation(criteria);

      // Keep filtered views consistent even if a stale server snapshot is
      // returned: remove the toggled record if it no longer matches the
      // current active/passive filter.
      if (criteria.isActive != null && criteria.isActive != isActive) {
        _state = _state.copyWith(
          customers: _state.customers
              .where((customer) => customer.id != customerId)
              .toList(growable: false),
        );
      }

      _state = _state.copyWith(
        isSaving: false,
        successMessage: 'Müşteri durumu güncellendi.',
      );
      if (_state.currentCustomer?.id == customerId) {
        await loadCustomer(customerId);
      }
    } on AppException catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Müşteri durumu güncellenemedi.',
      );
    }
    notifyListeners();
  }

  Future<void> _reloadCustomersForMutation(CustomerState criteria) async {
    final requestId = ++_requestSequence;
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
      search: criteria.search,
      city: criteria.city,
      district: criteria.district,
      isActive: criteria.isActive,
      startDate: criteria.startDate,
      endDate: criteria.endDate,
      page: criteria.page,
      pageSize: criteria.pageSize,
    );
    notifyListeners();

    try {
      final response = await repository.listCustomers(
        page: criteria.page,
        pageSize: criteria.pageSize,
        search: criteria.search,
        isActive: criteria.isActive,
        city: criteria.city,
        district: criteria.district,
        startDate: criteria.startDate,
        endDate: criteria.endDate,
      );
      if (requestId != _requestSequence) {
        return;
      }
      _state = _state.copyWith(
        customers: response.items,
        isLoading: false,
        hasMore: response.hasMore,
        page: criteria.page,
        pageSize: criteria.pageSize,
      );
    } on AppException {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      rethrow;
    } catch (_) {
      _state = _state.copyWith(isLoading: false);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    if (_state.isSaving) {
      return;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      await repository.deleteCustomer(customerId);
      final wasCurrentCustomer = _state.currentCustomer?.id == customerId;
      _state = _state.copyWith(
        currentCustomer: wasCurrentCustomer ? null : _state.currentCustomer,
      );
      await loadCustomers(resetPage: true);
      _state = _state.copyWith(
        isSaving: false,
        successMessage: 'Müşteri silindi.',
      );
    } on AppException catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: error.message);
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Müşteri silinemedi.',
      );
    }
    notifyListeners();
  }

  String _normalizePhone(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.startsWith('90') && digitsOnly.length > 10) {
      return '0${digitsOnly.substring(2)}';
    }
    if (digitsOnly.startsWith('0')) {
      return digitsOnly;
    }
    if (digitsOnly.length == 10) {
      return '0$digitsOnly';
    }
    return digitsOnly;
  }

  String? _validate(
    CustomerModel customer, {
    bool phoneRequired = true,
    bool addressRequired = true,
  }) {
    if (customer.customerType == CustomerType.corporate &&
        (customer.companyName?.trim().isEmpty ?? true)) {
      return 'Kurumsal müşteriler için firma adı zorunludur.';
    }

    if (customer.customerType == CustomerType.individual &&
        customer.fullName.trim().isEmpty) {
      return 'Ad soyad zorunludur.';
    }

    if (phoneRequired && customer.phone.trim().isEmpty) {
      return 'Telefon alanı zorunludur.';
    }

    if (addressRequired && customer.address.trim().isEmpty) {
      return 'Adres alanı zorunludur.';
    }

    if (customer.email?.trim().isNotEmpty == true &&
        !RegExp(
          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
        ).hasMatch(customer.email!.trim())) {
      return 'Geçerli bir e-posta adresi girin.';
    }

    if (customer.mapsUrl?.trim().isNotEmpty == true &&
        !Uri.tryParse(customer.mapsUrl!.trim())!.hasScheme) {
      return 'Harita bağlantısı geçersiz.';
    }

    if (customer.latitude != null &&
        (customer.latitude! < -90 || customer.latitude! > 90)) {
      return 'Enlem -90 ile 90 arasında olmalıdır.';
    }

    if (customer.longitude != null &&
        (customer.longitude! < -180 || customer.longitude! > 180)) {
      return 'Boylam -180 ile 180 arasında olmalıdır.';
    }

    return null;
  }
}
