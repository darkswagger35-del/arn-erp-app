import 'package:supabase_flutter/supabase_flutter.dart';

class TechnicianJob {
  const TechnicianJob({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.address,
    required this.serviceType,
    required this.description,
    required this.status,
    required this.price,
    this.plannedDate,
    this.plannedProductId,
    this.plannedProductName = '',
    this.plannedQuantity = 0,
    this.plannedUnitPrice = 0,
    this.secretaryName = '',
    this.completionNote = '',
    this.latitude,
    this.longitude,
    this.mapsUrl,
    this.city = '',
    this.district = '',
    this.neighborhood = '',
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason = '',
    this.technicianUnavailableReason = '',
    this.technicianUnavailableNote = '',
    this.routeOrder,
    this.routePlanDate,
    this.formValues = const <String, dynamic>{},
  });

  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String address;
  final String serviceType;
  final String description;
  final String status;
  final double price;
  final DateTime? plannedDate;
  final String? plannedProductId;
  final String plannedProductName;
  final double plannedQuantity;
  final double plannedUnitPrice;
  final String secretaryName;
  final String completionNote;
  final double? latitude;
  final double? longitude;
  final String? mapsUrl;
  final String city;
  final String district;
  final String neighborhood;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String cancellationReason;
  final String technicianUnavailableReason;
  final String technicianUnavailableNote;
  final int? routeOrder;
  final DateTime? routePlanDate;
  final Map<String, dynamic> formValues;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get hasUsableTurkeyCoordinates {
    if (!hasCoordinates) return false;
    final lat = latitude!;
    final lon = longitude!;
    if (lat < 35.0 || lat > 43.0 || lon < 25.0 || lon > 45.0) return false;

    // Eski/yanlış geocode sonuçları başka ülke veya başka şehirde kalmışsa
    // koordinatı kullanmak yerine açık adres + ilçe + şehir ile Yandex'e sor.
    final normalizedCity = city.trim().toLowerCase();
    bool inside(double minLat, double maxLat, double minLon, double maxLon) =>
        lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
    if (normalizedCity.contains('izmir')) return inside(37.7, 39.6, 25.8, 28.7);
    if (normalizedCity.contains('aydın') || normalizedCity.contains('aydin')) {
      return inside(37.2, 38.4, 26.0, 29.0);
    }
    if (normalizedCity.contains('manisa')) return inside(37.8, 39.7, 26.0, 29.5);
    if (normalizedCity.contains('antalya')) return inside(35.7, 37.6, 29.0, 32.8);
    if (normalizedCity.contains('ankara')) return inside(38.5, 41.0, 30.5, 34.5);
    return true;
  }

