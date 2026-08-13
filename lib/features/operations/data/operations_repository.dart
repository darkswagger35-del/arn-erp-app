import 'package:supabase_flutter/supabase_flutter.dart';

class OperationsRepository {
  OperationsRepository(this.client);

  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> list(
    String table, {
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    final rows = await client
        .from(table)
        .select()
        .order(orderBy, ascending: ascending);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> insert(String table, Map<String, dynamic> values) async {
    await client.from(table).insert(values);
  }

  Future<void> update(
    String table,
    String id,
    Map<String, dynamic> values,
  ) async {
    await client.from(table).update(values).eq('id', id);
  }

  Future<void> delete(String table, String id) async {
    await client.from(table).delete().eq('id', id);
  }



  Future<int> _countActiveCustomers({
    required bool isSecretary,
    String? viewerId,
  }) async {
    const pageSize = 1000;
    var offset = 0;
    var total = 0;

    while (true) {
      dynamic query = client
          .from('customers')
          .select('id')
          .eq('is_active', true)
          .filter('deleted_at', 'is', null);
      if (isSecretary && viewerId != null) {
        query = query.eq('created_by', viewerId);
      }

      final rows = List<Map<String, dynamic>>.from(
        await query.range(offset, offset + pageSize - 1),
      );
      total += rows.length;
      if (rows.length < pageSize) break;
      offset += pageSize;
    }

    return total;
  }

  Future<int> _countUpcomingMaintenance({
    required DateTime maintenanceEnd,
    required bool isSecretary,
    String? viewerId,
  }) async {
    const pageSize = 1000;
    var offset = 0;
    var total = 0;

    while (true) {
      dynamic query = client
          .from('customer_maintenance_records')
          .select('id')
          .not('next_maintenance_date', 'is', null)
          .lte(
            'next_maintenance_date',
            maintenanceEnd.toIso8601String().substring(0, 10),
          );
      if (isSecretary && viewerId != null) {
        query = query.eq('secretary_id', viewerId);
      }

      final rows = List<Map<String, dynamic>>.from(
        await query.range(offset, offset + pageSize - 1),
      );
      total += rows.length;
      if (rows.length < pageSize) break;
      offset += pageSize;
    }

    return total;
  }

  Future<Map<String, String?>> _viewerContext() async {
    final user = client.auth.currentUser;
    if (user == null) return const {'id': null, 'role': null};
    try {
      final row = await client
          .from('profiles')
          .select('id, role, full_name')
          .eq('id', user.id)
          .maybeSingle();
      return {
        'id': row?['id']?.toString() ?? user.id,
        'role': row?['role']?.toString(),
        'name': row?['full_name']?.toString(),
      };
    } catch (_) {
      return {'id': user.id, 'role': null, 'name': null};
    }
  }

  Future<Map<String, dynamic>> dashboardSummary({DateTime? selectedDate}) async {
    final viewer = await _viewerContext();
    final viewerId = viewer['id'];
    final isSecretary = viewer['role'] == 'secretary' && viewerId != null;
    final now = selectedDate ?? DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    Map<String, dynamic> data = const <String, dynamic>{};
    try {
      final result = await client.rpc(
        'erp_dashboard_summary',
        params: {
          'p_start': start.toUtc().toIso8601String(),
          'p_end': end.toUtc().toIso8601String(),
        },
      );
      data = Map<String, dynamic>.from(result as Map);
    } catch (_) {
      // Kartların tamamı tek bir RPC hatası yüzünden sıfırlanmasın.
    }

    // Servis listesiyle aynı tablodan doğrudan sayım yapıyoruz. Böylece eski
    // RPC sürümü ya da eski status değerleri ana paneli yanlış göstermiyor.
    var pending = _asInt(data['pending']);
    var assigned = _asInt(data['active']);
    try {
      dynamic pendingQuery = client
          .from('service_requests')
          .select('id')
          .inFilter('status', const ['pending', 'awaiting_approval']);
      dynamic assignedQuery = client
          .from('service_requests')
          .select('id')
          .inFilter('status', const ['assigned', 'in_progress']);
      if (isSecretary) {
        pendingQuery = pendingQuery.eq('created_by', viewerId!);
        assignedQuery = assignedQuery.eq('created_by', viewerId);
      }
      final pendingRows = List<Map<String, dynamic>>.from(await pendingQuery);
      final assignedRows = List<Map<String, dynamic>>.from(await assignedQuery);
      pending = pendingRows.length;
      assigned = assignedRows.length;
    } catch (_) {
      // RPC sonucu kullanılmaya devam eder.
    }

    var lowStock = 0;
    try {
      final stockRows = List<Map<String, dynamic>>.from(
        await client.from('warehouse_stocks').select(
          'product_id, quantity, products!inner(is_active, critical_stock)',
        ),
      );
      final criticalProducts = <String>{};
      for (final row in stockRows) {
        final product = row['products'];
        if (product is! Map) continue;
        if (product['is_active'] == false) continue;
        final critical = (product['critical_stock'] as num?)?.toDouble() ?? 0;
        if (critical <= 0) continue;
        final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
        if (quantity <= critical) {
          final productId = row['product_id']?.toString();
          if (productId != null && productId.isNotEmpty) criticalProducts.add(productId);
        }
      }
      lowStock = criticalProducts.length;
    } catch (_) {
      lowStock = 0;
    }

    var scopedActiveCustomers = _asInt(data['active_customers']);
    if (isSecretary) {
      try {
        scopedActiveCustomers = await _countActiveCustomers(
          isSecretary: true,
          viewerId: viewerId,
        );
      } catch (_) {
        scopedActiveCustomers = 0;
      }
    }

    return {
      'pending': pending,
      'assigned': assigned,
      'completed_today': _asInt(data['completed_period']),
      'low_stock': lowStock,
      'daily_collection': isSecretary ? 0 : (data['collection_period'] ?? 0),
      'daily_revenue': isSecretary ? 0 : (data['revenue_period'] ?? 0),
      'open_balance': isSecretary ? 0 : (data['open_balance'] ?? 0),
      'active_customers': scopedActiveCustomers,
    };
  }

  Future<Map<String, dynamic>> dashboardWorkspace({
    String search = '',
    String? status,
    String? serviceType,
    DateTime? start,
    DateTime? end,
    DateTime? selectedDate,
  }) async {
    final viewer = await _viewerContext();
    final viewerId = viewer['id'];
    final isSecretary = viewer['role'] == 'secretary' && viewerId != null;
    final summary = await dashboardSummary(selectedDate: selectedDate);
    final now = DateTime.now();
    final focus = selectedDate ?? now;
    final todayStart = DateTime(focus.year, focus.month, focus.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final recentServices = <Map<String, dynamic>>[];
    final todayJobs = <Map<String, dynamic>>[];
    final recentPayments = <Map<String, dynamic>>[];
    final monthlyRevenue = <Map<String, dynamic>>[];
    final couldNotCompleteToday = <Map<String, dynamic>>[];

    try {
      dynamic query = client
          .from('service_requests')
          .select(
            'id, customer_id, assigned_technician_id, service_type, status, '
            'price, planned_date, created_at, created_by',
          );
      if (isSecretary) query = query.eq('created_by', viewerId!);
      final rawRows = List<Map<String, dynamic>>.from(
        await query.order('created_at', ascending: false).limit(120),
      );
      final rows = rawRows
          .where((row) {
            final status = row['status']?.toString() ?? '';
            return status != 'cancelled' &&
                status != 'could_not_complete' &&
                status != 'deferred';
          })
          .take(80)
          .toList(growable: false);
      final customerIds = rows
          .map((row) => row['customer_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final technicianIds = rows
          .map((row) => row['assigned_technician_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final customerNames = <String, String>{};
      if (customerIds.isNotEmpty) {
        final customerRows = List<Map<String, dynamic>>.from(
          await client
              .from('customers')
              .select('id, full_name, company_name')
              .inFilter('id', customerIds),
        );
        for (final row in customerRows) {
          final fullName = row['full_name']?.toString().trim() ?? '';
          final companyName = row['company_name']?.toString().trim() ?? '';
          customerNames[row['id'].toString()] =
              fullName.isNotEmpty ? fullName : companyName;
        }
      }

      final technicianNames = <String, String>{};
      if (technicianIds.isNotEmpty) {
        final profileRows = List<Map<String, dynamic>>.from(
          await client
              .from('profiles')
              .select('id, full_name')
              .inFilter('id', technicianIds),
        );
        for (final row in profileRows) {
          technicianNames[row['id'].toString()] =
              row['full_name']?.toString() ?? '';
        }
      }

      for (final row in rows) {
        final customerId = row['customer_id']?.toString() ?? '';
        final technicianId =
            row['assigned_technician_id']?.toString() ?? '';
        final enriched = <String, dynamic>{
          ...row,
          'customer_name': customerNames[customerId] ?? 'Müşteri',
          'technician_name': technicianNames[technicianId] ?? 'Atanmadı',
        };
        recentServices.add(enriched);
      }
    } catch (_) {
      // Dashboard ana kartları, detay listesindeki bir şema farkından etkilenmesin.
    }

    try {
      dynamic todayQuery = client
          .from('service_requests')
          .select(
            'id, customer_id, assigned_technician_id, service_type, status, price, planned_date, created_at, created_by, completion_note',
          )
          .gte('planned_date', todayStart.toUtc().toIso8601String())
          .lt('planned_date', todayEnd.toUtc().toIso8601String())
          .inFilter('status', const ['approved', 'assigned', 'in_progress']);
      if (isSecretary) todayQuery = todayQuery.eq('created_by', viewerId!);
      final rows = List<Map<String, dynamic>>.from(
        await todayQuery.order('planned_date', ascending: true).limit(20),
      );
      final customerIds = rows
          .map((row) => row['customer_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final customerNames = <String, String>{};
      if (customerIds.isNotEmpty) {
        final customerRows = List<Map<String, dynamic>>.from(
          await client
              .from('customers')
              .select('id, full_name, company_name')
              .inFilter('id', customerIds),
        );
        for (final row in customerRows) {
          final fullName = row['full_name']?.toString().trim() ?? '';
          final companyName = row['company_name']?.toString().trim() ?? '';
          customerNames[row['id'].toString()] =
              fullName.isNotEmpty ? fullName : companyName;
        }
      }
      final technicianIds = rows
          .map((row) => row['assigned_technician_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final technicianNames = <String, String>{};
      if (technicianIds.isNotEmpty) {
        final profileRows = List<Map<String, dynamic>>.from(
          await client.from('profiles').select('id, full_name').inFilter('id', technicianIds),
        );
        for (final row in profileRows) {
          technicianNames[row['id'].toString()] = row['full_name']?.toString() ?? '';
        }
      }
      for (final row in rows) {
        todayJobs.add({
          ...row,
          'customer_name': customerNames[row['customer_id']?.toString() ?? ''] ?? 'Müşteri',
          'technician_name': technicianNames[row['assigned_technician_id']?.toString() ?? ''] ?? 'Atanmadı',
          'created_by_name': viewer['name'] ?? 'Sekreter',
        });
      }
    } catch (_) {
      // Planlanan işler bulunamazsa panel boş görünür.
    }

    try {
      final rows = List<Map<String, dynamic>>.from(
        await client
            .from('payments')
            .select(
              'id, customer_id, amount, payment_method, payment_date, description',
            )
            .order('payment_date', ascending: false)
            .limit(12),
      );
      final customerIds = rows
          .map((row) => row['customer_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final customerNames = <String, String>{};
      if (customerIds.isNotEmpty) {
        final customerRows = List<Map<String, dynamic>>.from(
          await client
              .from('customers')
              .select('id, full_name, company_name')
              .inFilter('id', customerIds),
        );
        for (final row in customerRows) {
          final fullName = row['full_name']?.toString().trim() ?? '';
          final companyName = row['company_name']?.toString().trim() ?? '';
          customerNames[row['id'].toString()] =
              fullName.isNotEmpty ? fullName : companyName;
        }
      }
      for (final row in rows) {
        final method = row['payment_method']?.toString() ?? '';
        recentPayments.add({
          ...row,
          'customer_name':
              customerNames[row['customer_id']?.toString() ?? ''] ?? 'Müşteri',
          'payment_method_label': switch (method) {
            'cash' => 'Nakit',
            'card' => 'Kredi Kartı',
            'transfer' => 'Havale / EFT',
            'open_account' => 'Açık Hesap',
            _ => method.isEmpty ? 'Tahsilat' : method,
          },
        });
      }
    } catch (_) {
      // Tahsilat paneli boş kalabilir.
    }


    try {
      dynamic couldNotQuery = client
          .from('service_requests')
          .select(
            'id, customer_id, service_type, status, completion_note, planned_date, updated_at, created_by',
          )
          .eq('status', 'could_not_complete')
          .gte('updated_at', todayStart.toUtc().toIso8601String())
          .lt('updated_at', todayEnd.toUtc().toIso8601String());
      if (isSecretary) couldNotQuery = couldNotQuery.eq('created_by', viewerId!);
      final rows = List<Map<String, dynamic>>.from(
        await couldNotQuery.order('updated_at', ascending: false),
      );
      final customerIds = rows
          .map((row) => row['customer_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final customerNames = <String, String>{};
      if (customerIds.isNotEmpty) {
        final customerRows = List<Map<String, dynamic>>.from(
          await client
              .from('customers')
              .select('id, full_name, company_name')
              .inFilter('id', customerIds),
        );
        for (final row in customerRows) {
          final fullName = row['full_name']?.toString().trim() ?? '';
          final companyName = row['company_name']?.toString().trim() ?? '';
          customerNames[row['id'].toString()] =
              fullName.isNotEmpty ? fullName : companyName;
        }
      }
      for (final row in rows) {
        couldNotCompleteToday.add({
          ...row,
          'customer_name': customerNames[row['customer_id']?.toString() ?? ''] ?? 'Müşteri',
        });
      }
    } catch (_) {
      // Tamamlanamayan işler paneli şema farkında ana dashboard'u bozmaz.
    }

    // Ciroyu tahsilatlardan değil, Raporlar ekranıyla aynı servis/ürün
    // detaylarından üretiriz. Böylece ana panel ile raporlar aynı rakamı gösterir.
    var todayRevenue = 0.0;
    var todayCollection = 0.0;
    var completedToday = 0;
    try {
      if (isSecretary) throw StateError('Sekreter finans özeti şirket geneli gösterilmez.');
      final firstMonth = DateTime(now.year, now.month - 5, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final detailRows = List<Map<String, dynamic>>.from(
        await client.rpc(
          'erp_report_details_v41',
          params: {
            'p_start': firstMonth.toUtc().toIso8601String(),
            'p_end': nextMonth
                .toUtc()
                .add(const Duration(hours: 3))
                .toIso8601String(),
          },
        ) as List,
      );

      final monthlyAmounts = <String, double>{};
      final todayRecords = <String>{};
      for (final row in detailRows) {
        final parsed = DateTime.tryParse(
          row['transaction_date']?.toString() ?? '',
        );
        if (parsed == null) continue;
        final date = parsed.toLocal();
        if (date.isBefore(firstMonth) || !date.isBefore(nextMonth)) continue;

        final amount = (row['amount'] as num?)?.toDouble() ??
            double.tryParse(row['amount']?.toString() ?? '') ??
            0.0;
        final key = '${date.year}-${date.month}';
        monthlyAmounts[key] = (monthlyAmounts[key] ?? 0) + amount;

        if (!date.isBefore(todayStart) && date.isBefore(todayEnd)) {
          todayRevenue += amount;
          final source = row['source_type']?.toString() ?? '';
          final record = row['record_id']?.toString() ?? '';
          todayRecords.add('$source:$record');
          final paymentStatus =
              (row['payment_status']?.toString() ?? '').toLowerCase();
          if (paymentStatus == 'paid' ||
              paymentStatus == 'odendi' ||
              paymentStatus.contains('ödendi')) {
            todayCollection += amount;
          }
        }
      }
      completedToday = todayRecords.length;

      for (var offset = 5; offset >= 0; offset--) {
        final month = DateTime(now.year, now.month - offset, 1);
        monthlyRevenue.add({
          'label': _monthLabel(month.month),
          'amount': monthlyAmounts['${month.year}-${month.month}'] ?? 0.0,
        });
      }
    } catch (_) {
      for (var offset = 5; offset >= 0; offset--) {
        final month = DateTime(now.year, now.month - offset, 1);
        monthlyRevenue.add({'label': _monthLabel(month.month), 'amount': 0.0});
      }
      todayRevenue = (summary['daily_revenue'] as num?)?.toDouble() ?? 0.0;
      todayCollection =
          (summary['daily_collection'] as num?)?.toDouble() ?? 0.0;
      completedToday = _asInt(summary['completed_today']);
    }

    var activeCustomers = _asInt(summary['active_customers']);
    if (isSecretary || activeCustomers == 0) {
      try {
        activeCustomers = await _countActiveCustomers(
          isSecretary: isSecretary,
          viewerId: viewerId,
        );
      } catch (_) {
        activeCustomers = 0;
      }
    }

    var upcomingMaintenance = 0;
    try {
      final maintenanceEnd = todayStart.add(const Duration(days: 10));
      upcomingMaintenance = await _countUpcomingMaintenance(
        maintenanceEnd: maintenanceEnd,
        isSecretary: isSecretary,
        viewerId: viewerId,
      );
    } catch (_) {
      upcomingMaintenance = 0;
    }

    final selectedPlanned = todayJobs.length;
    final selectedCompleted = todayJobs.where((row) => row['status']?.toString() == 'completed').length;
    final selectedCancelled = todayJobs.where((row) {
      final status = row['status']?.toString() ?? '';
      return status == 'cancelled' || status == 'canceled' || status == 'could_not_complete';
    }).length;
    final selectedInProgress = todayJobs.where((row) => row['status']?.toString() == 'in_progress').length;
    final selectedAssigned = todayJobs.where((row) {
      final status = row['status']?.toString() ?? '';
      return status == 'assigned' || status == 'in_progress';
    }).length;

    return {
      ...summary,
      'daily_revenue': todayRevenue,
      'daily_collection': todayCollection,
      'completed_today': completedToday,
      'active_customers': activeCustomers,
      'today_jobs_count': selectedPlanned,
      'selected_completed': selectedCompleted,
      'selected_cancelled': selectedCancelled,
      'selected_in_progress': selectedInProgress,
      'selected_assigned': selectedAssigned,
      'selected_date': todayStart.toIso8601String(),
      'secretary_name': viewer['name'],
      'upcoming_maintenance': upcomingMaintenance,
      'recent_services': recentServices.take(12).toList(growable: false),
      'today_jobs': todayJobs,
      'recent_payments': recentPayments,
      'monthly_revenue': monthlyRevenue,
      'could_not_complete_today': couldNotCompleteToday,
      'could_not_complete_today_count': couldNotCompleteToday.length,
    };
  }

  String _monthLabel(int month) {
    const labels = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return labels[month - 1];
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
