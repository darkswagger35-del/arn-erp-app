import 'package:supabase_flutter/supabase_flutter.dart';

class FinanceRepository {
  FinanceRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>> summary({
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await _client.rpc(
      'erp_dashboard_summary',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> payments({
    DateTime? start,
    DateTime? end,
  }) async {
    dynamic query = _client
        .from('payments')
        .select('*, customers(full_name, company_name, phone, address)');
    if (start != null) {
      query = query.gte('payment_date', start.toUtc().toIso8601String());
    }
    if (end != null) {
      query = query.lt('payment_date', end.toUtc().toIso8601String());
    }
    final raw = await query.order('payment_date', ascending: false).limit(500);
    final rows = List<Map<String, dynamic>>.from(raw as List);
    return _enrichPayments(rows);
  }

  Future<List<Map<String, dynamic>>> _enrichPayments(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final directServiceIds = rows
        .map((row) => row['service_request_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final customerIds = rows
        .map((row) => row['customer_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    try {
      final serviceRows = <Map<String, dynamic>>[];
      if (directServiceIds.isNotEmpty) {
        serviceRows.addAll(List<Map<String, dynamic>>.from(
          await _client
              .from('service_requests')
              .select(
                'id, customer_id, service_type, description, completion_note, '
                'created_by, assigned_technician_id, price, planned_product_name, '
                'planned_quantity, planned_unit_price, status, updated_at',
              )
              .inFilter('id', directServiceIds.toList()),
        ));
      }

      // Eski payments kayıtlarında service_request_id bulunmayabiliyor.
      // Aynı müşterinin ödeme anına en yakın tamamlanmış servisini yalnızca
      // detay göstermek için aday olarak yüklüyoruz.
      if (customerIds.isNotEmpty) {
        final byCustomer = List<Map<String, dynamic>>.from(
          await _client
              .from('service_requests')
              .select(
                'id, customer_id, service_type, description, completion_note, '
                'created_by, assigned_technician_id, price, planned_product_name, '
                'planned_quantity, planned_unit_price, status, updated_at',
              )
              .inFilter('customer_id', customerIds)
              .eq('status', 'completed')
              .order('updated_at', ascending: false)
              .limit(1000),
        );
        final known = serviceRows.map((e) => e['id']?.toString()).toSet();
        serviceRows.addAll(byCustomer.where((e) => !known.contains(e['id']?.toString())));
      }

      if (serviceRows.isEmpty) return rows;

      final allServiceIds = serviceRows
          .map((e) => e['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final profileIds = <String>{};
      for (final service in serviceRows) {
        final creator = service['created_by']?.toString() ?? '';
        final technician = service['assigned_technician_id']?.toString() ?? '';
        if (creator.isNotEmpty) profileIds.add(creator);
        if (technician.isNotEmpty) profileIds.add(technician);
      }

      final profileMap = <String, Map<String, dynamic>>{};
      if (profileIds.isNotEmpty) {
        final profiles = List<Map<String, dynamic>>.from(
          await _client
              .from('profiles')
              .select('id, full_name, role')
              .inFilter('id', profileIds.toList()),
        );
        for (final profile in profiles) {
          profileMap[profile['id'].toString()] = profile;
        }
      }

      final itemMap = <String, List<Map<String, dynamic>>>{};
      if (allServiceIds.isNotEmpty) {
        final items = List<Map<String, dynamic>>.from(
          await _client
              .from('service_items')
              .select(
                'service_request_id, product_name, quantity, unit_price, line_total',
              )
              .inFilter('service_request_id', allServiceIds)
              .order('created_at', ascending: true),
        );
        for (final item in items) {
          final id = item['service_request_id']?.toString() ?? '';
          if (id.isEmpty) continue;
          itemMap.putIfAbsent(id, () => <Map<String, dynamic>>[]).add(item);
        }
      }

      final serviceMap = <String, Map<String, dynamic>>{};
      for (final service in serviceRows) {
        final id = service['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final creatorId = service['created_by']?.toString() ?? '';
        final technicianId = service['assigned_technician_id']?.toString() ?? '';
        final creator = profileMap[creatorId] ?? const <String, dynamic>{};
        final technician = profileMap[technicianId] ?? const <String, dynamic>{};
        final creatorRole = creator['role']?.toString() ?? '';
        serviceMap[id] = <String, dynamic>{
          ...service,
          'technician_name': technician['full_name']?.toString() ?? '',
          'opened_by_name': creator['full_name']?.toString() ?? '',
          'opened_by_role': creatorRole,
          'secretary_name': creatorRole == 'secretary'
              ? creator['full_name']?.toString() ?? ''
              : '',
          'items': itemMap[id] ?? const <Map<String, dynamic>>[],
        };
      }

      Map<String, dynamic>? inferService(Map<String, dynamic> payment) {
        final direct = payment['service_request_id']?.toString() ?? '';
        if (direct.isNotEmpty && serviceMap[direct] != null) return serviceMap[direct];
        final customerId = payment['customer_id']?.toString() ?? '';
        final paymentDate = DateTime.tryParse(payment['payment_date']?.toString() ?? '');
        if (customerId.isEmpty || paymentDate == null) return null;
        Map<String, dynamic>? best;
        var bestSeconds = 3601;
        for (final service in serviceMap.values) {
          if (service['customer_id']?.toString() != customerId) continue;
          final updated = DateTime.tryParse(service['updated_at']?.toString() ?? '');
          if (updated == null) continue;
          final seconds = updated.difference(paymentDate).inSeconds.abs();
          if (seconds <= 3600 && seconds < bestSeconds) {
            best = service;
            bestSeconds = seconds;
          }
        }
        return best;
      }

      return rows.map((row) {
        final service = inferService(row);
        return <String, dynamic>{
          ...row,
          if (service != null) '_service': service,
        };
      }).toList(growable: false);
    } catch (_) {
      return rows;
    }
  }

  Future<List<Map<String, dynamic>>> customerAccount(String customerId) async {
    final rows = await _client
        .from('customer_account_movements')
        .select()
        .eq('customer_id', customerId)
        .order('movement_date', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> staffPerformance({
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await _client.rpc(
      'erp_staff_performance_v40',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> reportDetails({
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _client.rpc(
      'erp_report_details_v41',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().add(const Duration(hours: 3)).toIso8601String(),
      },
    );
    final parsedRows = List<Map<String, dynamic>>.from(rows as List);

    final filtered = parsedRows.where((row) {
      final rawDate = row['transaction_date'];
      if (rawDate == null) return false;
      final parsed = DateTime.tryParse(rawDate.toString());
      if (parsed == null) return false;
      final localDate = parsed.toLocal();
      return !localDate.isBefore(start) && localDate.isBefore(end);
    }).toList(growable: false);

    return _correctSecretaryAttribution(filtered);
  }

  Future<List<Map<String, dynamic>>> _correctSecretaryAttribution(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final ids = rows
        .map((row) => row['record_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return rows;

    try {
      final requests = List<Map<String, dynamic>>.from(
        await _client
            .from('service_requests')
            .select('id, created_by')
            .inFilter('id', ids),
      );
      final creatorIds = requests
          .map((row) => row['created_by']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (creatorIds.isEmpty) return rows;

      final profiles = List<Map<String, dynamic>>.from(
        await _client
            .from('profiles')
            .select('id, full_name, role')
            .inFilter('id', creatorIds),
      );
      final profileMap = {
        for (final profile in profiles) profile['id'].toString(): profile,
      };
      final creatorByRequest = {
        for (final request in requests)
          request['id'].toString(): request['created_by']?.toString() ?? '',
      };

      return rows.map((row) {
        final recordId = row['record_id']?.toString() ?? '';
        final creatorId = creatorByRequest[recordId];
        if (creatorId == null || creatorId.isEmpty) return row;
        final profile = profileMap[creatorId];
        if (profile == null) return row;
        final role = profile['role']?.toString() ?? '';
        return <String, dynamic>{
          ...row,
          'secretary_name': role == 'secretary'
              ? profile['full_name']?.toString() ?? ''
              : '',
          'opened_by_name': profile['full_name']?.toString() ?? '',
          'opened_by_role': role,
        };
      }).toList(growable: false);
    } catch (_) {
      return rows;
    }
  }

  Future<List<Map<String, dynamic>>> topProducts({
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await _client.rpc(
      'erp_top_products',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
        'p_limit': 10,
      },
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
