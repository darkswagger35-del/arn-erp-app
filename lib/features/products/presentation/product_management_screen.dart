import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/product_providers.dart';
import '../../inventory/data/inventory_providers.dart';
import '../domain/product_models.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends ConsumerState<ProductManagementScreen> {
  final _searchController = TextEditingController();
  String? _categoryFilter;
  bool _showPassive = true;
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final productsAsync = ref.watch(productsProvider);
    final categories = ref.watch(productCategoriesProvider).valueOrNull ?? const <ProductCategory>[];

    return ManagementShell(
      role: role,
      title: 'Ürünler',
      subtitle: 'Ürün kartlarını, bakım sürelerini ve stok miktarlarını profesyonel şekilde yönetin.',
      dark: true,
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showCategoryManager(context),
          icon: const Icon(Icons.category_outlined),
          label: const Text('Kategoriler'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _showProductForm(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Yeni Ürün'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(message: error.toString(), onRetry: _refresh),
        data: (products) {
          final filtered = _filterProducts(products);
          final activeCount = products.where((item) => item.isActive).length;
          final archivedCount = products.length - activeCount;
          final totalStock = products.where((item) => item.isActive).fold<double>(0, (sum, item) => sum + item.stockQuantity);
          final maintenanceTracked = products.where((item) => item.maintenanceMonths > 0).length;
          final selectedProducts = products.where((p) => _selectedIds.contains(p.id)).toList();

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final width = c.maxWidth >= 1100
                      ? (c.maxWidth - 36) / 4
                      : c.maxWidth >= 620
                          ? (c.maxWidth - 12) / 2
                          : c.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _DarkMetric(width: width, title: 'Toplam Ürün', value: '${products.length}', detail: 'Ürün kartı', icon: Icons.inventory_2_outlined, color: const Color(0xFF2F80ED)),
                      _DarkMetric(width: width, title: 'Aktif Ürün', value: '$activeCount', detail: 'Kullanımda', icon: Icons.check_circle_outline, color: const Color(0xFF35C978)),
                      _DarkMetric(width: width, title: 'Arşivde', value: '$archivedCount', detail: 'Geçmişi korunuyor', icon: Icons.archive_outlined, color: const Color(0xFF8B5CF6)),
                      _DarkMetric(width: width, title: 'Aktif Stok', value: _compact(totalStock), detail: 'Arşiv ürünleri hariç • $maintenanceTracked bakım takipli', icon: Icons.warehouse_outlined, color: const Color(0xFFF4B740)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width < 600 ? (MediaQuery.sizeOf(context).width - 64).clamp(220.0, 350.0) : 350,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Ürün adı veya kategori ara...',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          value: _categoryFilter ?? '__all__',
                          decoration: const InputDecoration(labelText: 'Kategori'),
                          items: [
                            const DropdownMenuItem(value: '__all__', child: Text('Tüm kategoriler')),
                            ...categories.where((c) => c.id.isNotEmpty).map(
                                  (category) => DropdownMenuItem(
                                    value: category.id,
                                    child: Text(category.name),
                                  ),
                                ),
                          ],
                          onChanged: (value) => setState(() => _categoryFilter = value == '__all__' ? null : value),
                        ),
                      ),
                      FilterChip(
                        selected: _showPassive,
                        label: const Text('Arşivdekileri göster'),
                        onSelected: (value) => setState(() => _showPassive = value),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: products.where((p) => p.isActive).isEmpty ? null : () => _showStockPicker(products),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Stok Ekle'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12313C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1E5666)),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_selectedIds.length} ürün seçildi', style: const TextStyle(fontWeight: FontWeight.w900)),
                      FilledButton.icon(
                        onPressed: selectedProducts.any((p) => p.isActive && p.stockQuantity > 0)
                            ? () => _bulkRemoveStock(selectedProducts)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Toplu Stok Düş'),
                      ),
                      OutlinedButton.icon(
                        onPressed: selectedProducts.any((p) => p.isActive)
                            ? () => _bulkArchive(selectedProducts)
                            : null,
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Seçilenleri Arşivle'),
                      ),
                      TextButton(
                        onPressed: () => setState(_selectedIds.clear),
                        child: const Text('Seçimi Temizle'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                const _EmptyProducts()
              else
                _DarkProductTable(
                  products: filtered,
                  selectedIds: _selectedIds,
                  onSelect: (product, selected) {
                    setState(() {
                      if (selected) {
                        _selectedIds.add(product.id);
                      } else {
                        _selectedIds.remove(product.id);
                      }
                    });
                  },
                  onSelectAll: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedIds.addAll(filtered.map((p) => p.id));
                      } else {
                        _selectedIds.removeAll(filtered.map((p) => p.id));
                      }
                    });
                  },
                  onEdit: (product) => _showProductForm(context, product: product),
                  onToggleActive: _toggleActive,
                  onAddStock: _showAddStockDialog,
                  onRemoveStock: _showRemoveStockDialog,
                  onArchive: _archiveProduct,
                ),
            ],
          );
        },
      ),
    );
  }

  List<ProductItem> _filterProducts(List<ProductItem> products) {
    final query = _searchController.text.trim().toLowerCase();
    return products.where((product) {
      if (!_showPassive && !product.isActive) return false;
      if (_categoryFilter != null && product.categoryId != _categoryFilter) return false;
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.categoryName.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  void _refresh() {
    ref.invalidate(productsProvider);
    ref.invalidate(productCategoriesProvider);
  }

  Future<void> _archiveProduct(ProductItem product) async {
    if (!product.isActive) {
      await _toggleActive(product);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ürünü arşivle'),
        content: Text(
          '${product.name} aktif ürün listesinden kaldırılacak. Eski servis, rapor ve stok hareketleri SİLİNMEYECEK.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.archive_outlined), label: const Text('Arşivle')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(productRepositoryProvider).setProductActive(product.id, false);
      setState(() => _selectedIds.remove(product.id));
      _refresh();
      if (mounted) _showMessage('Ürün arşivlendi; geçmiş kayıtları korundu.');
    } catch (error) {
      if (mounted) _showMessage('Ürün arşivlenemedi: $error');
    }
  }

  Future<void> _bulkArchive(List<ProductItem> products) async {
    final active = products.where((p) => p.isActive).toList(growable: false);
    if (active.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${active.length} ürünü arşivle'),
        content: const Text('Ürünler listeden kaldırılır; eski servisler, raporlar ve stok hareketleri korunur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Arşivle')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final product in active) {
        await ref.read(productRepositoryProvider).setProductActive(product.id, false);
      }
      setState(_selectedIds.clear);
      _refresh();
      if (mounted) _showMessage('${active.length} ürün arşivlendi. Geçmiş kayıtlar korunuyor.');
    } catch (error) {
      if (mounted) _showMessage('Toplu arşivleme tamamlanamadı: $error');
    }
  }

  Future<void> _toggleActive(ProductItem product) async {
    try {
      await ref.read(productRepositoryProvider).setProductActive(product.id, !product.isActive);
      _refresh();
      if (mounted) _showMessage(product.isActive ? 'Ürün arşivlendi.' : 'Ürün yeniden aktifleştirildi.');
    } catch (error) {
      if (mounted) _showMessage('İşlem yapılamadı: $error');
    }
  }

  Future<void> _showProductForm(BuildContext context, {ProductItem? product}) async {
    final categories = ref.read(productCategoriesProvider).valueOrNull ?? const <ProductCategory>[];
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductFormDialog(
        product: product,
        categories: categories.where((item) => item.isActive).toList(),
      ),
    );
    if (changed == true) _refresh();
  }

  Future<void> _showStockPicker(List<ProductItem> products) async {
    ProductItem? selected = products.where((p) => p.isActive).isNotEmpty
        ? products.where((p) => p.isActive).first
        : null;
    final picked = await showDialog<ProductItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Stok Ekle'),
          content: SizedBox(
            width: 440,
            child: DropdownButtonFormField<ProductItem>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Ürün'),
              items: products.where((p) => p.isActive).map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
              onChanged: (value) => setDialogState(() => selected = value),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
            FilledButton(onPressed: selected == null ? null : () => Navigator.pop(dialogContext, selected), child: const Text('Devam')),
          ],
        ),
      ),
    );
    if (picked != null) await _showAddStockDialog(picked);
  }

  Future<void> _showAddStockDialog(ProductItem product) async {
    final quantityController = TextEditingController();
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${product.name} - Stok Ekle'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mevcut: ${_compact(product.stockQuantity)} ${product.unit}'),
              const SizedBox(height: 12),
              TextField(controller: quantityController, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Miktar (${product.unit})')),
              const SizedBox(height: 12),
              TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Not')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Stok Ekle')),
        ],
      ),
    );
    if (confirmed != true) {
      quantityController.dispose();
      notesController.dispose();
      return;
    }
    final quantity = _parseNumber(quantityController.text) ?? 0;
    if (quantity <= 0) {
      _showMessage('Sıfırdan büyük bir miktar girin.');
      quantityController.dispose();
      notesController.dispose();
      return;
    }
    try {
      final repository = ref.read(inventoryRepositoryProvider);
      final mainWarehouse = await repository.getMainWarehouse();
      await repository.addStock(
        warehouseId: mainWarehouse.id,
        productId: product.id,
        quantity: quantity,
        notes: notesController.text.trim().isEmpty ? 'Ürün ekranından stok girişi' : notesController.text.trim(),
      );
      ref.invalidate(productsProvider);
      ref.invalidate(stockMovementsProvider);
      ref.invalidate(warehousesProvider);
      if (mounted) _showMessage('Stok Ana Depoya eklendi.');
    } catch (error) {
      if (mounted) _showMessage('Stok eklenemedi: $error');
    } finally {
      quantityController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showRemoveStockDialog(ProductItem product) async {
    final quantityController = TextEditingController();
    final notesController = TextEditingController();
    String reason = 'Sayım / Düzeltme';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${product.name} - Stok Düş'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mevcut stok: ${_compact(product.stockQuantity)} ${product.unit}', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextField(controller: quantityController, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Düşülecek miktar (${product.unit})')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: const InputDecoration(labelText: 'Sebep'),
                  items: const [
                    DropdownMenuItem(value: 'Sayım / Düzeltme', child: Text('Sayım / Düzeltme')),
                    DropdownMenuItem(value: 'Satış', child: Text('Satış')),
                    DropdownMenuItem(value: 'Kırık', child: Text('Kırık')),
                    DropdownMenuItem(value: 'Hurda', child: Text('Hurda')),
                    DropdownMenuItem(value: 'Serviste Kullanıldı', child: Text('Serviste Kullanıldı')),
                    DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => reason = value); },
                ),
                const SizedBox(height: 12),
                TextField(controller: notesController, maxLines: 2, decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
            FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.remove), label: const Text('Stok Düş')),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      quantityController.dispose();
      notesController.dispose();
      return;
    }
    final quantity = _parseNumber(quantityController.text) ?? 0;
    if (quantity <= 0 || quantity > product.stockQuantity) {
      _showMessage('Geçerli ve mevcut stoktan fazla olmayan bir miktar girin.');
      quantityController.dispose();
      notesController.dispose();
      return;
    }
    try {
      final repository = ref.read(inventoryRepositoryProvider);
      final mainWarehouse = await repository.getMainWarehouse();
      await repository.removeStock(
        warehouseId: mainWarehouse.id,
        productId: product.id,
        quantity: quantity,
        reason: reason,
        notes: notesController.text,
      );
      ref.invalidate(productsProvider);
      ref.invalidate(stockMovementsProvider);
      ref.invalidate(warehousesProvider);
      if (mounted) _showMessage('${_compact(quantity)} ${product.unit} stoktan düşüldü.');
    } catch (error) {
      if (mounted) _showMessage('Stok düşürülemedi: $error');
    } finally {
      quantityController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _bulkRemoveStock(List<ProductItem> products) async {
    final active = products.where((p) => p.isActive && p.stockQuantity > 0).toList(growable: false);
    if (active.isEmpty) return;
    final controllers = {for (final product in active) product.id: TextEditingController()};
    String reason = 'Sayım / Düzeltme';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Toplu Stok Düş • ${active.length} ürün'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: reason,
                    decoration: const InputDecoration(labelText: 'Sebep'),
                    items: const [
                      DropdownMenuItem(value: 'Sayım / Düzeltme', child: Text('Sayım / Düzeltme')),
                      DropdownMenuItem(value: 'Satış', child: Text('Satış')),
                      DropdownMenuItem(value: 'Kırık', child: Text('Kırık')),
                      DropdownMenuItem(value: 'Hurda', child: Text('Hurda')),
                      DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                    ],
                    onChanged: (value) { if (value != null) setDialogState(() => reason = value); },
                  ),
                  const SizedBox(height: 12),
                  ...active.map((product) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text('Mevcut: ${_compact(product.stockQuantity)} ${product.unit}', style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12)),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: TextField(
                                controller: controllers[product.id],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Düşülecek'),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
            FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.remove_circle_outline), label: const Text('Stokları Düş')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        final repository = ref.read(inventoryRepositoryProvider);
        final mainWarehouse = await repository.getMainWarehouse();
        var changed = 0;
        for (final product in active) {
          final quantity = _parseNumber(controllers[product.id]?.text ?? '') ?? 0;
          if (quantity <= 0) continue;
          if (quantity > product.stockQuantity) {
            throw StateError('${product.name}: düşülecek miktar mevcut stoktan fazla.');
          }
          await repository.removeStock(
            warehouseId: mainWarehouse.id,
            productId: product.id,
            quantity: quantity,
            reason: reason,
            notes: 'Ürünler ekranından toplu stok düzeltmesi',
          );
          changed++;
        }
        ref.invalidate(productsProvider);
        ref.invalidate(stockMovementsProvider);
        ref.invalidate(warehousesProvider);
        setState(_selectedIds.clear);
        if (mounted) _showMessage('$changed ürünün stoğu güncellendi.');
      } catch (error) {
        if (mounted) _showMessage('Toplu stok düşme tamamlanamadı: $error');
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _showCategoryManager(BuildContext context) async {
    await showDialog<void>(context: context, builder: (_) => const _CategoryManagerDialog());
    _refresh();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.width, required this.title, required this.value, required this.detail, required this.icon, required this.color});
  final double width;
  final String title, value, detail;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(radius: 24, backgroundColor: color.withOpacity(.14), child: Icon(icon, color: color)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title, style: const TextStyle(color: Color(0xFF91A4B7))),
                  Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  Text(detail, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                ])),
              ],
            ),
          ),
        ),
      );
}

