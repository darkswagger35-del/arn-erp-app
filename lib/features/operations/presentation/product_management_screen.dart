import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/operations_providers.dart';

class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _categories = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(operationsRepositoryProvider);
      final results = await Future.wait([
        repository.list('products', orderBy: 'name', ascending: true),
        repository.list('product_categories', orderBy: 'name', ascending: true),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0];
        _categories = results[1];
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Ürünler yüklenemedi. V1.2 SQL dosyasını çalıştırdığınızdan emin olun.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _products;
    return _products.where((row) {
      final values = [row['name'], row['sku'], row['barcode'], row['category']];
      return values.any(
        (value) => value?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();
  }

  String _money(dynamic value) => NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
  ).format((value as num?) ?? 0);

  Future<void> _openProductForm([Map<String, dynamic>? product]) async {
    final name = TextEditingController(
      text: product?['name']?.toString() ?? '',
    );
    final sku = TextEditingController(text: product?['sku']?.toString() ?? '');
    final barcode = TextEditingController(
      text: product?['barcode']?.toString() ?? '',
    );
    final unit = TextEditingController(
      text: product?['unit']?.toString() ?? 'adet',
    );
    final purchasePrice = TextEditingController(
      text: product?['purchase_price']?.toString() ?? '0',
    );
    final salePrice = TextEditingController(
      text: product?['sale_price']?.toString() ?? '0',
    );
    final criticalStock = TextEditingController(
      text: product?['critical_stock']?.toString() ?? '0',
    );
    String? categoryId = product?['category_id']?.toString();
    bool isActive = product?['is_active'] as bool? ?? true;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(product == null ? 'Yeni Ürün' : 'Ürünü Düzenle'),
          content: SizedBox(
            width: 620,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Ürün adı *',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Ürün adı zorunludur.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Kategorisiz'),
                        ),
                        ..._categories.map(
                          (row) => DropdownMenuItem<String?>(
                            value: row['id'].toString(),
                            child: Text(row['name']?.toString() ?? '-'),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => categoryId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: sku,
                            decoration: const InputDecoration(
                              labelText: 'Ürün kodu',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: barcode,
                            decoration: const InputDecoration(
                              labelText: 'Barkod',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: unit,
                            decoration: const InputDecoration(
                              labelText: 'Birim',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: criticalStock,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Kritik stok',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: purchasePrice,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Alış fiyatı (₺)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: salePrice,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Satış fiyatı (₺)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Aktif ürün'),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                    ),
                    if (product == null)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'İlk stok miktarını ürün kaydından sonra Stok Hareketleri ekranından gireceksiniz.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false)
                  Navigator.pop(dialogContext, true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final category = _categories
          .where((row) => row['id'].toString() == categoryId)
          .firstOrNull;
      final auth = ref.read(authControllerProvider);
      final values = <String, dynamic>{
        'company_id': auth.profile?.companyId,
        'name': name.text.trim(),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
        'barcode': barcode.text.trim().isEmpty ? null : barcode.text.trim(),
        'category_id': categoryId,
        'category': category?['name'],
        'unit': unit.text.trim().isEmpty ? 'adet' : unit.text.trim(),
        'purchase_price':
            double.tryParse(purchasePrice.text.replaceAll(',', '.')) ?? 0,
        'sale_price': double.tryParse(salePrice.text.replaceAll(',', '.')) ?? 0,
        'critical_stock':
            double.tryParse(criticalStock.text.replaceAll(',', '.')) ?? 0,
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      };
      try {
        final repository = ref.read(operationsRepositoryProvider);
        if (product == null) {
          await repository.insert('products', values);
        } else {
          await repository.update('products', product['id'].toString(), values);
        }
        await _load();
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ürün kaydedilemedi. Ürün kodu veya barkod başka bir üründe kullanılıyor olabilir.',
              ),
            ),
          );
      }
    }

    for (final controller in [
      name,
      sku,
      barcode,
      unit,
      purchasePrice,
      salePrice,
      criticalStock,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _openCategoryDialog() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Kategori'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Kategori adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().isNotEmpty),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        final companyId = ref.read(authControllerProvider).profile?.companyId;
        await ref.read(operationsRepositoryProvider).insert(
          'product_categories',
          {'company_id': companyId, 'name': controller.text.trim()},
        );
        await _load();
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Kategori kaydedilemedi. Aynı isimde kategori olabilir.',
              ),
            ),
          );
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = _filteredProducts;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin-dashboard'),
        ),
        title: const Text('Ürün Yönetimi'),
        actions: [
          TextButton.icon(
            onPressed: _openCategoryDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Kategori Ekle'),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductForm(),
        icon: const Icon(Icons.add),
        label: const Text('Ürün Ekle'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Ürün adı, kodu veya barkod ara',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: products.isEmpty
                      ? const Center(
                          child: Text(
                            'Henüz ürün yok. Ürünlerinizi kendiniz ekleyebilirsiniz.',
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: products.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final product = products[index];
                            final stock =
                                (product['stock_quantity'] as num?)
                                    ?.toDouble() ??
                                0;
                            final critical =
                                (product['critical_stock'] as num?)
                                    ?.toDouble() ??
                                0;
                            final lowStock = stock <= critical;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    lowStock
                                        ? Icons.warning_amber_rounded
                                        : Icons.inventory_2_outlined,
                                  ),
                                ),
                                title: Text(product['name']?.toString() ?? '-'),
                                subtitle: Text(
                                  [
                                    if ((product['category']?.toString() ?? '')
                                        .isNotEmpty)
                                      product['category'].toString(),
                                    'Stok: ${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 2)} ${product['unit'] ?? 'adet'}',
                                    'Satış: ${_money(product['sale_price'])}',
                                  ].join(' • '),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!((product['is_active'] as bool?) ??
                                        true))
                                      const Chip(label: Text('Pasif')),
                                    IconButton(
                                      tooltip: 'Düzenle',
                                      onPressed: () =>
                                          _openProductForm(product),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
