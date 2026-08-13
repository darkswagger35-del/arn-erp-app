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
    dynamic query = _client.from('service_requests').select();

    final currentUser = _client.auth.currentUser;
    if (currentUser != null) {
      try {
        final profile = await _client
            .from('profiles')
            .select('role')
            .eq('id', currentUser.id)
            .maybeSingle();
        if (profile?['role']?.toString() == 'secretary') {
          // Savunma katmanı: RLS yanlış/eskimiş olsa bile sekreter yalnızca
          // kendi açtığı servis kayıtlarını istemci tarafında da sorgular.
          query = query.eq('created_by', currentUser.id);
        }
      } catch (_) {
        // Asıl güvenlik Supabase RLS politikasındadır.
      }
    }

    if (status != null) {
      query = query.eq('status', status.value);
    }

    if (technicianId != null && technicianId.trim().isNotEmpty) {
      query = query.eq('assigned_technician_id', technicianId.trim());
    }

    final response = await query.order('created_at', ascending: false);
    var requests = (response as List<dynamic>)
        .map(
          (item) => ServiceRequestModel.fromMap(item as Map<String, dynamic>),
        )
        .toList();

    requests = await _hideSupersededFailedRequests(requests);
    return _enrichRequests(requests);
  }

  /// Yeniden servis açılmış eski "Tamamlanamadı / İptal Edildi" kayıtlarını
  /// operasyon listelerinden kaldırırız. Veritabanındaki eski kayıt silinmez;
  /// müşteri kartında geçmiş/not olarak görünmeye devam eder.
  Future<List<ServiceRequestModel>> _hideSupersededFailedRequests(
    List<ServiceRequestModel> requests,
  ) async {
    final failed = requests
        .where((r) => r.status == ServiceRequestStatus.couldNotComplete || r.status == ServiceRequestStatus.cancelled)
        .toList(growable: false);
    if (failed.isEmpty) return requests;

    final customerIds = failed
        .map((r) => r.customerId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (customerIds.isEmpty) return requests;

    try {
      dynamic query = _client
          .from('service_requests')
          .select('id, customer_id, status, created_at')
          .inFilter('customer_id', customerIds)
          .inFilter('status', const ['pending', 'assigned', 'in_progress', 'completed']);

      final currentUser = _client.auth.currentUser;
      if (currentUser != null) {
        try {
          final profile = await _client
              .from('profiles')
              .select('role')
              .eq('id', currentUser.id)
              .maybeSingle();
          if (profile?['role']?.toString() == 'secretary') {
            query = query.eq('created_by', currentUser.id);
          }
        } catch (_) {}
      }

      final newerRows = List<Map<String, dynamic>>.from(await query);
      bool hasNewer(ServiceRequestModel old) {
        final oldCreated = old.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return newerRows.any((row) {
          if (row['customer_id']?.toString() != old.customerId) return false;
          final id = row['id']?.toString();
          if (id != null && id == old.id) return false;
          final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
          return created != null && created.isAfter(oldCreated);
        });
      }

      return requests
          .where((r) {
            final failedStatus = r.status == ServiceRequestStatus.couldNotComplete ||
                r.status == ServiceRequestStatus.cancelled;
            return !failedStatus || !hasNewer(r);
          })
          .toList(growable: false);
    } catch (_) {
      return requests;
    }
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
            assignedTechnicianName: request.status == ServiceRequestStatus.pending ||
                    request.assignedTechnicianId == null ||
                    request.assignedTechnicianId!.trim().isEmpty
                ? ''
                : technicianMap[request.assignedTechnicianId] ??
                    request.technicianNameSnapshot,
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
  Future<void> deleteServiceRequest(String id) async {
    await _client.from('service_requests').delete().eq('id', id);
  }

  @override
  Future<void> deleteCompletedService(String id) async {
    await _client.rpc('delete_completed_service_v17', params: {'p_service_request_id': id});
  }
}
