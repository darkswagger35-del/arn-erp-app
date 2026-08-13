import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../data/models/customer_device_model.dart';
import '../../domain/repositories/device_repository.dart';

const Object _unset = Object();

T? _pick<T>(Object? value, T? current) {
  if (identical(value, _unset)) {
    return current;
  }
  return value as T?;
}

class DeviceState {
  const DeviceState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isSaving = false,
    this.hasMore = false,
    this.page = 1,
    this.pageSize = 25,
    this.search = '',
    this.customerId,
    this.isActive,
    this.deviceType,
    this.pumpType,
    this.errorMessage,
    this.successMessage,
  });

  final List<CustomerDeviceModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isSaving;
  final bool hasMore;
  final int page;
  final int pageSize;
  final String search;
  final String? customerId;
  final bool? isActive;
  final String? deviceType;
  final String? pumpType;
  final String? errorMessage;
  final String? successMessage;

  DeviceState copyWith({
    List<CustomerDeviceModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isSaving,
    bool? hasMore,
    int? page,
    int? pageSize,
    String? search,
    Object? customerId = _unset,
    Object? isActive = _unset,
    Object? deviceType = _unset,
    Object? pumpType = _unset,
    Object? errorMessage = _unset,
    Object? successMessage = _unset,
  }) {
    return DeviceState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isSaving: isSaving ?? this.isSaving,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      search: search ?? this.search,
      customerId: _pick<String?>(customerId, this.customerId),
      isActive: _pick<bool?>(isActive, this.isActive),
      deviceType: _pick<String?>(deviceType, this.deviceType),
      pumpType: _pick<String?>(pumpType, this.pumpType),
      errorMessage: _pick<String?>(errorMessage, this.errorMessage),
      successMessage: _pick<String?>(successMessage, this.successMessage),
    );
  }
}

class DeviceController extends StateNotifier<DeviceState> {
  DeviceController({required this.repository}) : super(const DeviceState());

  final DeviceRepository repository;
  Timer? _debounceTimer;
  int _requestSequence = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDevices({bool resetPage = true}) async {
    final requestId = ++_requestSequence;
    final page = resetPage ? 1 : state.page;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      errorMessage: null,
      successMessage: null,
      page: page,
      items: resetPage ? const [] : state.items,
    );

    try {
      final response = await repository.getDevices(
        page: page,
        pageSize: state.pageSize,
        search: state.search,
        customerId: state.customerId,
        isActive: state.isActive,
        deviceType: state.deviceType,
        pumpType: state.pumpType,
      );
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(
        items: response.items,
        isLoading: false,
        hasMore: response.hasMore,
        page: page,
      );
    } on AppException catch (error) {
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(isLoading: false, errorMessage: error.message);
    } catch (_) {
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Cihazlar yüklenemedi.',
      );
    }
  }

  Future<void> refresh() => loadDevices(resetPage: true);

  Future<void> loadMoreDevices() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }

    final requestId = ++_requestSequence;
    state = state.copyWith(
      isLoadingMore: true,
      errorMessage: null,
      successMessage: null,
    );

    try {
      final nextPage = state.page + 1;
      final response = await repository.getDevices(
        page: nextPage,
        pageSize: state.pageSize,
        search: state.search,
        customerId: state.customerId,
        isActive: state.isActive,
        deviceType: state.deviceType,
        pumpType: state.pumpType,
      );
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(
        items: [...state.items, ...response.items],
        isLoadingMore: false,
        hasMore: response.hasMore,
        page: nextPage,
      );
    } on AppException catch (error) {
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(isLoadingMore: false, errorMessage: error.message);
    } catch (_) {
      if (requestId != _requestSequence || !mounted) {
        return;
      }
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Daha fazla cihaz yüklenemedi.',
      );
    }
  }

  void updateSearch(String value) {
    final normalized = value.trim();
    state = state.copyWith(
      search: normalized,
      page: 1,
      errorMessage: null,
      successMessage: null,
    );
    _debounceTimer?.cancel();
    final requestId = ++_requestSequence;
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || requestId != _requestSequence) {
        return;
      }
      loadDevices(resetPage: true);
    });
  }

  void updateFilters({
    Object? customerId = _unset,
    Object? isActive = _unset,
    Object? deviceType = _unset,
    Object? pumpType = _unset,
  }) {
    _debounceTimer?.cancel();
    _requestSequence++;
    state = state.copyWith(
      customerId: customerId,
      isActive: isActive,
      deviceType: deviceType,
      pumpType: pumpType,
      page: 1,
      errorMessage: null,
      successMessage: null,
    );
    loadDevices(resetPage: true);
  }

  Future<CustomerDeviceModel> saveDevice(CustomerDeviceModel device) {
    if (device.id == null || device.id!.isEmpty) {
      return createDevice(device);
    }
    return updateDevice(device);
  }

  Future<CustomerDeviceModel> createDevice(CustomerDeviceModel device) async {
    state = state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final saved = await repository.createDevice(_normalizeDevice(device));
      await loadDevices(resetPage: true);
      state = state.copyWith(
        isSaving: false,
        successMessage: 'Cihaz başarıyla kaydedildi.',
      );
      return saved;
    } on AppException catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Cihaz kaydedilemedi.',
      );
      throw const AppException('Cihaz kaydedilemedi.');
    }
  }

  Future<CustomerDeviceModel> updateDevice(CustomerDeviceModel device) async {
    state = state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final saved = await repository.updateDevice(_normalizeDevice(device));
      await loadDevices(resetPage: true);
      state = state.copyWith(
        isSaving: false,
        successMessage: 'Cihaz başarıyla güncellendi.',
      );
      return saved;
    } on AppException catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Cihaz güncellenemedi.',
      );
      throw const AppException('Cihaz güncellenemedi.');
    }
  }

  Future<void> softDeleteDevice(String id) async {
    state = state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      await repository.softDeleteDevice(id);
      final updatedItems = state.items
          .where((item) => item.id != id)
          .toList(growable: false);
      state = state.copyWith(
        isSaving: false,
        items: updatedItems,
        successMessage: 'Cihaz silindi.',
      );
    } on AppException catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Cihaz silinemedi.',
      );
      throw const AppException('Cihaz silinemedi.');
    }
  }

  Future<CustomerDeviceModel> changeDeviceStatus(
    String id,
    bool isActive,
  ) async {
    state = state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    try {
      final saved = await repository.changeDeviceStatus(id, isActive);
      await loadDevices(resetPage: true);
      state = state.copyWith(
        isSaving: false,
        successMessage: 'Cihaz durumu güncellendi.',
      );
      return saved;
    } on AppException catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.message);
      rethrow;
    } catch (_) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Cihaz durumu güncellenemedi.',
      );
      throw const AppException('Cihaz durumu güncellenemedi.');
    }
  }

  CustomerDeviceModel _normalizeDevice(CustomerDeviceModel device) {
    return device.copyWith(
      brand: _trimToNull(device.brand),
      model: _trimToNull(device.model),
      serialNumber: _trimToNull(device.serialNumber),
      qrCode: _trimToNull(device.qrCode),
      membraneType: _trimToNull(device.membraneType),
      description: _trimToNull(device.description),
      customerName: _trimToNull(device.customerName),
      customerPhone: _trimToNull(device.customerPhone),
      customerAddress: _trimToNull(device.customerAddress),
    );
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
