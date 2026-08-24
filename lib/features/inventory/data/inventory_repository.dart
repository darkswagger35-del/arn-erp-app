import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/inventory_models.dart';

class InventoryRepository {
  InventoryRepository(this._client);
  final SupabaseClient _client;

  Future<void> ensureWarehouses() => _client.rpc('ensure_company_warehouses');

  Future<List<WarehouseItem>> getWarehouses() async {
    await ensureWarehouses();
    final rows = await _client
        .from('warehouses')
        .select('id, name, type, is_active, assigned_technician_id, profiles!warehouses_assigned_technician_id_fkey(full_name, is_active, deleted_at)')
        .eq('is_active', true)
        .order('type')
        .order('name');
    final items = List<Map<String, dynamic>>.from(rows)
        .where((row) {
          if (row['type']?.toString() != 'vehicle') return true;
          final profile = row['profiles'];
          if (profile is! Map) return false;
          return profile['is_active'] == true && profile['deleted_at'] == null;
        })
        .map(WarehouseItem.fromMap)
        .toList();
    final unique = <String, WarehouseItem>{};
    for (final item in items) {
      final key = item.type == 'vehicle' && item.technicianId != null
          ? 'vehicle:${item.technicianId}'
          : '${item.type}:${item.id}';
      unique.putIfAbsent(key, () => item);
    }
    return unique.values.toList(growable: false);
  }

  Future<List<WarehouseStockItem>> getWarehouseStocks(String warehouseId) async {
    final rows = await _client
        .from('warehouse_stocks')
        .select('product_id, quantity, products(name, unit)')
        .eq('warehouse_id', warehouseId)
        .gt('quantity', 0)
        .order('quantity', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map(WarehouseStockItem.fromMap).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final rows = await _client.from('products').select('id, name, unit').eq('is_active', true).order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addStock({required String warehouseId, required String productId, required double quantity, String? notes}) async {
    final companyId = (await _client.rpc('current_company_id')).toString();
    await _client.from('stock_movements').insert({
      'company_id': companyId,
      'warehouse_id': warehouseId,
      'product_id': productId,
      'movement_type': 'in',
      'quantity': quantity,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> removeStock({
    required String warehouseId,
    required String productId,
    required double quantity,
    String? reason,
    String? notes,
  }) async {
    final companyId = (await _client.rpc('current_company_id')).toString();
    final cleanReason = reason?.trim() ?? '';
    final cleanNotes = notes?.trim() ?? '';
    final description = [
      if (cleanReason.isNotEmpty) 'Sebep: $cleanReason',
      if (cleanNotes.isNotEmpty) cleanNotes,
    ].join(' - ');

    await _client.from('stock_movements').insert({
      'company_id': companyId,
      'warehouse_id': warehouseId,
      'product_id': productId,
      'movement_type': 'out',
      'quantity': quantity,
      'notes': description.isEmpty ? 'Ürün ekranından stok düşüldü' : description,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> transfer({required String productId, required String sourceWarehouseId, required String destinationWarehouseId, required double quantity, String? notes}) async {
    await _client.rpc('transfer_stock', params: {
      'p_product_id': productId,
      'p_source_warehouse_id': sourceWarehouseId,
      'p_destination_warehouse_id': destinationWarehouseId,
      'p_quantity': quantity,
      'p_notes': notes,
    });
  }

  Future<WarehouseItem> getMainWarehouse() async {
    final warehouses = await getWarehouses();
    return warehouses.firstWhere(
      (item) => item.type == 'main',
      orElse: () => warehouses.first,
    );
  }

  Future<void> reverseMovement(String movementId) async {
    await _client.rpc('reverse_stock_movement', params: {'p_movement_id': movementId});
  }

  Future<void> deleteMovement(String movementId) async {
    await _client.rpc('delete_stock_movement', params: {'p_movement_id': movementId});
  }

  Future<List<StockMovementItem>> getMovements({
    DateTime? start,
    DateTime? end,
    String? productId,
  }) async {
    dynamic query = _client
        .from('stock_movements')
        .select('id, movement_type, quantity, notes, created_at, product_id, service_request_id, products(name), warehouses(name)');
    if (start != null) query = query.gte('created_at', start.toUtc().toIso8601String());
    if (end != null) query = query.lt('created_at', end.toUtc().toIso8601String());
    if (productId != null && productId.isNotEmpty) query = query.eq('product_id', productId);
    final rawRows = List<Map<String, dynamic>>.from(
      await query.order('created_at', ascending: false).limit(1000),
    );

    final requestIds = rawRows
        .map((row) => row['service_request_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final contexts = <String, Map<String, dynamic>>{};

    if (requestIds.isNotEmpty) {
      try {
        final requestRows = List<Map<String, dynamic>>.from(
          await _client
              .from('service_requests')
              .select('id, customer_id, assigned_technician_id, service_type')
              .inFilter('id', requestIds),
        );
        final customerIds = requestRows
            .map((row) => row['customer_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);
        final technicianIds = requestRows
            .map((row) => row['assigned_technician_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false);

        final customers = <String, Map<String, dynamic>>{};
        if (customerIds.isNotEmpty) {
          final rows = List<Map<String, dynamic>>.from(
            await _client
                .from('customers')
                .select('id, full_name, phone')
                .inFilter('id', customerIds),
          );
          for (final row in rows) {
            customers[row['id'].toString()] = row;
          }
        }

        final technicians = <String, String>{};
        if (technicianIds.isNotEmpty) {
          final rows = List<Map<String, dynamic>>.from(
            await _client
                .from('profiles')
                .select('id, full_name')
                .inFilter('id', technicianIds),
          );
          for (final row in rows) {
            technicians[row['id'].toString()] = row['full_name']?.toString() ?? '';
          }
        }

        for (final request in requestRows) {
          final requestId = request['id']?.toString() ?? '';
          if (requestId.isEmpty) continue;
          final customer = customers[request['customer_id']?.toString() ?? ''];
          contexts[requestId] = {
            'customer_name': customer?['full_name'],
            'customer_phone': customer?['phone'],
            'technician_name': technicians[request['assigned_technician_id']?.toString() ?? ''],
            'service_type': request['service_type'],
          };
        }
    
      } catch (_) {
        // Hareket listesi yine çalışsın; servis/müşteri zenginleştirmesi opsiyoneldir.
      }
    }
    return rawRows
        .map((row) => StockMovementItem.fromMap(
              row,
              context: contexts[row['service_request_id']?.toString() ?? ''],
            ))
        .toList(growable: false);
  }
}
