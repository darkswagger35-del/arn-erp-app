import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/inventory_providers.dart';
import '../domain/inventory_models.dart';

class WarehouseManagementScreen extends ConsumerStatefulWidget {
  const WarehouseManagementScreen({super.key});

  @override
  ConsumerState<WarehouseManagementScreen> createState() =>
      _WarehouseManagementScreenState();
}

class _WarehouseManagementScreenState
    extends ConsumerState<WarehouseManagementScreen> {
  String _query = '';
  String _type = 'all';
  late Future<_WarehouseDashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_WarehouseDashboardData> _load() async {
    final repo = ref.read(inventoryRepositoryProvider);
    final warehouses = await repo.getWarehouses();
    final stocks = <String, List<WarehouseStockItem>>{};
    for (final warehouse in warehouses) {
      stocks[warehouse.id] = await repo.getWarehouseStocks(warehouse.id);
    }
    return _WarehouseDashboardData(warehouses: warehouses, stocks: stocks);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
    ref.invalidate(warehousesProvider);
    ref.invalidate(stockMovementsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    return ManagementShell(
      role: role,
      title: 'Depolar',
      subtitle: 'Depolarınızı, stok durumlarını ve depo hareketlerini yönetin.',
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final data = await _future;
            if (!context.mounted) return;
            await _openTransfer(context, data.warehouses);
          },
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Ürün Transferi'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<_WarehouseDashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Depolar yüklenemedi.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final filtered = data.warehouses.where((warehouse) {
            final matchesQuery = warehouse.name
                .toLowerCase()
                .contains(_query.trim().toLowerCase());
            final matchesType = _type == 'all' || warehouse.type == _type;
            return matchesQuery && matchesType;
          }).toList();
          final totalStock = data.stocks.values
              .expand((items) => items)
              .fold<double>(0, (sum, item) => sum + item.quantity);
          final vehicleCount =
              data.warehouses.where((item) => item.type == 'vehicle').length;
          final stockedWarehouses = data.stocks.values
              .where((items) => items.any((item) => item.quantity > 0))
              .length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final count = width >= 1200 ? 4 : width >= 700 ? 2 : 1;
                  return GridView.count(
                    crossAxisCount: count,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: count == 1 ? 3.2 : 2.45,
                    children: [
                      _MetricCard(
                        label: 'Toplam Depo',
                        value: '${data.warehouses.length}',
                        detail: 'Aktif depolarınız',
                        icon: Icons.warehouse_outlined,
                        color: const Color(0xFF2F80ED),
                      ),
                      _MetricCard(
                        label: 'Toplam Stok Adedi',
                        value: _quantity(totalStock),
                        detail: 'Tüm depolardaki toplam',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFFF5A623),
                      ),
                      _MetricCard(
                        label: 'Araç Depoları',
                        value: '$vehicleCount',
                        detail: 'Teknisyen araç depoları',
                        icon: Icons.local_shipping_outlined,
                        color: const Color(0xFF8B5CF6),
                      ),
                      _MetricCard(
                        label: 'Stok Bulunan Depo',
                        value: '$stockedWarehouses',
                        detail: 'En az bir ürünü olan',
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF18A66A),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _FilterCard(
                query: _query,
                type: _type,
                onQueryChanged: (value) => setState(() => _query = value),
                onTypeChanged: (value) => setState(() => _type = value),
                onClear: () => setState(() {
                  _query = '';
                  _type = 'all';
                }),
              ),
              const SizedBox(height: 14),
              _Panel(
                title: 'Depolarım',
                badge: '${filtered.length}',
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(38),
                        child: Center(child: Text('Filtreye uygun depo bulunamadı.')),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 760) {
                            return Column(
                              children: filtered.map((warehouse) {
                                final stocks = data.stocks[warehouse.id] ?? const <WarehouseStockItem>[];
                                return _WarehouseMobileCard(
                                  warehouse: warehouse,
                                  stocks: stocks,
                                  onStockAdd: warehouse.type == 'main'
                                      ? () => _addStock(context, warehouse)
                                      : null,
                                  onView: () => _showWarehouseDetails(context, warehouse, stocks),
                                );
                              }).toList(growable: false),
                            );
                          }
                          return Column(
                            children: [
                              const _WarehouseHeader(),
                              ...filtered.map(
                                (warehouse) => _WarehouseRow(
                                  warehouse: warehouse,
                                  stocks: data.stocks[warehouse.id] ?? const [],
                                  onStockAdd: warehouse.type == 'main'
                                      ? () => _addStock(context, warehouse)
                                      : null,
                                  onView: () => _showWarehouseDetails(
                                    context,
                                    warehouse,
                                    data.stocks[warehouse.id] ?? const [],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showWarehouseDetails(
    BuildContext context,
    WarehouseItem warehouse,
    List<WarehouseStockItem> stocks,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(warehouse.name),
        content: SizedBox(
          width: 620,
          child: stocks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Bu depoda ürün bulunmuyor.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: stocks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = stocks[index];
                    return ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(item.productName),
                      trailing: Text(
                        '${_quantity(item.quantity)} ${item.unit}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTransfer(
    BuildContext context,
    List<WarehouseItem> warehouses,
  ) async {
    if (warehouses.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer için en az iki depo gerekir.')),
      );
      return;
    }
    final products = await ref.read(inventoryRepositoryProvider).getProducts();
    if (!context.mounted || products.isEmpty) return;

    String source = warehouses
        .firstWhere((w) => w.type == 'main', orElse: () => warehouses.first)
        .id;
    String destination = warehouses.firstWhere((w) => w.id != source).id;
    String productId = products.first['id'].toString();
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Depolar Arası Transfer'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'Kaynak depo'),
                    items: warehouses
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() {
                      source = value!;
                      if (destination == source) {
                        destination = warehouses.firstWhere((w) => w.id != source).id;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: destination,
                    decoration: const InputDecoration(labelText: 'Hedef depo'),
                    items: warehouses
                        .where((w) => w.id != source)
                        .map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => destination = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Ürün'),
                    items: products
                        .map((product) => DropdownMenuItem(
                              value: product['id'].toString(),
                              child: Text(product['name']?.toString() ?? '-'),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => productId = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Miktar'),
                    validator: (value) {
                      final number = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return number == null || number <= 0
                          ? 'Geçerli miktar girin.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (isteğe bağlı)',
                    ),
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
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Transfer Et'),
            ),
          ],
        ),
      ),
    );

    if (save == true) {
      try {
        await ref.read(inventoryRepositoryProvider).transfer(
              productId: productId,
              sourceWarehouseId: source,
              destinationWarehouseId: destination,
              quantity: double.parse(quantity.text.replaceAll(',', '.')),
              notes: notes.text,
            );
        _reload();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer tamamlandı.')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Transfer yapılamadı: $error')),
          );
        }
      }
    }
    quantity.dispose();
    notes.dispose();
  }

  Future<void> _addStock(
    BuildContext context,
    WarehouseItem warehouse,
  ) async {
    final products = await ref.read(inventoryRepositoryProvider).getProducts();
    if (!context.mounted || products.isEmpty) return;
    String productId = products.first['id'].toString();
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${warehouse.name} - Stok Girişi'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Ürün'),
                    items: products
                        .map((product) => DropdownMenuItem(
                              value: product['id'].toString(),
                              child: Text(product['name']?.toString() ?? '-'),
                            ))
                        .toList(),
                    onChanged: (value) => setState(() => productId = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: quantity,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Miktar'),
                    validator: (value) {
                      final number = double.tryParse(
                        (value ?? '').replaceAll(',', '.'),
                      );
                      return number == null || number <= 0
                          ? 'Geçerli miktar girin.'
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
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await ref.read(inventoryRepositoryProvider).addStock(
            warehouseId: warehouse.id,
            productId: productId,
            quantity: double.parse(quantity.text.replaceAll(',', '.')),
            notes: notes.text,
          );
      _reload();
    }
    quantity.dispose();
    notes.dispose();
  }

  static String _quantity(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
}

class _WarehouseDashboardData {
  const _WarehouseDashboardData({
    required this.warehouses,
    required this.stocks,
  });

  final List<WarehouseItem> warehouses;
  final Map<String, List<WarehouseStockItem>> stocks;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF66758A))),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0B1F35),
                  ),
                ),
                Text(detail, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.query,
    required this.type,
    required this.onQueryChanged,
    required this.onTypeChanged,
    required this.onClear,
  });

  final String query;
  final String type;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 430,
            child: TextFormField(
              initialValue: query,
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Depo adı ile ara...',
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Depo Türü'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tümü')),
                DropdownMenuItem(value: 'main', child: Text('Ana Depo')),
                DropdownMenuItem(value: 'vehicle', child: Text('Araç Deposu')),
              ],
              onChanged: (value) => onTypeChanged(value ?? 'all'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.badge, required this.child});

  final String title;
  final String badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F6F8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(badge),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

