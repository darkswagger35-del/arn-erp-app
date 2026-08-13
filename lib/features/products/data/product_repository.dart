import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/product_models.dart';

class ProductRepository {
  ProductRepository(this._client);

  final SupabaseClient _client;

  Future<String> _companyId() async {
    final value = await _client.rpc('current_company_id');
    final companyId = value?.toString() ?? '';
    if (companyId.isEmpty) {
      throw StateError('Kullanıcının firma bilgisi bulunamadı.');
    }
    return companyId;
  }

  Future<List<ProductItem>> getProducts({bool includePassive = true}) async {
    var query = _client
        .from('products')
        .select(
          'id, name, category_id, unit, stock_quantity, maintenance_months, is_active, product_categories(name)',
        );

    if (!includePassive) {
      query = query.eq('is_active', true);
    }

    final rows = await query.order('name', ascending: true);
    return List<Map<String, dynamic>>.from(
      rows,
    ).map(ProductItem.fromMap).toList(growable: false);
  }

  Future<List<ProductCategory>> getCategories({
    bool includePassive = true,
  }) async {
    var query = _client
        .from('product_categories')
        .select('id, name, is_active');
    if (!includePassive) {
      query = query.eq('is_active', true);
    }
    final rows = await query.order('name', ascending: true);
    final unique = <String, ProductCategory>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final category = ProductCategory.fromMap(row);
      if (category.id.isNotEmpty) {
        unique[category.id] = category;
      }
    }
    return unique.values.toList(growable: false);
  }

  Future<String> saveProduct({String? id, required ProductDraft draft}) async {
    final companyId = await _companyId();
    final values = draft.toMap(companyId);

    if (id == null) {
      final row = await _client
          .from('products')
          .insert(values)
          .select('id')
          .single();
      return row['id'].toString();
    }

    await _client.from('products').update(values).eq('id', id);
    return id;
  }

  Future<void> deleteProduct(String id) async {
    await _client.rpc('delete_product_v11', params: {'p_product_id': id});
  }

  Future<void> setProductActive(String id, bool isActive) async {
    await _client
        .from('products')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<void> saveCategory({String? id, required String name}) async {
    final companyId = await _companyId();
    final values = {
      'company_id': companyId,
      'name': name.trim(),
      'is_active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (id == null) {
      await _client.from('product_categories').insert(values);
    } else {
      await _client.from('product_categories').update(values).eq('id', id);
    }
  }

  Future<void> setCategoryActive(String id, bool isActive) async {
    await _client
        .from('product_categories')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);
  }
}
