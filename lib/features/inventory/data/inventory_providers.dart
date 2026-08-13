import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/supabase_client_provider.dart';
import '../domain/inventory_models.dart';
import 'inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) => InventoryRepository(ref.watch(supabaseClientProvider)));
final warehousesProvider = FutureProvider.autoDispose<List<WarehouseItem>>((ref) => ref.watch(inventoryRepositoryProvider).getWarehouses());
final warehouseStocksProvider = FutureProvider.autoDispose.family<List<WarehouseStockItem>, String>((ref, id) => ref.watch(inventoryRepositoryProvider).getWarehouseStocks(id));
final stockMovementsProvider = FutureProvider.autoDispose<List<StockMovementItem>>((ref) => ref.watch(inventoryRepositoryProvider).getMovements());
