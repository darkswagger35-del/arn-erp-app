import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceProduct {
  const MaintenanceProduct({
    required this.id,
    required this.name,
    required this.maintenanceMonths,
  });

  final String id;
  final String name;
  final int maintenanceMonths;

  factory MaintenanceProduct.fromMap(Map<String, dynamic> map) {
    return MaintenanceProduct(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Ürün',
      maintenanceMonths: (map['maintenance_months'] as num?)?.toInt() ?? 0,
    );
  }
}

class MaintenanceUser {
  const MaintenanceUser({
    required this.id,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String fullName;
  final String role;

  factory MaintenanceUser.fromMap(Map<String, dynamic> map) {
    return MaintenanceUser(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name']?.toString() ?? 'Personel',
      role: map['role']?.toString() ?? 'secretary',
    );
  }
}

class MaintenanceReminder {
  const MaintenanceReminder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.productName,
    required this.performedAt,
    required this.nextMaintenanceDate,
    this.assignedUserName,
    this.secretaryName,
    this.technicianName,
    this.notes,
    this.isCustomerActive = true,
    this.maintenanceMonths = 0,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String address;
  final String productName;
  final DateTime performedAt;
  final DateTime nextMaintenanceDate;
  final String? assignedUserName;
  final String? secretaryName;
  final String? technicianName;
  final String? notes;
  final bool isCustomerActive;
  final int maintenanceMonths;

  int get daysRemaining => nextMaintenanceDate
      .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
      .inDays;

  factory MaintenanceReminder.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] is Map<String, dynamic>
        ? map['customers'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final product = map['products'] is Map<String, dynamic>
        ? map['products'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final profile = map['assigned_profile'] is Map<String, dynamic>
        ? map['assigned_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final secretary = map['secretary_profile'] is Map<String, dynamic>
        ? map['secretary_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final technician = map['technician_profile'] is Map<String, dynamic>
        ? map['technician_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return MaintenanceReminder(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      customerName: customer['full_name']?.toString() ?? 'Müşteri',
      phone: customer['phone']?.toString() ?? '',
      address: customer['address']?.toString() ?? '',
      productName: product['name']?.toString() ?? 'Ürün',
      performedAt: DateTime.tryParse(map['performed_at']?.toString() ?? '') ?? DateTime.now(),
      nextMaintenanceDate: DateTime.tryParse(map['next_maintenance_date']?.toString() ?? '') ?? DateTime.now(),
      assignedUserName: profile['full_name']?.toString(),
      secretaryName: secretary['full_name']?.toString(),
      technicianName: technician['full_name']?.toString(),
      notes: map['notes']?.toString(),
      isCustomerActive: customer['is_active'] != false,
      maintenanceMonths: (product['maintenance_months'] as num?)?.toInt() ?? 0,
    );
  }
}


class CustomerMaintenanceRecord {
  const CustomerMaintenanceRecord({
    required this.id,
    required this.productName,
    required this.performedAt,
    this.productId,
    this.nextMaintenanceDate,
    this.assignedUserName,
    this.secretaryId,
    this.secretaryName,
    this.technicianId,
    this.technicianName,
    this.notes,
    this.serviceId,
    this.quantity = 1,
    this.amount = 0,
    this.paymentStatus = 'paid',
  });

  final String id;
  final String productName;
  final String? productId;
  final DateTime performedAt;
  final DateTime? nextMaintenanceDate;
  final String? assignedUserName;
  final String? secretaryId;
  final String? secretaryName;
  final String? technicianId;
  final String? technicianName;
  final String? notes;
  final String? serviceId;
  final double quantity;
  final double amount;
  final String paymentStatus;

  factory CustomerMaintenanceRecord.fromMap(Map<String, dynamic> map) {
    final product = map['products'] is Map<String, dynamic>
        ? map['products'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final profile = map['assigned_profile'] is Map<String, dynamic>
        ? map['assigned_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final secretary = map['secretary_profile'] is Map<String, dynamic>
        ? map['secretary_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final technician = map['technician_profile'] is Map<String, dynamic>
        ? map['technician_profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final sale = map['_sale'] is Map<String, dynamic>
        ? map['_sale'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final item = map['_service_item'] is Map<String, dynamic>
        ? map['_service_item'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return CustomerMaintenanceRecord(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString(),
      productName: product['name']?.toString() ??
          map['product_name']?.toString() ??
          item['product_name']?.toString() ??
          'Servis işlemi',
      performedAt: DateTime.tryParse(map['performed_at']?.toString() ?? '') ?? DateTime.now(),
      nextMaintenanceDate: DateTime.tryParse(map['next_maintenance_date']?.toString() ?? ''),
      assignedUserName: profile['full_name']?.toString(),
      secretaryId: map['secretary_id']?.toString(),
      secretaryName: secretary['full_name']?.toString(),
      technicianId: map['technician_id']?.toString(),
      technicianName: technician['full_name']?.toString(),
      notes: map['notes']?.toString(),
      serviceId: map['service_id']?.toString(),
      quantity: (sale['quantity'] as num?)?.toDouble() ??
          (item['quantity'] as num?)?.toDouble() ?? 1,
      amount: (sale['amount'] as num?)?.toDouble() ??
          (item['line_total'] as num?)?.toDouble() ?? 0,
      paymentStatus: sale['payment_status']?.toString() ?? 'paid',
    );
  }
}

class MaintenanceRepository {
  MaintenanceRepository(this._client);

  final SupabaseClient _client;

  Future<String> _companyId() async {
    final value = await _client.rpc('current_company_id');
    final id = value?.toString() ?? '';
    if (id.isEmpty) throw StateError('Firma bilgisi bulunamadı.');
    return id;
  }

  Future<List<MaintenanceProduct>> getProducts() async {
    final rows = await _client
        .from('products')
        .select('id, name, maintenance_months')
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(MaintenanceProduct.fromMap)
        .toList(growable: false);
  }

  Future<List<MaintenanceUser>> getAssignableUsers() async {
    final rows = await _client.rpc('list_maintenance_staff');
    return List<Map<String, dynamic>>.from(rows as List)
        .map(MaintenanceUser.fromMap)
        .toList(growable: false);
  }


  Future<List<MaintenanceUser>> getHistoricalStaff() async {
    final rows = await _client.rpc('list_historical_staff_v17');
    return List<Map<String, dynamic>>.from(rows as List)
        .map(MaintenanceUser.fromMap)
        .toList(growable: false);
  }

  Future<Map<String, String?>> getCustomerStaffSummary(String customerId) async {
    final rows = await _client.rpc('customer_staff_summary_v17', params: {
      'p_customer_id': customerId,
    });
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isEmpty) return const {'secretary_name': null, 'technician_name': null};
    return {
      'secretary_name': list.first['secretary_name']?.toString(),
      'technician_name': list.first['technician_name']?.toString(),
    };
  }
  Future<String> createHistoricalCustomerV17({
    required String fullName,
    required String phone,
    required String city,
    required String district,
    required String address,
    required DateTime recordDate,
    required String productId,
    required double quantity,
    required double amount,
    required String paymentStatus,
    DateTime? paymentDueDate,
    required int maintenanceMonths,
    String? secretaryId,
    String? technicianId,
  }) async {
    final result = await _client.rpc('create_historical_customer_v17', params: {
      'p_full_name': fullName.trim(),
      'p_phone': phone.trim(),
      'p_city': city.trim(),
      'p_district': district.trim(),
      'p_address': address.trim(),
      'p_record_date': recordDate.toIso8601String().split('T').first,
      'p_product_id': productId,
      'p_quantity': quantity,
      'p_amount': amount,
      'p_payment_status': paymentStatus,
      'p_payment_due_date': paymentDueDate?.toIso8601String().split('T').first,
      'p_maintenance_months': maintenanceMonths,
      'p_secretary_id': secretaryId,
      'p_technician_id': technicianId,
    });
    return result.toString();
  }

  Future<String> createHistoricalCustomer({
    required String fullName,
    required String phone,
    required String address,
    required DateTime registrationDate,
    required String productId,
    required DateTime performedAt,
    required int maintenanceMonths,
    required String assignedRole,
    String? assignedUserId,
    String? notes,
  }) async {
    final companyId = await _companyId();
    final userId = _client.auth.currentUser?.id;
    final customer = await _client
        .from('customers')
        .insert({
          'company_id': companyId,
          'customer_type': 'individual',
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'address': address.trim(),
          'is_active': true,
          'registration_date': registrationDate.toIso8601String(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'created_by': userId,
          'updated_by': userId,
        })
        .select('id')
        .single();
    final customerId = customer['id'].toString();
    final nextDate = maintenanceMonths > 0
        ? DateTime(performedAt.year, performedAt.month + maintenanceMonths, performedAt.day)
        : null;
    await _client.from('customer_maintenance_records').insert({
      'company_id': companyId,
      'customer_id': customerId,
      'product_id': productId,
      'performed_at': performedAt.toIso8601String().split('T').first,
      'next_maintenance_date': nextDate?.toIso8601String().split('T').first,
      'assigned_user_id': assignedUserId,
      'assigned_role': assignedRole,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'created_by': userId,
    });
    return customerId;
  }

  Future<List<CustomerMaintenanceRecord>> getCustomerRecords(String customerId) async {
    final maintenanceRows = List<Map<String, dynamic>>.from(
      await _client
          .from('customer_maintenance_records')
          .select(
            'id, service_id, product_id, performed_at, next_maintenance_date, notes, product_name, '
            'secretary_id, technician_id, import_batch_id, import_source_row, products(name), '
            'assigned_profile:profiles!customer_maintenance_records_assigned_user_id_fkey(full_name), '
            'secretary_profile:profiles!customer_maintenance_records_secretary_id_fkey(full_name), '
            'technician_profile:profiles!customer_maintenance_records_technician_id_fkey(full_name)',
          )
          .eq('customer_id', customerId)
          .order('performed_at', ascending: false),
    );

    final saleRows = List<Map<String, dynamic>>.from(
      await _client
          .from('historical_customer_sales')
          .select(
            'product_id, product_name, quantity, amount, payment_status, transaction_date, '
            'import_batch_id, import_source_row',
          )
          .eq('customer_id', customerId),
    );
    final salesByImport = <String, Map<String, dynamic>>{
      for (final sale in saleRows)
        if (sale['import_batch_id'] != null && sale['import_source_row'] != null)
          '${sale['import_batch_id']}|${sale['import_source_row']}': sale,
    };

    final serviceRows = List<Map<String, dynamic>>.from(
      await _client
          .from('services')
          .select(
            'id, completed_at, work_description, technician_id, '
            'technician_profile:profiles!services_technician_id_fkey(full_name), '
            'service_items(id, product_id, product_name, quantity, unit_price, line_total)',
          )
          .eq('customer_id', customerId)
          .order('completed_at', ascending: false),
    );
    final serviceItems = <String, List<Map<String, dynamic>>>{};
    for (final service in serviceRows) {
      serviceItems[service['id']?.toString() ?? ''] =
          List<Map<String, dynamic>>.from(service['service_items'] as List? ?? const []);
    }

    final records = <CustomerMaintenanceRecord>[];
    final recordedServiceProducts = <String>{};
    for (final row in maintenanceRows) {
      final importKey = row['import_batch_id'] != null && row['import_source_row'] != null
          ? '${row['import_batch_id']}|${row['import_source_row']}'
          : null;
      if (importKey != null) row['_sale'] = salesByImport[importKey];

      final serviceId = row['service_id']?.toString();
      final productId = row['product_id']?.toString();
      if (serviceId != null && serviceId.isNotEmpty) {
        final items = serviceItems[serviceId] ?? const <Map<String, dynamic>>[];
        final matching = items.where((item) => item['product_id']?.toString() == productId).toList();
        if (matching.isNotEmpty) row['_service_item'] = matching.first;
        recordedServiceProducts.add('$serviceId|$productId');
      }
      records.add(CustomerMaintenanceRecord.fromMap(row));
    }

    // Bakım kaydı oluşmayan servis ürünlerini de ayrı, düzenlenebilir satır yap.
    for (final service in serviceRows) {
      final serviceId = service['id']?.toString() ?? '';
      final profile = service['technician_profile'] is Map<String, dynamic>
          ? service['technician_profile'] as Map<String, dynamic>
          : const <String, dynamic>{};
      for (final item in serviceItems[serviceId] ?? const <Map<String, dynamic>>[]) {
        final productId = item['product_id']?.toString();
        if (recordedServiceProducts.contains('$serviceId|$productId')) continue;
        records.add(CustomerMaintenanceRecord(
          id: 'service-item:${item['id']}',
          productId: productId,
          productName: item['product_name']?.toString() ?? 'Servis işlemi',
          performedAt: DateTime.tryParse(service['completed_at']?.toString() ?? '') ?? DateTime.now(),
          technicianId: service['technician_id']?.toString(),
          technicianName: profile['full_name']?.toString(),
          assignedUserName: profile['full_name']?.toString(),
          notes: service['work_description']?.toString(),
          serviceId: serviceId,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
          amount: (item['line_total'] as num?)?.toDouble() ?? 0,
          paymentStatus: 'paid',
        ));
      }
    }

    records.sort((a, b) => b.performedAt.compareTo(a.performedAt));
    return records;
  }

  Future<void> updateCustomerRecord({
    required CustomerMaintenanceRecord record,
    required String productId,
    required DateTime performedAt,
    DateTime? nextMaintenanceDate,
    String? secretaryId,
    String? technicianId,
    required String notes,
    required double quantity,
    required double amount,
    required String paymentStatus,
  }) async {
    if (record.id.startsWith('service-item:')) {
      throw StateError('Bakım kaydı olmayan servis ürünleri şu anda servis detayından düzenlenmelidir.');
    }
    await _client.rpc('update_customer_maintenance_record_v28', params: {
      'p_record_id': record.id,
      'p_product_id': productId,
      'p_performed_at': performedAt.toIso8601String().split('T').first,
      'p_next_maintenance_date': nextMaintenanceDate?.toIso8601String().split('T').first,
      'p_secretary_id': secretaryId,
      'p_technician_id': technicianId,
      'p_notes': notes.trim(),
      'p_quantity': quantity,
      'p_amount': amount,
      'p_payment_status': paymentStatus,
    });
  }

  Future<void> deleteCustomerRecord(CustomerMaintenanceRecord record) async {
    if (record.id.startsWith('service-item:')) {
      throw StateError('Bu servis ürününü silmek için tüm servis işlemini silin.');
    }
    await _client.rpc('delete_customer_maintenance_record_v28', params: {
      'p_record_id': record.id,
    });
  }

  Future<void> deleteCustomerHistoryTransaction(CustomerMaintenanceRecord record) async {
    if (record.id.startsWith('service-item:')) {
      throw StateError('Bu işlem bakım kaydıyla bağlı değil. Servis Talepleri ekranından tamamlanan kaydı silin.');
    }
    await _client.rpc('delete_customer_history_transaction_v28', params: {
      'p_record_id': record.id,
    });
  }

  Future<List<MaintenanceReminder>> getAssignedToCurrentUser() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _client
        .from('customer_maintenance_records')
        .select(
          'id, customer_id, performed_at, next_maintenance_date, notes, '
          'customers(full_name, phone, address, is_active), products(name, maintenance_months), '
          'assigned_profile:profiles!customer_maintenance_records_assigned_user_id_fkey(full_name), '
          'secretary_profile:profiles!customer_maintenance_records_secretary_id_fkey(full_name), '
          'technician_profile:profiles!customer_maintenance_records_technician_id_fkey(full_name)',
        )
        .eq('assigned_user_id', userId)
        .order('next_maintenance_date');
    return List<Map<String, dynamic>>.from(rows)
        .map(MaintenanceReminder.fromMap)
        .toList(growable: false);
  }

  Future<List<MaintenanceReminder>> getUpcoming({int days = 45}) async {
    final today = DateTime.now();
    final end = today.add(Duration(days: days));
    final userId = _client.auth.currentUser?.id;
    String? role;
    if (userId != null) {
      try {
        final profile = await _client
            .from('profiles')
            .select('role')
            .eq('id', userId)
            .maybeSingle();
        role = profile?['role']?.toString();
      } catch (_) {}
    }

    dynamic query = _client
        .from('customer_maintenance_records')
        .select(
          'id, customer_id, performed_at, next_maintenance_date, notes, '
          'customers(full_name, phone, address, is_active), products(name, maintenance_months), '
          'assigned_profile:profiles!customer_maintenance_records_assigned_user_id_fkey(full_name), '
          'secretary_profile:profiles!customer_maintenance_records_secretary_id_fkey(full_name), '
          'technician_profile:profiles!customer_maintenance_records_technician_id_fkey(full_name)',
        )
        .not('next_maintenance_date', 'is', null)
        .lte('next_maintenance_date', end.toIso8601String().split('T').first);
    if (role == 'secretary' && userId != null) {
      query = query.eq('secretary_id', userId);
    }
    final rows = await query.order('next_maintenance_date');
    var reminders = List<Map<String, dynamic>>.from(rows)
        .map(MaintenanceReminder.fromMap)
        .toList(growable: false);

    // Bu bakım için yeni servis talebi açıldıysa aynı müşteriyi tekrar bakım
    // listesinde tutmayız. Servis kapandığında yeni bakım tarihi servis sonucu
    // üzerinden tekrar üretilebilir.
    final customerIds = reminders
        .map((item) => item.customerId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (customerIds.isNotEmpty) {
      try {
        dynamic openQuery = _client
            .from('service_requests')
            .select('customer_id')
            .inFilter('customer_id', customerIds)
            .inFilter('status', const ['pending', 'assigned', 'in_progress']);
        // Bakım müşterisi için açık bir servis varsa, servisi kim açmış olursa olsun
        // yaklaşan bakım listesinden çıkar. Hatırlatma zaten sekreter bazlı süzüldüğü
        // için burada created_by filtresi kullanmak yanlış tekrar kayıtlara yol açıyordu.
        final openRows = List<Map<String, dynamic>>.from(await openQuery);
        final openCustomers = openRows
            .map((row) => row['customer_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        reminders = reminders
            .where((item) => !openCustomers.contains(item.customerId))
            .toList(growable: false);
      } catch (_) {}
    }

    return reminders;
  }

  Future<void> setMaintenanceFollowUpNote({
    required String recordId,
    required String? currentNotes,
    String? followUpLabel,
  }) async {
    final lines = (currentNotes ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('Bakım Takibi:'))
        .toList(growable: true);
    if (followUpLabel != null && followUpLabel.trim().isNotEmpty) {
      lines.add('Bakım Takibi: ${followUpLabel.trim()}');
    }
    await _client
        .from('customer_maintenance_records')
        .update({'notes': lines.isEmpty ? null : lines.join('\n')})
        .eq('id', recordId);
  }
}