class _WarehouseMobileCard extends StatelessWidget {
  const _WarehouseMobileCard({
    required this.warehouse,
    required this.stocks,
    required this.onView,
    this.onStockAdd,
  });

  final WarehouseItem warehouse;
  final List<WarehouseStockItem> stocks;
  final VoidCallback onView;
  final VoidCallback? onStockAdd;

  @override
  Widget build(BuildContext context) {
    final total = stocks.fold<double>(0, (sum, item) => sum + item.quantity);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE9EEF4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE7F7F8),
                child: Icon(
                  warehouse.type == 'main' ? Icons.warehouse_outlined : Icons.local_shipping_outlined,
                  color: const Color(0xFF0BA6B5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(warehouse.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(warehouse.type == 'main' ? 'Ana Depo' : 'Araç Deposu', style: const TextStyle(color: Color(0xFF718096))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: const Color(0xFFE3F6EB), borderRadius: BorderRadius.circular(999)),
                child: const Text('Aktif', style: TextStyle(color: Color(0xFF168650), fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MobileWarehouseInfo(label: 'Sorumlu', value: warehouse.technicianName ?? 'Yönetici'),
              _MobileWarehouseInfo(label: 'Stok', value: _WarehouseManagementScreenState._quantity(total)),
              _MobileWarehouseInfo(label: 'Ürün', value: '${stocks.length} çeşit'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: onView, icon: const Icon(Icons.visibility_outlined), label: const Text('Detay'))),
              if (onStockAdd != null) ...[
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(onPressed: onStockAdd, icon: const Icon(Icons.add_rounded), label: const Text('Stok Ekle'))),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileWarehouseInfo extends StatelessWidget {
  const _MobileWarehouseInfo({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF4F8FB), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );
}

class _WarehouseHeader extends StatelessWidget {
  const _WarehouseHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Depo Adı')),
          Expanded(flex: 2, child: Text('Tür')),
          Expanded(flex: 2, child: Text('Sorumlu')),
          Expanded(flex: 2, child: Text('Stok Adedi')),
          Expanded(flex: 2, child: Text('Ürün Çeşidi')),
          Expanded(flex: 2, child: Text('Durum')),
          SizedBox(width: 112, child: Text('İşlemler')),
        ],
      ),
    );
  }
}

class _WarehouseRow extends StatelessWidget {
  const _WarehouseRow({
    required this.warehouse,
    required this.stocks,
    required this.onView,
    this.onStockAdd,
  });

  final WarehouseItem warehouse;
  final List<WarehouseStockItem> stocks;
  final VoidCallback onView;
  final VoidCallback? onStockAdd;

  @override
  Widget build(BuildContext context) {
    final total = stocks.fold<double>(0, (sum, item) => sum + item.quantity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE9EEF4))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE7F7F8),
                  child: Icon(
                    warehouse.type == 'main'
                        ? Icons.warehouse_outlined
                        : Icons.local_shipping_outlined,
                    color: const Color(0xFF0BA6B5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    warehouse.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(warehouse.type == 'main' ? 'Ana Depo' : 'Araç Deposu'),
          ),
          Expanded(
            flex: 2,
            child: Text(warehouse.technicianName ?? 'Yönetici'),
          ),
          Expanded(flex: 2, child: Text(_WarehouseManagementScreenState._quantity(total))),
          Expanded(flex: 2, child: Text('${stocks.length} ürün')),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F6EB),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Aktif',
                  style: TextStyle(
                    color: Color(0xFF148A51),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 112,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Depoyu görüntüle',
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined),
                ),
                if (onStockAdd != null)
                  IconButton(
                    tooltip: 'Stok ekle',
                    onPressed: onStockAdd,
                    icon: const Icon(Icons.add_box_outlined),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