class _DarkProductTable extends StatelessWidget {
  const _DarkProductTable({
    required this.products,
    required this.selectedIds,
    required this.onSelect,
    required this.onSelectAll,
    required this.onEdit,
    required this.onToggleActive,
    required this.onAddStock,
    required this.onRemoveStock,
    required this.onArchive,
  });
  final List<ProductItem> products;
  final Set<String> selectedIds;
  final void Function(ProductItem, bool) onSelect;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<ProductItem> onEdit, onToggleActive, onAddStock, onRemoveStock, onArchive;

  @override
  Widget build(BuildContext context) {
    final allSelected = products.isNotEmpty && products.every((p) => selectedIds.contains(p.id));
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF101F2C),
                  child: Row(
                    children: [
                      Checkbox(value: allSelected, onChanged: (v) => onSelectAll(v ?? false)),
                      const Expanded(child: Text('Tümünü seç', style: TextStyle(fontWeight: FontWeight.w800))),
                      Text('${products.length} ürün', style: const TextStyle(color: Color(0xFF91A4B7))),
                    ],
                  ),
                ),
                ...products.map((product) => _MobileProductCard(
                      product: product,
                      selected: selectedIds.contains(product.id),
                      onSelect: (value) => onSelect(product, value),
                      onEdit: () => onEdit(product),
                      onToggleActive: () => onToggleActive(product),
                      onAddStock: product.isActive ? () => onAddStock(product) : null,
                      onRemoveStock: product.isActive && product.stockQuantity > 0 ? () => onRemoveStock(product) : null,
                      onArchive: product.isActive ? () => onArchive(product) : null,
                    )),
              ],
            ),
          );
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: const Color(0xFF101F2C),
                child: Row(children: [
                  SizedBox(width: 42, child: Checkbox(value: allSelected, onChanged: (v) => onSelectAll(v ?? false))),
                  const Expanded(flex: 4, child: Text('Ürün', style: TextStyle(fontWeight: FontWeight.w800))),
                  const Expanded(flex: 2, child: Text('Kategori', style: TextStyle(fontWeight: FontWeight.w800))),
                  const Expanded(flex: 2, child: Text('Stok', style: TextStyle(fontWeight: FontWeight.w800))),
                  const Expanded(flex: 2, child: Text('Bakım', style: TextStyle(fontWeight: FontWeight.w800))),
                  const Expanded(flex: 2, child: Text('Durum', style: TextStyle(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 196, child: Text('İşlemler', style: TextStyle(fontWeight: FontWeight.w800))),
                ]),
              ),
              ...products.map((product) {
                final selected = selectedIds.contains(product.id);
                return Container(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF223241)))),
                  child: InkWell(
                    onTap: () => onEdit(product),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Row(children: [
                        SizedBox(width: 42, child: Checkbox(value: selected, onChanged: (v) => onSelect(product, v ?? false))),
                        Expanded(flex: 4, child: Row(children: [
                          Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFF12313C), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF22D3DC), size: 20)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w900))),
                        ])),
                        Expanded(flex: 2, child: Text(product.categoryName.isEmpty ? 'Kategorisiz' : product.categoryName)),
                        Expanded(
                          flex: 2,
                          child: Text(
                            product.isActive ? '${_compact(product.stockQuantity)} ${product.unit}' : '—',
                            style: TextStyle(fontWeight: FontWeight.w800, color: product.isActive ? null : const Color(0xFF6F8396)),
                          ),
                        ),
                        Expanded(flex: 2, child: Text(product.maintenanceLabel)),
                        Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _StatusBadge(active: product.isActive))),
                        SizedBox(width: 196, child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: 'Düzenle', onPressed: () => onEdit(product), icon: const Icon(Icons.edit_outlined, size: 19)),
                          IconButton(tooltip: 'Stok Ekle', onPressed: product.isActive ? () => onAddStock(product) : null, icon: const Icon(Icons.add_circle_outline, color: Color(0xFF35C978), size: 19)),
                          IconButton(tooltip: 'Stok Düş', onPressed: product.isActive && product.stockQuantity > 0 ? () => onRemoveStock(product) : null, icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFF4B740), size: 19)),
                          PopupMenuButton<String>(
                            tooltip: 'Diğer',
                            onSelected: (value) {
                              if (value == 'toggle') onToggleActive(product);
                              if (value == 'archive') onArchive(product);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'toggle', child: Text(product.isActive ? 'Pasife al' : 'Yeniden aktifleştir')),
                              if (product.isActive) const PopupMenuItem(value: 'archive', child: Text('Arşivle • geçmişi koru')),
                            ],
                          ),
                        ])),
                      ]),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _MobileProductCard extends StatelessWidget {
  const _MobileProductCard({
    required this.product,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onToggleActive,
    required this.onAddStock,
    required this.onRemoveStock,
    required this.onArchive,
  });

  final ProductItem product;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback? onAddStock;
  final VoidCallback? onRemoveStock;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF223241)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
              Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF12313C), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF22D3DC), size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(product.categoryName.isEmpty ? 'Kategorisiz' : product.categoryName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12)),
                  ],
                ),
              ),
              _StatusBadge(active: product.isActive),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProductInfoChip(label: 'Stok', value: product.isActive ? '${_compact(product.stockQuantity)} ${product.unit}' : '—'),
              _ProductInfoChip(label: 'Bakım', value: product.maintenanceLabel),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton.filledTonal(tooltip: 'Düzenle', onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
              IconButton.filledTonal(tooltip: 'Stok Ekle', onPressed: onAddStock, icon: const Icon(Icons.add_circle_outline, color: Color(0xFF35C978))),
              IconButton.filledTonal(tooltip: 'Stok Düş', onPressed: onRemoveStock, icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFF4B740))),
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                onSelected: (value) {
                  if (value == 'toggle') onToggleActive();
                  if (value == 'archive' && onArchive != null) onArchive!();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'toggle', child: Text(product.isActive ? 'Pasife al' : 'Yeniden aktifleştir')),
                  if (product.isActive) const PopupMenuItem(value: 'archive', child: Text('Arşivle • geçmişi koru')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductInfoChip extends StatelessWidget {
  const _ProductInfoChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xFF101F2C), borderRadius: BorderRadius.circular(9)),
        child: Text('$label: $value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF123B2B) : const Color(0xFF29223F),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(active ? 'Aktif' : 'Arşivde', style: TextStyle(color: active ? const Color(0xFF5DE6A1) : const Color(0xFFB9A7FF), fontWeight: FontWeight.w800)),
      );
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 70),
          child: Column(children: [
            Icon(Icons.inventory_2_outlined, size: 50, color: Color(0xFF22D3DC)),
            SizedBox(height: 12),
            Text('Ürün bulunamadı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text('Arama ve filtreleri değiştirin.'),
          ]),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ]),
        ),
      );
}

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({required this.categories, this.product});

  final List<ProductCategory> categories;
  final ProductItem? product;

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _initialStock;
  String? _categoryId;
  String _unit = 'adet';
  int _maintenanceMonths = 0;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _initialStock = TextEditingController(text: '0');
    _categoryId = product?.categoryId;
    _maintenanceMonths = product?.maintenanceMonths ?? 0;

    const allowedUnits = {'adet', 'takım', 'metre', 'kutu', 'paket'};
    final savedUnit = (product?.unit ?? 'adet').trim().toLowerCase();
    _unit = allowedUnits.contains(savedUnit) ? savedUnit : 'adet';
    _isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _initialStock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uniqueCategories = <String, ProductCategory>{};
    for (final category in widget.categories) {
      if (category.id.isNotEmpty) uniqueCategories[category.id] = category;
    }
    final categoryItems = uniqueCategories.values.toList(growable: false);
    final safeCategoryId = uniqueCategories.containsKey(_categoryId)
        ? _categoryId
        : null;
    final maintenanceOptions = <int>{
      0, 1, 3, 6, 8, 9, 12, 18, 24, _maintenanceMonths,
    }.toList()..sort();

    return AlertDialog(
      title: Text(widget.product == null ? 'Yeni Ürün' : 'Ürünü Düzenle'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Ürün adı *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: safeCategoryId ?? '__none__',
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '__none__',
                      child: Text('Kategorisiz'),
                    ),
                    ...categoryItems.map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _categoryId = value == '__none__' ? null : value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Birim',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'adet', child: Text('Adet')),
                          DropdownMenuItem(value: 'takım', child: Text('Takım')),
                          DropdownMenuItem(value: 'metre', child: Text('Metre')),
                          DropdownMenuItem(value: 'kutu', child: Text('Kutu')),
                          DropdownMenuItem(value: 'paket', child: Text('Paket')),
                        ],
                        onChanged: (value) => setState(() => _unit = value ?? 'adet'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _maintenanceMonths,
                        decoration: const InputDecoration(
                          labelText: 'Bakım süresi',
                          helperText: 'Son işlemden sonra sayaç başlar',
                          border: OutlineInputBorder(),
                        ),
                        items: maintenanceOptions
                            .map(
                              (months) => DropdownMenuItem<int>(
                                value: months,
                                child: Text(
                                  months == 0
                                      ? 'Bakım takibi yok'
                                      : '$months ay',
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) => setState(() => _maintenanceMonths = value ?? 0),
                      ),
                    ),
                  ],
                ),
                if (widget.product == null) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _initialStock,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç stoğu',
                      helperText: 'İsterseniz ürünü ilk stok miktarıyla kaydedin',
                      prefixIcon: Icon(Icons.add_box_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  title: const Text('Aktif ürün'),
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Kaydet'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final draft = ProductDraft(
        name: _name.text,
        categoryId: _categoryId,
        unit: _unit,
        maintenanceMonths: _maintenanceMonths,
        isActive: _isActive,
      );
      final productId = await ref.read(productRepositoryProvider).saveProduct(
        id: widget.product?.id,
        draft: draft,
      );

      if (widget.product == null) {
        final initialStock = _parseNumber(_initialStock.text) ?? 0;
        if (initialStock > 0) {
          final inventory = ref.read(inventoryRepositoryProvider);
          final mainWarehouse = await inventory.getMainWarehouse();
          await inventory.addStock(
            warehouseId: mainWarehouse.id,
            productId: productId,
            quantity: initialStock,
            notes: 'Yeni ürün başlangıç stoğu',
          );
          ref.invalidate(stockMovementsProvider);
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ürün kaydedilemedi: $error')),
        );
        setState(() => _saving = false);
      }
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Bu alan zorunludur.';
    return null;
  }
}

