import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/service_request_repository.dart';
import '../models/service_request_model.dart';

class ServiceRequestRepositoryImpl implements ServiceRequestRepository {
  ServiceRequestRepositoryImpl({required this._client});

  final SupabaseClient _client;

  @override
  Future<List<ServiceRequestModel>> getServiceRequests({
    ServiceRequestStatus? status,
    String? technicianId,
  }) async {
    final currentUser = _client.auth.currentUser;
    var secretaryScope = false;
    if (currentUser != null) {
      try {
        final profile = await _client
            .from('profiles')
            .select('role')
            .eq('id', currentUser.id)
            .maybeSingle();
        secretaryScope = profile?['role']?.toString() == 'secretary';
      } catch (_) {
        // Asıl güvenlik Supabase RLS politikasındadır.
      }
    }

    dynamic buildQuery({required bool includeReworkScope}) {
      dynamic query = _client.from('service_requests').select();
      if (secretaryScope && currentUser != null) {
        query = includeReworkScope
            ? query.or(
                'created_by.eq.${currentUser.id},rework_secretary_id.eq.${currentUser.id}',
              )
            : query.eq('created_by', currentUser.id);
      }
      if (status != null) {
        query = query.eq('status', status.value);
      }
      if (technicianId != null && technicianId.trim().isNotEmpty) {
        query = query.eq('assigned_technician_id', technicianId.trim());
      }
      return query.order('created_at', ascending: false);
    }

    dynamic response;
    try {
      response = await buildQuery(includeReworkScope: true);
    } catch (error) {
      // Yeni rework migrationı henüz uygulanmadıysa eski sürümde liste ekranını
      // tamamen kırmayalım. Migration uygulandıktan sonra geniş sekreter kapsamı
      // otomatik devreye girer.
      final text = error.toString().toLowerCase();
      if (secretaryScope && text.contains('rework_secretary_id')) {
        response = await buildQuery(includeReworkScope: false);
      } else {
        rethrow;
      }
    }

    final requests = (response as List<dynamic>)
        .map(
          (item) => ServiceRequestModel.fromMap(item as Map<String, dynamic>),
        )
        .toList();

    // Tamamlanamayan / iptal edilen kayıtlar operasyon geçmişidir; yeni servis
    // açılmış olsa bile listeden saklanmaz. Böylece sekreter ve yönetici eski
    // işlemi, teknikerini ve notlarını sonradan da görebilir.
    return _enrichRequests(requests);
  }

  Future<List<ServiceRequestModel>> _enrichRequests(
    List<ServiceRequestModel> requests,
  ) async {
    if (requests.isEmpty) {
      return requests;
    }

    final customerIds = requests
        .map((item) => item.customerId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final requestIds = requests
        .map((item) => item.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final technicianIds = requests
        .map((item) => item.assignedTechnicianId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final customerMap = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      final rows = await _client
          .from('customers')
          .select('id, full_name, company_name, phone, address, city, district, neighborhood')
          .inFilter('id', customerIds);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        customerMap[map['id'].toString()] = map;
      }
    }

    final itemMap = <String, List<ServiceRequestItem>>{};
    if (requestIds.isNotEmpty) {
      final rows = await _client
          .from('service_items')
          .select('service_request_id, product_name, quantity, unit_price, line_total')
          .inFilter('service_request_id', requestIds)
          .order('created_at', ascending: true);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        final requestId = map['service_request_id']?.toString() ?? '';
        if (requestId.isEmpty) continue;
        itemMap.putIfAbsent(requestId, () => <ServiceRequestItem>[])
            .add(ServiceRequestItem.fromMap(map));
      }
    }

    final technicianMap = <String, String>{};
    if (technicianIds.isNotEmpty) {
      final rows = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', technicianIds);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        technicianMap[map['id'].toString()] =
            map['full_name']?.toString() ?? '';
      }
    }

