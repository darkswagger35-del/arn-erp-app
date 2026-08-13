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
        .select('id, name, type, is_active, assigned_technician_id, profiles!warehouses_assigned_technician_id_fkey(full_name)')
        .eq('is_active', true)
        .order('type')
        .order('name');
    final items = List<Map<String, dynamic>>.from(rows).map(WarehouseItem.fromMap).toList();
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
        .select('id, movement_type, quantity, notes, created_at, product_id, products(name), warehouses(name)');
    if (start != null) query = query.gte('created_at', start.toUtc().toIso8601String());
    if (end != null) query = query.lt('created_at', end.toUtc().toIso8601String());
    if (productId != null && productId.isNotEmpty) query = query.eq('product_id', productId);
    final rows = await query.order('created_at', ascending: false).limit(1000);
    return List<Map<String, dynamic>>.from(rows).map(StockMovementItem.fromMap).toList(growable: false);
  }
}