class _CategoryManagerDialog extends ConsumerWidget {
  const _CategoryManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(productCategoriesProvider);
    return AlertDialog(
      title: const Text('Ürün Kategorileri'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(productCategoriesProvider),
          ),
          data: (categories) => ListView.separated(
            itemCount: categories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final category = categories[index];
              return ListTile(
                title: Text(category.name),
                subtitle: Text(category.isActive ? 'Aktif' : 'Pasif'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Düzenle',
                      onPressed: () => _editCategory(context, ref, category),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: category.isActive ? 'Pasife al' : 'Aktifleştir',
                      onPressed: () async {
                        await ref
                            .read(productRepositoryProvider)
                            .setCategoryActive(category.id, !category.isActive);
                        ref.invalidate(productCategoriesProvider);
                      },
                      icon: Icon(
                        category.isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _editCategory(context, ref, null),
          icon: const Icon(Icons.add),
          label: const Text('Yeni Kategori'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    ProductCategory? category,
  ) async {
    final controller = TextEditingController(text: category?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(category == null ? 'Yeni Kategori' : 'Kategoriyi Düzenle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Kategori adı'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) {
      return;
    }
    await ref
        .read(productRepositoryProvider)
        .saveCategory(id: category?.id, name: name);
    ref.invalidate(productCategoriesProvider);
  }
}

double? _parseNumber(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return 0;
  }
  final normalized = text.contains(',')
      ? text.replaceAll('.', '').replaceAll(',', '.')
      : text;
  return double.tryParse(normalized);
}

String _compact(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceAll('.', ',');
}
