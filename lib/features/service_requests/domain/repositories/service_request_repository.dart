import '../../data/models/service_request_model.dart';

abstract class ServiceRequestRepository {
  Future<List<ServiceRequestModel>> getServiceRequests({
    ServiceRequestStatus? status,
    String? technicianId,
  });

  Future<ServiceRequestModel?> getServiceRequestById(String serviceRequestId);

  Future<ServiceRequestModel> createServiceRequest(ServiceRequestModel request);

  Future<ServiceRequestModel> updateServiceRequest(ServiceRequestModel request);

  Future<void> assignTechnician({
    required String serviceRequestId,
    required String technicianId,
    DateTime? plannedDate,
  });

  Future<void> unassignTechnician({required String serviceRequestId});

  Future<void> updateRoutePlan({
    required String serviceRequestId,
    required String technicianId,
    required int routeOrder,
    required DateTime routePlanDate,
  });

  Future<void> updateStatus({
    required String serviceRequestId,
    required ServiceRequestStatus status,
  });

  Future<void> cancelServiceRequest({
    required String serviceRequestId,
    required String reason,
  });

  Future<void> reopenCancelledService({required String serviceRequestId});

  Future<void> addToSecretaryFollowUp({
    required String serviceRequestId,
    required DateTime followUpAt,
    String note = '',
  });

  Future<String> sendOverdueToSecretary({
    required String serviceRequestId,
    String? secretaryId,
  });

  Future<String> recreateServiceFromRework({required String serviceRequestId});

  Future<void> submitReworkToManager({
    required String serviceRequestId,
    ServiceRequestModel? snapshot,
  });

  Future<void> deleteServiceRequest(String serviceRequestId);

  Future<void> deleteCompletedService(String serviceRequestId);
}
