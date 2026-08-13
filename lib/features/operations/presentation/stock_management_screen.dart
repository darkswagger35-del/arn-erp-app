import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/operations_providers.dart';

class StockManagementScreen extends ConsumerStatefulWidget {
  const StockManagementScreen({super.key});

  @override
  ConsumerState<StockManagementScreen> createState() =>
      _StockManagementScreenState();
}

class _StockManagementScreenState extends ConsumerState<StockManagementScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _warehouses = const [];
  List<Map<String, dynamic>> _movements = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
        repository.list('warehouses', orderBy: 'name', ascending: true),
        repository.list('stock_movements'),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0];
        _warehouses = results[1];
        _movements = results[2];
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Stok bilgileri yüklenemedi. V1.2 SQL dosyasını çalıştırın.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _productName(String? id) =>
      _products
          .where((row) => row['id'].toString() == id)
          .firstOrNull?['name']
          ?.toString() ??
      'Ürün';
  String _warehouseName(String? id) =>
      _warehouses
          .where((row) => row['id'].toString() == id)
          .firstOrNull?['name']
          ?.toString() ??
      'Genel stok';

  String _movementLabel(String value) {
    switch (value) {
      case 'in':
        return 'Stok Girişi';
      case 'out':
        return 'Stok Çıkışı';
      case 'service':
        return 'Serviste Kullanım';
      case 'adjustment':
        return 'Sayım Düzeltmesi';
      default:
        return value;
    }
  }

  Future<void> _openMovementDialog() async {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce en az bir ürün ekleyin.')),
      );
      return;
    }
    String? productId = _products.first['id']?.toString();
    String? warehouseId = _warehouses.isEmpty
        ? null
        : _warehouses.first['id']?.toString();
    String movementType = 'in';
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Stok Hareketi'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Ürün *'),
                    items: _products
                        .map(
                          (row) => DropdownMenuItem(
                            value: row['id'].toString(),
                            child: Text(row['name']?.toString() ?? '-'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => productId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: warehouseId,
                    decoration: const InputDecoration(labelText: 'Depo'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Genel stok'),
                      ),
                      ..._warehouses.map(
                        (row) => DropdownMenuItem<String?>(
                          value: row['id'].toString(),
                          child: Text(row['name']?.toString() ?? '-'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => warehouseId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: movementType,
                    decoration: const InputDecoration(
                      labelText: 'Hareket türü *',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'in', child: Text('Stok Girişi')),
                      DropdownMenuItem(
                        value: 'out',
                        child: Text('Stok Çıkışı'),
                      ),
                      DropdownMenuItem(
                        value: 'adjustment',
                        child: Text('Sayım Düzeltmesi (+)'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => movementType = value ?? 'in'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Miktar *'),
                    validator: (value) {
                      final parsed = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return parsed == null || parsed <= 0
                          ? 'Sıfırdan büyük miktar girin.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Açıklama'),
                  ),
                ],
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
      try {
        final auth = ref.read(authControllerProvider);
        await ref.read(operationsRepositoryProvider).insert('stock_movements', {
          'company_id': auth.profile?.companyId,
          'product_id': productId,
          'warehouse_id': warehouseId,
          'movement_type': movementType,
          'quantity': double.parse(quantity.text.replaceAll(',', '.')),
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          'created_by': auth.profile?.id,
        });
        await _load();
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Stok hareketi kaydedilemedi. Çıkış miktarı mevcut stoktan fazla olabilir.',
              ),
            ),
          );
      }
    }
    quantity.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin-dashboard'),
        ),
        title: const Text('Stok Yönetimi'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openMovementDialog,
        icon: const Icon(Icons.add),
        label: const Text('Stok Hareketi'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Güncel Stoklar',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_products.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Henüz ürün bulunmuyor. Önce Ürünler ekranından ürünlerinizi girin.',
                      ),
                    ),
                  )
                else
                  ..._products.map((product) {
                    final stock =
                        (product['stock_quantity'] as num?)?.toDouble() ?? 0;
                    final critical =
                        (product['critical_stock'] as num?)?.toDouble() ?? 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          stock <= critical
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_2_outlined,
                        ),
                        title: Text(product['name']?.toString() ?? '-'),
                        subtitle: Text(
                          'Kritik seviye: ${critical.toStringAsFixed(critical.truncateToDouble() == critical ? 0 : 2)}',
                        ),
                        trailing: Text(
                          '${stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 2)} ${product['unit'] ?? 'adet'}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
                Text(
                  'Son Hareketler',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_movements.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Henüz stok hareketi yok.'),
                    ),
                  )
                else
                  ..._movements.take(100).map((movement) {
                    final type = movement['movement_type']?.toString() ?? '';
                    final isOut = type == 'out' || type == 'service';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(isOut ? Icons.remove : Icons.add),
                        ),
                        title: Text(
                          _productName(movement['product_id']?.toString()),
                        ),
                        subtitle: Text(
                          '${_movementLabel(type)} • ${_warehouseName(movement['warehouse_id']?.toString())}${movement['notes'] == null ? '' : ' • ${movement['notes']}'}',
                        ),
                        trailing: Text(
                          '${isOut ? '-' : '+'}${movement['quantity']}',
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
