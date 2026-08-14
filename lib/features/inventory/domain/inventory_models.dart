class WarehouseItem {
  const WarehouseItem({
    required this.id,
    required this.name,
    required this.type,
    required this.isActive,
    this.technicianId,
    this.technicianName,
  });

  final String id;
  final String name;
  final String type;
  final bool isActive;
  final String? technicianId;
  final String? technicianName;

  factory WarehouseItem.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] is Map<String, dynamic>
        ? map['profiles'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return WarehouseItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Depo',
      type: map['type']?.toString() ?? 'main',
      isActive: map['is_active'] as bool? ?? true,
      technicianId: map['assigned_technician_id']?.toString(),
      technicianName: profile['full_name']?.toString(),
    );
  }
}

class WarehouseStockItem {
  const WarehouseStockItem({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
  });

  final String productId;
  final String productName;
  final String unit;
  final double quantity;

  factory WarehouseStockItem.fromMap(Map<String, dynamic> map) {
    final product = map['products'] is Map<String, dynamic>
        ? map['products'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return WarehouseStockItem(
      productId: map['product_id']?.toString() ?? '',
      productName: product['name']?.toString() ?? 'Ürün',
      unit: product['unit']?.toString() ?? 'adet',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class StockMovementItem {
  const StockMovementItem({
    required this.id,
    required this.productName,
    required this.warehouseName,
    required this.type,
    required this.quantity,
    required this.createdAt,
    this.notes,
    this.serviceRequestId,
    this.technicianName,
    this.customerName,
    this.customerPhone,
    this.serviceType,
  });

  final String id;
  final String productName;
  final String warehouseName;
  final String type;
  final double quantity;
  final DateTime createdAt;
  final String? notes;
  final String? serviceRequestId;
  final String? technicianName;
  final String? customerName;
  final String? customerPhone;
  final String? serviceType;

  String get displayTechnician {
    final explicit = technicianName?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    const suffix = ' Araç Deposu';
    if (warehouseName.endsWith(suffix)) {
      return warehouseName.substring(0, warehouseName.length - suffix.length);
    }
    return '—';
  }

  factory StockMovementItem.fromMap(
    Map<String, dynamic> map, {
    Map<String, dynamic>? context,
  }) {
    final product = map['products'] is Map<String, dynamic>
        ? map['products'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final warehouse = map['warehouses'] is Map<String, dynamic>
        ? map['warehouses'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return StockMovementItem(
      id: map['id']?.toString() ?? '',
      productName: product['name']?.toString() ?? 'Ürün',
      warehouseName: warehouse['name']?.toString() ?? 'Depo',
      type: map['movement_type']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      notes: map['notes']?.toString(),
      serviceRequestId: map['service_request_id']?.toString(),
      technicianName: context?['technician_name']?.toString(),
      customerName: context?['customer_name']?.toString(),
      customerPhone: context?['customer_phone']?.toString(),
      serviceType: context?['service_type']?.toString(),
    );
  }
}