  /// Yandex rota girişinde yönetici Bölgeler ekranıyla aynı adres formatını
  /// kullanır. Rota URL'sine eski/yanlış koordinat veya mahalle eklemiyoruz;
  /// bunlar Yandex'in aynı sokağı başka şehirde çözmesine yol açabiliyor.
  String get mapQuery {
    final parts = <String>[
      address.trim(),
      district.trim(),
      city.trim(),
      'Türkiye',
    ].where((value) => value.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  String get locationText {
    final parts = <String>[address.trim(), district.trim(), city.trim()]
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return parts.join(', ');
  }

  factory TechnicianJob.fromMap(Map<String, dynamic> map) {
    final customer = map['customers'] is Map<String, dynamic>
        ? map['customers'] as Map<String, dynamic>
        : <String, dynamic>{};
    final fullName = customer['full_name']?.toString().trim() ?? '';
    final companyName = customer['company_name']?.toString().trim() ?? '';

    return TechnicianJob(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      customerName: companyName.isNotEmpty ? companyName : fullName,
      phone: customer['phone']?.toString() ?? '',
      address: customer['address']?.toString() ?? '',
      serviceType: map['service_type']?.toString() ?? 'other',
      description: map['description']?.toString() ?? '',
      status: map['status']?.toString() ?? 'assigned',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      plannedDate: map['planned_date'] == null
          ? null
          : DateTime.tryParse(map['planned_date'].toString()),
      plannedProductId: map['planned_product_id']?.toString(),
      plannedProductName: map['planned_product_name']?.toString() ?? '',
      plannedQuantity: (map['planned_quantity'] as num?)?.toDouble() ?? 0,
      plannedUnitPrice: (map['planned_unit_price'] as num?)?.toDouble() ?? 0,
      secretaryName: map['secretary_name']?.toString() ?? '',
      completionNote: map['completion_note']?.toString() ?? '',
      latitude: customer['latitude'] is num
          ? (customer['latitude'] as num).toDouble()
          : null,
      longitude: customer['longitude'] is num
          ? (customer['longitude'] as num).toDouble()
          : null,
      mapsUrl: customer['maps_url']?.toString(),
      city: customer['city']?.toString() ?? '',
      district: customer['district']?.toString() ?? '',
      neighborhood: customer['neighborhood']?.toString() ?? '',
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.tryParse(map['completed_at'].toString()),
      cancelledAt: map['cancelled_at'] == null
          ? null
          : DateTime.tryParse(map['cancelled_at'].toString()),
      cancellationReason: map['cancellation_reason']?.toString() ?? '',
      technicianUnavailableReason:
          map['technician_unavailable_reason']?.toString() ?? '',
      technicianUnavailableNote:
          map['technician_unavailable_note']?.toString() ?? '',
      routeOrder: (map['route_order'] as num?)?.toInt(),
      routePlanDate: map['route_plan_date'] == null
          ? null
          : DateTime.tryParse(map['route_plan_date'].toString()),
      formValues: map['service_form_values'] is Map
          ? Map<String, dynamic>.from(map['service_form_values'] as Map)
          : const <String, dynamic>{},
    );
  }
}


class TechnicianUsedItem {
  const TechnicianUsedItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
}

class TechnicianDayPerformance {
  const TechnicianDayPerformance({
    this.totalRevenue = 0,
    this.collectedAmount = 0,
    this.usedItemCount = 0,
    this.averageJobMinutes = 0,
    this.productQuantities = const <String, double>{},
  });

  final double totalRevenue;
  final double collectedAmount;
  final double usedItemCount;
  final double averageJobMinutes;
  final Map<String, double> productQuantities;
}

class TechnicianCompletedDetail {
  const TechnicianCompletedDetail({
    required this.job,
    this.items = const <TechnicianUsedItem>[],
    this.collectedAmount = 0,
    this.paymentMethod = '',
  });

  final TechnicianJob job;
  final List<TechnicianUsedItem> items;
  final double collectedAmount;
  final String paymentMethod;
}

class ServiceExecutionRepository {
  ServiceExecutionRepository(this._client);

  final SupabaseClient _client;

  Future<List<TechnicianJob>> getTechnicianJobs(String technicianId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const AuthException('Teknisyen oturumu bulunamadı.');
    }

    try {
      final response = await _client.rpc('technician_my_jobs_v23');
      final rawRows = response is List
          ? response
          : response is Map && response['jobs'] is List
              ? response['jobs'] as List
              : const <dynamic>[];

      final rows = rawRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: true);

      await _enrichCustomerLocations(rows);
      final jobs = rows
          .map(TechnicianJob.fromMap)
          .where((job) => const {'assigned', 'in_progress'}.contains(job.status))
          .toList(growable: true);
      _sortJobs(jobs);

      // RPC eski bir sürümse hata vermeden boş dönebiliyor. Yönetici ekranında
      // teknisyene atanmış iş varken tekniker ekranının boş kalmaması için
      // doğrudan tablo sorgusunu ikinci güvenilir kaynak olarak kullan.
      if (jobs.isEmpty) {
        return _loadJobsDirect(currentUserId);
      }
      return jobs;
    } on PostgrestException {
      return _loadJobsDirect(currentUserId);
    }
  }

