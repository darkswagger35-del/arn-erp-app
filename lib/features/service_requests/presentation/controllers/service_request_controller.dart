import 'package:flutter/foundation.dart';

import '../../data/models/service_request_model.dart';
import '../../domain/repositories/service_request_repository.dart';

class ServiceRequestState {
  const ServiceRequestState({
    this.serviceRequests = const [],
    this.currentServiceRequest,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
  });

  final List<ServiceRequestModel> serviceRequests;
  final ServiceRequestModel? currentServiceRequest;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;

  static const Object _unset = Object();

  T? _pick<T>(Object? value, T? current) {
    if (identical(value, _unset)) {
      return current;
    }

    return value as T?;
  }

  ServiceRequestState copyWith({
    List<ServiceRequestModel>? serviceRequests,
    Object? currentServiceRequest = _unset,
    bool? isLoading,
    bool? isSaving,
    Object? errorMessage = _unset,
    Object? successMessage = _unset,
  }) {
    return ServiceRequestState(
      serviceRequests: serviceRequests ?? this.serviceRequests,
      currentServiceRequest: _pick<ServiceRequestModel?>(
        currentServiceRequest,
        this.currentServiceRequest,
      ),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: _pick<String?>(errorMessage, this.errorMessage),
      successMessage: _pick<String?>(successMessage, this.successMessage),
    );
  }
}

class ServiceRequestController extends ChangeNotifier {
  ServiceRequestController({required this.repository});

  final ServiceRequestRepository repository;

  ServiceRequestState _state = const ServiceRequestState();

  ServiceRequestState get state => _state;