    return requests
        .map((request) {
          final customer = customerMap[request.customerId];
          final fullName = customer?['full_name']?.toString().trim() ?? '';
          final companyName =
              customer?['company_name']?.toString().trim() ?? '';
          return request.copyWith(
            customerName: fullName.isNotEmpty ? fullName : companyName,
            customerPhone: customer?['phone']?.toString() ?? '',
            customerAddress: customer?['address']?.toString() ?? '',
            customerCity: customer?['city']?.toString() ?? '',
            customerDistrict: customer?['district']?.toString() ?? '',
            customerNeighborhood: customer?['neighborhood']?.toString() ?? '',
            assignedTechnicianName: request.assignedTechnicianId != null &&
                    request.assignedTechnicianId!.trim().isNotEmpty
                ? technicianMap[request.assignedTechnicianId] ??
                    request.technicianNameSnapshot
                : request.technicianNameSnapshot,
            items: itemMap[request.id] ?? const [],
          );
        })
        .toList(growable: false);
  }

  @override
  Future<ServiceRequestModel?> getServiceRequestById(String id) async {
    final response = await _client
        .from('service_requests')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    final enriched = await _enrichRequests([
      ServiceRequestModel.fromMap(response),
    ]);
    return enriched.first;
  }

  @override
  Future<ServiceRequestModel> createServiceRequest(
    ServiceRequestModel request,
  ) async {
    final data = Map<String, dynamic>.from(request.toMap())..remove('id');
    final currentUser = _client.auth.currentUser;
    if ((data['created_by'] == null || data['created_by'].toString().isEmpty) && currentUser != null) {
      data['created_by'] = currentUser.id;
    }
    if (currentUser != null) {
      final profile = await _client
          .from('profiles')
          .select('company_id')
          .eq('id', currentUser.id)
          .maybeSingle();
      final companyId = profile?['company_id']?.toString();
      if (companyId != null && companyId.isNotEmpty) {
        data['company_id'] = companyId;
      }
    }

    final response = await _client
        .from('service_requests')
        .insert(data)
        .select()
        .single();
    return ServiceRequestModel.fromMap(response);
  }

  @override
  Future<ServiceRequestModel> updateServiceRequest(
    ServiceRequestModel request,
  ) async {
    final id = request.id;
    if (id == null || id.trim().isEmpty) {
      throw ArgumentError(
        'Güncellenecek servis talebinin ID değeri bulunamadı.',
      );
    }
    final data = Map<String, dynamic>.from(request.toMap())
      ..remove('id')
      // Talebi açan kişi sabit kalır; yönetici/teknisyen düzenlemeleri
      // created_by alanını asla değiştirmez.
      ..remove('created_by')
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from('service_requests')
        .update(data)
        .eq('id', id)
        .select()
        .single();
    return ServiceRequestModel.fromMap(response);
  }

  @override
  Future<void> assignTechnician({
    required String serviceRequestId,
    required String technicianId,
    DateTime? plannedDate,
  }) async {
    final technician = await _client
        .from('profiles')
        .select('company_id, role, is_active')
        .eq('id', technicianId)
        .maybeSingle();
    if (technician == null ||
        technician['role']?.toString() != 'technician' ||
        technician['is_active'] != true) {
      throw const PostgrestException(
        message: 'Aktif teknisyen profili bulunamadı.',
        code: 'TECHNICIAN_NOT_FOUND',
      );
    }

    final data = <String, dynamic>{
      'assigned_technician_id': technicianId,
      'company_id': technician['company_id'],
      'status': ServiceRequestStatus.assigned.value,
      'route_order': null,
      'route_plan_date': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (plannedDate != null) {
      data['planned_date'] = plannedDate.toUtc().toIso8601String();
    }
    await _client
        .from('service_requests')
        .update(data)
        .eq('id', serviceRequestId);
  }

  @override
  Future<void> updateRoutePlan({
    required String serviceRequestId,
    required String technicianId,
    required int routeOrder,
    required DateTime routePlanDate,
  }) async {
    final date = DateTime(routePlanDate.year, routePlanDate.month, routePlanDate.day);
    await _client.from('service_requests').update({
      'assigned_technician_id': technicianId,
      'status': ServiceRequestStatus.assigned.value,
      'route_order': routeOrder,
      'route_plan_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', serviceRequestId);
  }

  @override
  Future<void> unassignTechnician({required String serviceRequestId}) async {
    await _client.from('service_requests').update({
      'assigned_technician_id': null,
      // Atama kaldırılırken planlanan tarih korunur. Yönetici işi tekrar
      // planlarken tarihi kaybetmemeli.
      'status': ServiceRequestStatus.approved.value,
      'route_order': null,
      'route_plan_date': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', serviceRequestId);
  }

  @override
  Future<void> updateStatus({
    required String serviceRequestId,
    required ServiceRequestStatus status,
  }) async {
    await _client
        .from('service_requests')
        .update({
          'status': status.value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', serviceRequestId);
  }


  @override
  Future<void> cancelServiceRequest({
    required String serviceRequestId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw ArgumentError('İptal nedeni zorunludur.');
    }

    // Önce durumu doğrudan cancelled yapıyoruz. Böylece RPC / metadata
    // tarafında bir sorun olsa bile kayıt Bekleyen Atamalar'a geri düşmez.
    final currentUser = _client.auth.currentUser;
    String cancelledByName = '';
    if (currentUser != null) {
      try {
        final profile = await _client
            .from('profiles')
            .select('full_name')
            .eq('id', currentUser.id)
            .maybeSingle();
        cancelledByName = profile?['full_name']?.toString().trim() ?? '';
      } catch (_) {}
    }

    final baseUpdate = <String, dynamic>{
      'status': ServiceRequestStatus.cancelled.value,
      'route_order': null,
      'route_plan_date': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _client.from('service_requests').update({
        ...baseUpdate,
        'cancellation_reason': cleanReason,
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
        'cancelled_by': currentUser?.id,
        'cancelled_by_name': cancelledByName,
      }).eq('id', serviceRequestId);
    } catch (_) {
      // Eski veritabanında iptal metadata kolonları henüz yoksa bile
      // servis mutlaka cancelled durumuna geçsin.
      await _client
          .from('service_requests')
          .update(baseUpdate)
          .eq('id', serviceRequestId);
    }

    // RPC varsa metadata/yetki kurallarını da çalıştır. Ancak bu çağrının
    // başarısız olması artık statüyü pending'e geri çeviremez.
    try {
      await _client.rpc('cancel_service_request_v2', params: {
        'p_service_request_id': serviceRequestId,
        'p_reason': cleanReason,
      });
    } catch (_) {}
  }

  @override
  Future<void> reopenCancelledService({required String serviceRequestId}) async {
    await _client.rpc('reopen_cancelled_service_v2', params: {
      'p_service_request_id': serviceRequestId,
    });
  }

  @override
  Future<void> addToSecretaryFollowUp({
    required String serviceRequestId,
    required DateTime followUpAt,
    String note = '',
  }) async {
    await _client.rpc(
      'secretary_track_service_v1',
      params: {
        'p_service_request_id': serviceRequestId,
        'p_follow_up_at': followUpAt.toUtc().toIso8601String(),
        'p_note': note.trim(),
      },
    );
  }

  @override
  Future<String> sendOverdueToSecretary({
    required String serviceRequestId,
    String? secretaryId,
  }) async {
    final result = await _client.rpc(
      'send_overdue_service_to_secretary_v1',
      params: {
        'p_service_request_id': serviceRequestId,
        'p_secretary_id': secretaryId,
      },
    );
    if (result is Map) {
      return result['secretary_name']?.toString() ?? 'Sekreter';
    }
    return 'Sekreter';
  }

  @override
  Future<String> recreateServiceFromRework({required String serviceRequestId}) async {
    final result = await _client.rpc(
      'recreate_service_from_rework_v1',
      params: {'p_service_request_id': serviceRequestId},
    );
    if (result is Map) {
      return result['new_service_request_id']?.toString() ?? '';
    }
    return '';
  }

  @override
  Future<void> submitReworkToManager({
    required String serviceRequestId,
    ServiceRequestModel? snapshot,
  }) async {
    final paramsV3 = <String, dynamic>{
      'p_service_request_id': serviceRequestId,
      if (snapshot != null) ...{
        'p_planned_date': snapshot.plannedDate?.toUtc().toIso8601String(),
        'p_service_type': snapshot.serviceType.value,
        'p_description': snapshot.description.trim(),
        'p_product_id': snapshot.plannedProductId,
        'p_product_name': snapshot.plannedProductName.trim(),
        'p_quantity': snapshot.plannedQuantity,
        'p_unit_price': snapshot.plannedUnitPrice,
        'p_price': snapshot.price,
      },
    };

    try {
      await _client.rpc(
        'submit_rework_service_to_manager_v3',
        params: paramsV3,
      );
      return;
    } catch (error) {
      final text = error.toString().toLowerCase();
      final missingV3 = text.contains('submit_rework_service_to_manager_v3') &&
          (text.contains('could not find') ||
              text.contains('does not exist') ||
              text.contains('pgrst202'));
      if (!missingV3) rethrow;
    }

    // V2 migration kuruluysa mevcut taslak akışını kullan.
    try {
      await _client.rpc(
        'submit_rework_service_to_manager_v2',
        params: {'p_service_request_id': serviceRequestId},
      );
      return;
    } catch (error) {
      final text = error.toString().toLowerCase();
      final missingV2 = text.contains('submit_rework_service_to_manager_v2') &&
          (text.contains('could not find') ||
              text.contains('does not exist') ||
              text.contains('pgrst202'));
      if (!missingV2) rethrow;
    }

    // Eski V1 veritabanlarında da sekreter akışını kilitlemeyelim. V1 RPC yeni
    // pending kaydı üretir; ardından sekreterin seçtiği yeni tarih / ürün / fiyat
    // bilgilerini bu yeni kayda taşırız.
    final legacyResult = await _client.rpc(
      'recreate_service_from_rework_v1',
      params: {'p_service_request_id': serviceRequestId},
    );
    final newId = legacyResult is Map
        ? legacyResult['new_service_request_id']?.toString() ?? ''
        : '';
    if (newId.isEmpty) {
      throw const PostgrestException(
        message: 'Yeniden planlanan servis oluşturulamadı.',
        code: 'REWORK_CREATE_FAILED',
      );
    }

    if (snapshot != null) {
      await _client.from('service_requests').update({
        'service_type': snapshot.serviceType.value,
        'planned_date': snapshot.plannedDate?.toUtc().toIso8601String(),
        'description': snapshot.description.trim(),
        'planned_product_id': snapshot.plannedProductId,
        'planned_product_name': snapshot.plannedProductName.trim(),
        'planned_quantity': snapshot.plannedQuantity,
        'planned_unit_price': snapshot.plannedUnitPrice,
        'price': snapshot.price,
        'assigned_technician_id': null,
        'status': ServiceRequestStatus.pending.value,
        'route_order': null,
        'route_plan_date': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', newId);
    }
  }

  @override
  Future<void> deleteServiceRequest(String id) async {
    await _client.from('service_requests').delete().eq('id', id);
  }

  @override
  Future<void> deleteCompletedService(String id) async {
    await _client.rpc('delete_completed_service_v17', params: {'p_service_request_id': id});
  }
}
