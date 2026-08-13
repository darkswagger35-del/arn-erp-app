import 'package:supabase_flutter/supabase_flutter.dart';

class ExcelTransferRepository {
  ExcelTransferRepository(this._client);

  final SupabaseClient _client;

  Future<String> _companyId() async {
    final value = await _client.rpc('current_company_id');
    final id = value?.toString() ?? '';
    if (id.isEmpty) throw StateError('Firma bilgisi bulunamadı.');
    return id;
  }

  Future<List<Map<String, dynamic>>> exportCustomers() async {
    final rows = await _client
        .from('customers')
        .select(
          'id, customer_type, full_name, company_name, phone, alternative_phone, '
          'email, city, district, neighborhood, address, notes, is_active, registration_date, created_at',
        )
        .order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> exportHistory() async {
    final rows = await _client.rpc(
      'erp_report_details_v41',
      params: {
        'p_start': DateTime(2000, 1, 1).toUtc().toIso8601String(),
        'p_end': DateTime(2100, 1, 1).toUtc().toIso8601String(),
      },
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> exportProducts() async {
    final rows = await _client
        .from('products')
        .select('id, name, unit, stock_quantity, maintenance_months, is_active, product_categories(name)')
        .order('name', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> exportStaff() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name, role, is_active')
        .inFilter('role', ['manager', 'admin', 'secretary', 'technician'])
        .order('role', ascending: true)
        .order('full_name', ascending: true);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<ExcelImportReferenceData> importReferenceData() async {
    final results = await Future.wait([
      _client
          .from('products')
          .select('id, name, maintenance_months, is_active')
          .eq('is_active', true)
          .order('name'),
      _client
          .from('profiles')
          .select('id, full_name, role, is_active')
          .inFilter('role', ['secretary', 'technician'])
          .eq('is_active', true)
          .order('full_name'),
      _client
          .from('customers')
          .select('id, full_name, phone, city, district, address'),
    ]);
    return ExcelImportReferenceData(
      products: List<Map<String, dynamic>>.from(results[0] as List),
      staff: List<Map<String, dynamic>>.from(results[1] as List),
      customers: List<Map<String, dynamic>>.from(results[2] as List),
    );
  }

  Future<ExcelImportResult> importRows({
    required String batchId,
    required List<ExcelImportRow> rows,
  }) async {
    final companyId = await _companyId();
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Oturum bulunamadı.');

    final refs = await importReferenceData();
    final productByName = <String, Map<String, dynamic>>{
      for (final p in refs.products) _normalize(p['name']?.toString() ?? ''): p,
    };
    final secretaryByName = <String, Map<String, dynamic>>{
      for (final p in refs.staff)
        if (p['role']?.toString() == 'secretary') _normalize(p['full_name']?.toString() ?? ''): p,
    };
    final technicianByName = <String, Map<String, dynamic>>{
      for (final p in refs.staff)
        if (p['role']?.toString() == 'technician') _normalize(p['full_name']?.toString() ?? ''): p,
    };

    final customerByPhone = <String, String>{};
    final customerByFallback = <String, String>{};
    for (final c in refs.customers) {
      final id = c['id']?.toString() ?? '';
      final phone = normalizePhone(c['phone']?.toString() ?? '');
      if (id.isEmpty) continue;
      if (phone.isNotEmpty) customerByPhone[phone] = id;
      customerByFallback[_customerKey(
        c['full_name']?.toString() ?? '',
        c['address']?.toString() ?? '',
      )] = id;
    }

    final existingRows = await _client
        .from('historical_customer_sales')
        .select('import_source_row')
        .eq('import_batch_id', batchId);
    final importedSourceRows = List<Map<String, dynamic>>.from(existingRows as List)
        .map((e) => (e['import_source_row'] as num?)?.toInt())
        .whereType<int>()
        .toSet();

    final historicalRows = await _client
        .from('historical_customer_sales')
        .select('customer_id, product_id, transaction_date, quantity, amount');
    final existingSignatures = List<Map<String, dynamic>>.from(historicalRows as List)
        .map((e) => _saleSignature(
              customerId: e['customer_id']?.toString() ?? '',
              productId: e['product_id']?.toString() ?? '',
              date: e['transaction_date']?.toString() ?? '',
              quantity: (e['quantity'] as num?)?.toDouble() ?? 0,
              amount: (e['amount'] as num?)?.toDouble() ?? 0,
            ))
        .toSet();

    var imported = 0;
    var skipped = 0;
    final errors = <String>[];

    for (final row in rows) {
      if (importedSourceRows.contains(row.sourceRow)) {
        skipped++;
        continue;
      }
      try {
        final product = productByName[_normalize(row.productName)];
        if (product == null) {
          throw StateError('Ürün bulunamadı: ${row.productName}');
        }
        final productId = product['id']?.toString() ?? '';
        final productName = product['name']?.toString() ?? row.productName;
        final maintenanceMonths = (product['maintenance_months'] as num?)?.toInt() ?? 0;

        String? secretaryId;
        if (row.secretaryName.trim().isNotEmpty) {
          secretaryId = secretaryByName[_normalize(row.secretaryName)]?['id']?.toString();
          if (secretaryId == null) {
            throw StateError('Sekreter bulunamadı: ${row.secretaryName}');
          }
        }
        String? technicianId;
        if (row.technicianName.trim().isNotEmpty) {
          technicianId = technicianByName[_normalize(row.technicianName)]?['id']?.toString();
          if (technicianId == null) {
            throw StateError('Tekniker bulunamadı: ${row.technicianName}');
          }
        }

        final phone = normalizePhone(row.phone);
        final fallbackKey = _customerKey(row.fullName, row.address);
        var customerId = phone.isNotEmpty ? customerByPhone[phone] : null;
        customerId ??= customerByFallback[fallbackKey];

        if (customerId == null) {
          final created = await _client
              .from('customers')
              .insert({
                'company_id': companyId,
                'customer_type': 'individual',
                'full_name': row.fullName.trim(),
                'phone': phone,
                'city': _nullable(row.city),
                'district': _nullable(row.district),
                'address': row.address.trim(),
                'is_active': true,
                'registration_date': row.transactionDate.toIso8601String(),
                'created_at': row.transactionDate.toIso8601String(),
                'updated_at': DateTime.now().toUtc().toIso8601String(),
                'created_by': secretaryId ?? userId,
                'updated_by': userId,
              })
              .select('id')
              .single();
          customerId = created['id'].toString();
          if (phone.isNotEmpty) customerByPhone[phone] = customerId;
          customerByFallback[fallbackKey] = customerId;
        }

        final signature = _saleSignature(
          customerId: customerId,
          productId: productId,
          date: _dateOnly(row.transactionDate),
          quantity: row.quantity,
          amount: row.amount,
        );
        if (existingSignatures.contains(signature)) {
          skipped++;
          continue;
        }

        final nextDate = maintenanceMonths > 0
            ? DateTime(
                row.transactionDate.year,
                row.transactionDate.month + maintenanceMonths,
                row.transactionDate.day,
              )
            : null;

        await _client.from('customer_maintenance_records').insert({
          'company_id': companyId,
          'customer_id': customerId,
          'product_id': productId,
          'product_name': productName,
          'performed_at': _dateOnly(row.transactionDate),
          'next_maintenance_date': nextDate == null ? null : _dateOnly(nextDate),
          'assigned_user_id': technicianId ?? secretaryId,
          'assigned_role': technicianId != null ? 'technician' : 'secretary',
          'secretary_id': secretaryId,
          'technician_id': technicianId,
          'notes': 'Excel içe aktarım. Adet: ${row.quantity}',
          'created_by': userId,
          'import_batch_id': batchId,
          'import_source_row': row.sourceRow,
        });

        await _client.from('historical_customer_sales').insert({
          'company_id': companyId,
          'customer_id': customerId,
          'product_id': productId,
          'product_name': productName,
          'quantity': row.quantity,
          'amount': row.amount,
          'payment_status': row.paymentStatus,
          'payment_due_date': row.paymentDueDate == null ? null : _dateOnly(row.paymentDueDate!),
          'transaction_date': _dateOnly(row.transactionDate),
          'created_by': userId,
          'import_batch_id': batchId,
          'import_source_row': row.sourceRow,
        });
        existingSignatures.add(signature);
        imported++;
      } catch (e) {
        try {
          await _client
              .from('customer_maintenance_records')
              .delete()
              .eq('import_batch_id', batchId)
              .eq('import_source_row', row.sourceRow);
          await _client
              .from('historical_customer_sales')
              .delete()
              .eq('import_batch_id', batchId)
              .eq('import_source_row', row.sourceRow);
        } catch (_) {}
        errors.add('Satır ${row.sourceRow}: ${_cleanError(e)}');
      }
    }

    return ExcelImportResult(imported: imported, skipped: skipped, errors: errors);
  }

  static String normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90') && digits.length == 12) return digits.substring(2);
    if (digits.startsWith('0') && digits.length == 11) return digits.substring(1);
    return digits;
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _saleSignature({
    required String customerId,
    required String productId,
    required String date,
    required double quantity,
    required double amount,
  }) =>
      '$customerId|$productId|$date|${quantity.toStringAsFixed(2)}|${amount.toStringAsFixed(2)}';

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _customerKey(String name, String address) =>
      '${_normalize(name)}|${_normalize(address)}';

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static String _cleanError(Object error) {
    final value = error.toString();
    return value.startsWith('Bad state: ') ? value.substring(11) : value;
  }
}

class ExcelImportReferenceData {
  const ExcelImportReferenceData({
    required this.products,
    required this.staff,
    required this.customers,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> customers;
}

class ExcelImportRow {
  const ExcelImportRow({
    required this.sourceRow,
    required this.fullName,
    required this.phone,
    required this.city,
    required this.district,
    required this.address,
    required this.transactionDate,
    required this.productName,
    required this.quantity,
    required this.amount,
    required this.paymentStatus,
    required this.secretaryName,
    required this.technicianName,
    this.paymentDueDate,
  });

  final int sourceRow;
  final String fullName;
  final String phone;
  final String city;
  final String district;
  final String address;
  final DateTime transactionDate;
  final String productName;
  final double quantity;
  final double amount;
  final String paymentStatus;
  final DateTime? paymentDueDate;
  final String secretaryName;
  final String technicianName;
}

class ExcelImportResult {
  const ExcelImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  final int imported;
  final int skipped;
  final List<String> errors;
}