  Future<void> loadServiceRequests({
    ServiceRequestStatus? status,
    String? technicianId,
  }) async {
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      final serviceRequests = await repository.getServiceRequests(
        status: status,
        technicianId: technicianId,
      );

      _state = _state.copyWith(
        serviceRequests: serviceRequests,
        isLoading: false,
      );
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Servis talepleri yüklenemedi.',
      );
    }

    notifyListeners();
  }

  Future<void> loadServiceRequest(String serviceRequestId) async {
    _state = _state.copyWith(
      isLoading: true,
      currentServiceRequest: null,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      final request = await repository.getServiceRequestById(serviceRequestId);

      _state = _state.copyWith(
        currentServiceRequest: request,
        isLoading: false,
      );
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Servis talebi yüklenemedi.',
      );
    }

    notifyListeners();
  }

  Future<bool> createServiceRequest(ServiceRequestModel request) async {
    if (_state.isSaving) {
      return false;
    }

    final validationError = _validate(request);

    if (validationError != null) {
      _state = _state.copyWith(
        errorMessage: validationError,
        successMessage: null,
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      final created = await repository.createServiceRequest(request);

      _state = _state.copyWith(
        serviceRequests: [created, ..._state.serviceRequests],
        currentServiceRequest: created,
        isSaving: false,
        successMessage: 'Servis talebi oluşturuldu.',
      );

      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Servis talebi oluşturulamadı.',
      );

      notifyListeners();
      return false;
    }
  }

  Future<bool> updateServiceRequest(ServiceRequestModel request) async {
    if (_state.isSaving) {
      return false;
    }

    final validationError = _validate(request);

    if (validationError != null) {
      _state = _state.copyWith(
        errorMessage: validationError,
        successMessage: null,
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      final updated = await repository.updateServiceRequest(request);

      final updatedList = _state.serviceRequests
          .map((item) {
            if (item.id == updated.id) {
              return updated;
            }

            return item;
          })
          .toList(growable: false);

      _state = _state.copyWith(
        serviceRequests: updatedList,
        currentServiceRequest: updated,
        isSaving: false,
        successMessage: 'Servis talebi güncellendi.',
      );

      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Servis talebi güncellenemedi.',
      );

      notifyListeners();
      return false;
    }
  }

  Future<bool> assignTechnician({
    required String serviceRequestId,
    required String technicianId,
    DateTime? plannedDate,
  }) async {
    if (_state.isSaving) {
      return false;
    }

    if (technicianId.trim().isEmpty) {
      _state = _state.copyWith(
        errorMessage: 'Tekniker seçimi zorunludur.',
        successMessage: null,
      );
      notifyListeners();
      return false;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      await repository.assignTechnician(
        serviceRequestId: serviceRequestId,
        technicianId: technicianId.trim(),
        plannedDate: plannedDate,
      );

      await loadServiceRequests();

      _state = _state.copyWith(
        isSaving: false,
        successMessage: 'Tekniker atandı.',
      );

      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Tekniker atanamadı.',
      );

      notifyListeners();
      return false;
    }
  }

  Future<bool> unassignTechnician(String serviceRequestId) async {
    if (_state.isSaving) return false;
    _state = _state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await repository.unassignTechnician(serviceRequestId: serviceRequestId);
      await loadServiceRequests();
      _state = _state.copyWith(isSaving: false, successMessage: 'Teknisyen ataması iptal edildi. Talep onay bekliyor durumuna alındı.');
      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(isSaving: false, errorMessage: 'Teknisyen ataması iptal edilemedi.');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStatus({
    required String serviceRequestId,
    required ServiceRequestStatus status,
  }) async {
    if (_state.isSaving) {
      return false;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      await repository.updateStatus(
        serviceRequestId: serviceRequestId,
        status: status,
      );

      final updatedList = _state.serviceRequests
          .map((item) {
            if (item.id == serviceRequestId) {
              return item.copyWith(status: status, updatedAt: DateTime.now());
            }

            return item;
          })
          .toList(growable: false);

      _state = _state.copyWith(
        serviceRequests: updatedList,
        isSaving: false,
        successMessage: 'Servis durumu güncellendi.',
      );

      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Servis durumu güncellenemedi.',
      );

      notifyListeners();
      return false;
    }
  }


  Future<bool> cancelServiceRequest({
    required String serviceRequestId,
    required String reason,
  }) async {
    if (_state.isSaving) return false;
    _state = _state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await repository.cancelServiceRequest(
        serviceRequestId: serviceRequestId,
        reason: reason,
      );
      await loadServiceRequests();
      _state = _state.copyWith(isSaving: false, successMessage: 'Servis iptal edildi.');
      notifyListeners();
      return true;
    } catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: 'Servis iptal edilemedi: $error');
      notifyListeners();
      return false;
    }
  }

  Future<bool> reopenCancelledService(String serviceRequestId) async {
    if (_state.isSaving) return false;
    _state = _state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await repository.reopenCancelledService(serviceRequestId: serviceRequestId);
      await loadServiceRequests();
      _state = _state.copyWith(isSaving: false, successMessage: 'İptal edilen servis yeniden açıldı.');
      notifyListeners();
      return true;
    } catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: 'Servis yeniden açılamadı: $error');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCompletedService(String serviceRequestId) async {
    if (_state.isSaving) return false;
    _state = _state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    notifyListeners();
    try {
      await repository.deleteCompletedService(serviceRequestId);
      _state = _state.copyWith(
        serviceRequests: _state.serviceRequests.where((item) => item.id != serviceRequestId).toList(growable: false),
        isSaving: false,
        successMessage: 'Tamamlanan servis silindi; ciro ve tahsilat kaldırıldı, stok geri yüklendi.',
      );
      notifyListeners();
      return true;
    } catch (error) {
      _state = _state.copyWith(isSaving: false, errorMessage: 'Tamamlanan servis silinemedi: $error');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteServiceRequest(String serviceRequestId) async {
    if (_state.isSaving) {
      return false;
    }

    _state = _state.copyWith(
      isSaving: true,
      errorMessage: null,
      successMessage: null,
    );
    notifyListeners();

    try {
      await repository.deleteServiceRequest(serviceRequestId);

      final updatedList = _state.serviceRequests
          .where((item) => item.id != serviceRequestId)
          .toList(growable: false);

      _state = _state.copyWith(
        serviceRequests: updatedList,
        currentServiceRequest:
            _state.currentServiceRequest?.id == serviceRequestId
            ? null
            : _state.currentServiceRequest,
        isSaving: false,
        successMessage: 'Servis talebi silindi.',
      );

      notifyListeners();
      return true;
    } catch (_) {
      _state = _state.copyWith(
        isSaving: false,
        errorMessage: 'Servis talebi silinemedi.',
      );

      notifyListeners();
      return false;
    }
  }

  void clearCurrentServiceRequest() {
    _state = _state.copyWith(currentServiceRequest: null);
    notifyListeners();
  }

  void clearMessages() {
    _state = _state.copyWith(errorMessage: null, successMessage: null);
    notifyListeners();
  }

  String? _validate(ServiceRequestModel request) {
    if (request.customerId.trim().isEmpty) {
      return 'Müşteri seçimi zorunludur.';
    }

    return null;
  }
}
