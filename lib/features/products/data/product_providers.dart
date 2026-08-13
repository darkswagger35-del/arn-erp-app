import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_client_provider.dart';
import '../domain/product_models.dart';
import 'product_repository.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(supabaseClientProvider));
});

final productsProvider = FutureProvider.autoDispose<List<ProductItem>>((ref) {
  return ref.watch(productRepositoryProvider).getProducts();
});

final productCategoriesProvider =
    FutureProvider.autoDispose<List<ProductCategory>>((ref) {
      return ref.watch(productRepositoryProvider).getCategories();
    });