  Future<List<TechnicianJob>> _loadJobsDirect(String technicianId) async {
    final response = await _client
        .from('service_requests')
        .select(
          '*, customers(full_name, company_name, phone, city, district, neighborhood, address, latitude, longitude, maps_url)',
        )
        .eq('assigned_technician_id', technicianId)
        .inFilter('status', const ['assigned', 'in_progress'])
        .order('planned_date', ascending: true)
        .order('created_at', ascending: false);

    final rows = (response as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final jobs = rows.map(TechnicianJob.fromMap).toList(growable: true);
    _sortJobs(jobs);
    return jobs;
  }

  void _sortJobs(List<TechnicianJob> jobs) {
    jobs.sort((a, b) {
      final ao = a.routeOrder;
      final bo = b.routeOrder;
      if (ao != null || bo != null) return (ao ?? 9999).compareTo(bo ?? 9999);
      final ad = a.plannedDate;
      final bd = b.plannedDate;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return 0;
    });
  }

  Future<List<TechnicianJob>> getCompletedJobsForDay(DateTime day) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return const [];

    final start = DateTime(day.year, day.month, day.day).toUtc();
    final end = DateTime(day.year, day.month, day.day + 1).toUtc();
    final rows = await _client
        .from('service_requests')
        .select(
          '*, customers(full_name, company_name, phone, city, district, neighborhood, address, latitude, longitude, maps_url)',
        )
        .eq('assigned_technician_id', currentUserId)
        .eq('status', 'completed')
        .gte('completed_at', start.toIso8601String())
        .lt('completed_at', end.toIso8601String())
        .order('completed_at', ascending: false);

    return (rows as List)
        .whereType<Map>()
        .map((row) => TechnicianJob.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<TechnicianJob>> getFailedJobsForDay(DateTime day) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return const [];

    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    try {
      final response = await _client.rpc(
        'technician_job_history_v1',
        params: {'p_day': dayKey},
      );
      final rawRows = response is List
          ? response
          : response is Map && response['jobs'] is List
              ? response['jobs'] as List
              : const <dynamic>[];
      final rows = rawRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: true);
      await _enrichCustomerLocations(rows);
      return rows
          .map(TechnicianJob.fromMap)
          .where((job) =>
              job.status == 'could_not_complete' ||
              job.status == 'cancelled')
          .toList(growable: false);
    } on PostgrestException {
      final start = DateTime(day.year, day.month, day.day).toUtc();
      final end = DateTime(day.year, day.month, day.day + 1).toUtc();
      final rows = await _client
          .from('service_requests')
          .select(
            '*, customers(full_name, company_name, phone, city, district, neighborhood, address, latitude, longitude, maps_url)',
          )
          .eq('assigned_technician_id', currentUserId)
          .inFilter('status', const ['could_not_complete', 'cancelled'])
          .gte('planned_date', start.toIso8601String())
          .lt('planned_date', end.toIso8601String())
          .order('planned_date', ascending: true);
      return (rows as List)
          .whereType<Map>()
          .map((row) => TechnicianJob.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }
  }

  Future<void> rescheduleOwnJob({
    required String serviceRequestId,
    required DateTime plannedAt,
    String note = '',
  }) async {
    await _client.rpc(
      'technician_reschedule_own_job_v1',
      params: {
        'p_service_request_id': serviceRequestId,
        'p_planned_at': plannedAt.toUtc().toIso8601String(),
        'p_note': note.trim(),
      },
    );
  }

  Future<String> sendOwnJobToSecretary({
    required String serviceRequestId,
    String note = '',
  }) async {
    final result = await _client.rpc(
      'technician_send_job_to_secretary_v1',
      params: {
        'p_service_request_id': serviceRequestId,
        'p_note': note.trim(),
      },
    );
    if (result is Map) {
      return result['secretary_name']?.toString() ?? 'Sekreter';
    }
    return 'Sekreter';
  }

  Future<void> _enrichCustomerLocations(List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((row) => row['customer_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return;

    try {
      final customers = await _client
          .from('customers')
          .select('id, full_name, company_name, phone, city, district, neighborhood, address, latitude, longitude, maps_url')
          .inFilter('id', ids);
      final byId = <String, Map<String, dynamic>>{};
      for (final raw in customers as List) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = item;
      }
      for (final row in rows) {
        final customerId = row['customer_id']?.toString() ?? '';
        final customer = byId[customerId];
        if (customer != null) row['customers'] = customer;
      }
    } catch (_) {
      // Konum zenginleştirmesi başarısız olsa da adres ile navigasyon devam eder.
    }
  }

  Future<TechnicianJob?> getJob(String serviceRequestId) async {
    final row = await _client
        .from('service_requests')
        .select(
          '*, customers(full_name, company_name, phone, city, district, neighborhood, address, latitude, longitude, maps_url)',
        )
        .eq('id', serviceRequestId)
        .maybeSingle();
    if (row == null) return null;
    final data = Map<String, dynamic>.from(row);
    final creatorId = data['created_by']?.toString();
    if (creatorId?.isNotEmpty == true) {
      final profile = await _client
          .from('profiles')
          .select('full_name, role')
          .eq('id', creatorId!)
          .maybeSingle();
      if (profile != null && profile['role']?.toString() == 'secretary') {
        data['secretary_name'] = profile['full_name']?.toString() ?? '';
      }
    }
    return TechnicianJob.fromMap(data);
  }

  Future<void> updateServiceContent({
    required String serviceRequestId,
    required String serviceType,
    required String description,
    required String completionNote,
  }) async {
    await _client.from('service_requests').update({
      'service_type': serviceType,
      'description': description.trim(),
      'completion_note': completionNote.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', serviceRequestId);
  }

  Future<void> updateServiceFormValues({
    required String serviceRequestId,
    required Map<String, dynamic> values,
  }) async {
    try {
      await _client.from('service_requests').update({
        'service_form_values': values,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', serviceRequestId);
    } on PostgrestException catch (error) {
      final text = '${error.code} ${error.message}'.toLowerCase();
      if (text.contains('service_form_values') || text.contains('pgrst204')) {
        // Yeni migration henüz kurulmamışsa servis kapatma akışını bozmayız.
        // Değerlerin kalıcı saklanması için SUPABASE_V7_DINAMIK_SERVIS_FORMU.sql
        // dosyası bir kez uygulanmalıdır.
        return;
      }
      rethrow;
    }
  }

  Future<void> startService(String serviceRequestId) async {
    await _client
        .from('service_requests')
        .update({
          'status': 'in_progress',
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', serviceRequestId);
  }

  Future<List<Map<String, dynamic>>> getActiveProducts(String technicianId) async {
    // V6 tekniker ekranı, yalnız araçta bulunanları değil firmanın aktif ürünlerini
    // de gösterir. Böylece tekniker merkez depoda bulunan bir ürünü sahada
    // kullanabilir; araç stoğu tamamlamada eksiye düşerek eksik malzeme olarak
    // görünür. Yeni RPC henüz kurulmadıysa eski araç-stok RPC'sine geri düşeriz.
    try {
      final rows = await _client.rpc('technician_service_products_v1');
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException {
      final rows = await _client.rpc(
        'technician_vehicle_products_v11',
        params: {'p_technician_id': technicianId},
      );
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  Future<void> completeService({
    required String serviceRequestId,
    required String customerId,
    required String companyId,
    required String technicianId,
    required String workDescription,
    required double serviceAmount,
    required double extraAmount,
    required double collectedAmount,
    required String paymentMethod,
    required List<Map<String, dynamic>> items,
  }) async {
    final params = {
      'p_service_request_id': serviceRequestId,
      'p_work_description': workDescription.trim(),
      'p_service_amount': serviceAmount,
      'p_extra_amount': extraAmount,
      'p_collected_amount': collectedAmount,
      'p_payment_method': paymentMethod,
      'p_items': items
          .map(
            (item) => {
              'product_id': item['product_id'],
              'quantity': item['quantity'],
              'unit_price': item['unit_price'],
            },
          )
          .toList(growable: false),
    };

    try {
      await _client.rpc('technician_complete_service_v1', params: params);
    } on PostgrestException {
      // V6 SQL henüz kurulmadıysa mevcut servis kapatma fonksiyonu ile normal
      // servisleri çalıştırmaya devam eder. Araç stoğunu eksiye düşürme özelliği
      // için SUPABASE_V5_TEKNIKER_FINAL.sql kurulmalıdır.
      await _client.rpc('complete_service_v5', params: params);
    }
  }


  Future<TechnicianDayPerformance> getTechnicianDayPerformance(DateTime day) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const TechnicianDayPerformance();
    }
    final start = DateTime(day.year, day.month, day.day).toUtc();
    final end = DateTime(day.year, day.month, day.day + 1).toUtc();
    final raw = await _client
        .from('service_requests')
        .select('id, price, collected_amount, started_at, completed_at')
        .eq('assigned_technician_id', currentUserId)
        .eq('status', 'completed')
        .gte('completed_at', start.toIso8601String())
        .lt('completed_at', end.toIso8601String());
    final rows = (raw as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (rows.isEmpty) return const TechnicianDayPerformance();

    final ids = rows.map((e) => e['id']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    double revenue = 0;
    double collected = 0;
    double durationTotal = 0;
    int durationCount = 0;
    for (final row in rows) {
      revenue += (row['price'] as num?)?.toDouble() ?? 0;
      collected += (row['collected_amount'] as num?)?.toDouble() ?? 0;
      final started = DateTime.tryParse(row['started_at']?.toString() ?? '');
      final completed = DateTime.tryParse(row['completed_at']?.toString() ?? '');
      if (started != null && completed != null && completed.isAfter(started)) {
        durationTotal += completed.difference(started).inMinutes.toDouble();
        durationCount++;
      }
    }

    final productQuantities = <String, double>{};
    double itemCount = 0;
    if (ids.isNotEmpty) {
      final itemRaw = await _client
          .from('service_items')
          .select('product_name, quantity')
          .inFilter('service_request_id', ids);
      for (final rawItem in itemRaw as List) {
        if (rawItem is! Map) continue;
        final name = rawItem['product_name']?.toString().trim() ?? '';
        final qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0;
        if (name.isEmpty || qty <= 0) continue;
        productQuantities[name] = (productQuantities[name] ?? 0) + qty;
        itemCount += qty;
      }
    }
    return TechnicianDayPerformance(
      totalRevenue: revenue,
      collectedAmount: collected,
      usedItemCount: itemCount,
      averageJobMinutes: durationCount == 0 ? 0 : durationTotal / durationCount,
      productQuantities: productQuantities,
    );
  }

  Future<TechnicianCompletedDetail?> getCompletedJobDetail(String serviceRequestId) async {
    final job = await getJob(serviceRequestId);
    if (job == null) return null;
    final rawItems = await _client
        .from('service_items')
        .select('product_name, quantity, unit_price, line_total')
        .eq('service_request_id', serviceRequestId)
        .order('id');
    final items = <TechnicianUsedItem>[];
    for (final raw in rawItems as List) {
      if (raw is! Map) continue;
      items.add(TechnicianUsedItem(
        productName: raw['product_name']?.toString() ?? '',
        quantity: (raw['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (raw['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (raw['line_total'] as num?)?.toDouble() ?? 0,
      ));
    }
    double collected = 0;
    String paymentMethod = '';
    try {
      final payment = await _client
          .from('payments')
          .select('amount, payment_method')
          .eq('service_request_id', serviceRequestId)
          .order('payment_date', ascending: false)
          .limit(1)
          .maybeSingle();
      if (payment != null) {
        collected = (payment['amount'] as num?)?.toDouble() ?? 0;
        paymentMethod = payment['payment_method']?.toString() ?? '';
      }
    } catch (_) {}
    return TechnicianCompletedDetail(
      job: job,
      items: items,
      collectedAmount: collected,
      paymentMethod: paymentMethod,
    );
  }

  Future<void> saveTechnicianRouteOrder(List<String> serviceRequestIds) async {
    await _client.rpc(
      'technician_save_route_order_v1',
      params: {'p_service_request_ids': serviceRequestIds},
    );
  }

  Future<void> saveCustomerMapPoint({
    required String customerId,
    required double latitude,
    required double longitude,
  }) async {
    await _client.rpc(
      'technician_set_customer_map_point_v1',
      params: {
        'p_customer_id': customerId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
  }

  Future<void> reportCannotAttend({
    required String serviceRequestId,
    required String reason,
    String note = '',
  }) async {
    await _client.rpc(
      'technician_cannot_attend_v1',
      params: {
        'p_service_request_id': serviceRequestId,
        'p_reason': reason.trim(),
        'p_note': note.trim(),
      },
    );
  }

  Future<void> markCouldNotComplete({
    required String serviceRequestId,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const FormatException('Tamamlanamama sebebi boş olamaz.');
    }

    try {
      // RLS nedeniyle teknikerin doğrudan UPDATE'i bazı kurulumlarda sessizce
      // 0 satır etkileyebiliyor. V9 security-definer RPC kaydı gerçekten kapatır,
      // aktif rota listesinden çıkarır; tekniker atamasını geçmiş için korur.
      await _client.rpc(
        'technician_mark_could_not_complete_v1',
        params: {
          'p_service_request_id': serviceRequestId,
          'p_reason': cleanReason,
        },
      );
      return;
    } on PostgrestException catch (error) {
      final text = '${error.code} ${error.message}'.toLowerCase();
      final missingFunction = text.contains('technician_mark_could_not_complete_v1') ||
          text.contains('pgrst202') ||
          text.contains('42883');
      if (!missingFunction) rethrow;
    }

    // Geriye uyumluluk: V9 SQL henüz uygulanmadıysa eski doğrudan güncellemeyi dene.
    // Kalıcı çözüm için SUPABASE_V9_SERVIS_TAKIP_VE_TEKNIKER_GECMIS.sql çalıştırılmalıdır.
    await _client
        .from('service_requests')
        .update({
          'status': 'could_not_complete',
          'completion_note': cleanReason,
          'route_order': null,
          'route_plan_date': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', serviceRequestId);
  }
}
