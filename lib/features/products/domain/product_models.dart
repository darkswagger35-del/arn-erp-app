class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory ProductCategory.fromMap(Map<String, dynamic> map) {
    return ProductCategory(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

class ProductItem {
  const ProductItem({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.unit,
    required this.stockQuantity,
    required this.maintenanceMonths,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String categoryName;
  final String unit;
  final double stockQuantity;
  final int maintenanceMonths;
  final bool isActive;

  String get maintenanceLabel => maintenanceMonths <= 0
      ? 'Bakım takibi yok'
      : '$maintenanceMonths ay';

  factory ProductItem.fromMap(Map<String, dynamic> map) {
    final category = map['product_categories'] is Map<String, dynamic>
        ? map['product_categories'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return ProductItem(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      categoryId: (map['category_id']?.toString().trim().isEmpty ?? true)
          ? null
          : map['category_id']?.toString(),
      categoryName: category['name']?.toString() ?? '',
      unit: map['unit']?.toString() ?? 'adet',
      stockQuantity: (map['stock_quantity'] as num?)?.toDouble() ?? 0,
      maintenanceMonths: (map['maintenance_months'] as num?)?.toInt() ?? 0,
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.maintenanceMonths,
    required this.isActive,
  });

  final String name;
  final String? categoryId;
  final String unit;
  final int maintenanceMonths;
  final bool isActive;

  Map<String, dynamic> toMap(String companyId) {
    return {
      'company_id': companyId,
      'name': name.trim(),
      'category_id': categoryId,
      'unit': unit,
      'maintenance_months': maintenanceMonths,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
