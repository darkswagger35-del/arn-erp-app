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
  final Set<String> _expandedWarehouses = <String>{};
  bool _showAllMainProducts = false;
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
        FilledButton.tonalIcon(
          onPressed: () async {
            final data = await _future;
            if (!context.mounted) return;
            await _openTransfer(context, data.warehouses);
          },
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Ürün Transferi'),
        ),
        const SizedBox(width: 8),
        IconButton(tooltip: 'Yenile', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
      ],
      child: FutureBuilder<_WarehouseDashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Depolar yüklenemedi.\n${snapshot.error}', textAlign: TextAlign.center)));
          }

          final data = snapshot.data!;
          final mainWarehouses = data.warehouses.where((w) => w.type == 'main').toList(growable: false);
          final mainWarehouse = mainWarehouses.isEmpty ? null : mainWarehouses.first;
          final vehicleWarehouses = data.warehouses.where((w) => w.type == 'vehicle').toList(growable: false);
          final query = _query.trim().toLowerCase();
          final filteredVehicles = vehicleWarehouses.where((warehouse) {
            if (_type != 'all' && _type != 'vehicle') return false;
            if (query.isEmpty) return true;
            final stocks = data.stocks[warehouse.id] ?? const <WarehouseStockItem>[];
            return warehouse.name.toLowerCase().contains(query) ||
                (warehouse.technicianName ?? '').toLowerCase().contains(query) ||
                stocks.any((item) => item.productName.toLowerCase().contains(query));
          }).toList(growable: false);

          final mainStocks = mainWarehouse == null ? const <WarehouseStockItem>[] : (data.stocks[mainWarehouse.id] ?? const <WarehouseStockItem>[]);
          final mainStockTotal = mainStocks.fold<double>(0, (sum, item) => sum + item.quantity);
          final vehicleStockTotal = vehicleWarehouses
              .expand((w) => data.stocks[w.id] ?? const <WarehouseStockItem>[])
              .fold<double>(0, (sum, item) => sum + item.quantity);
          final stockedVehicleCount = vehicleWarehouses.where((w) => (data.stocks[w.id] ?? const <WarehouseStockItem>[]).any((i) => i.quantity > 0)).length;
          final emptyVehicleCount = vehicleWarehouses.length - stockedVehicleCount;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.maxWidth >= 1120 ? 4 : constraints.maxWidth >= 700 ? 2 : 1;
                  return GridView.count(
                    crossAxisCount: count,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: count == 1 ? 3.4 : 2.55,
                    children: [
                      _MetricCard(label: 'Ana Depo Stoku', value: _quantity(mainStockTotal), detail: '${mainStocks.length} ürün', icon: Icons.warehouse_outlined, color: const Color(0xFF12A7B5)),
                      _MetricCard(label: 'Araçlardaki Toplam Stok', value: _quantity(vehicleStockTotal), detail: '${vehicleWarehouses.length} araç', icon: Icons.local_shipping_outlined, color: const Color(0xFFF59A23)),
                      _MetricCard(label: 'Aktif Araç Deposu', value: '$stockedVehicleCount', detail: 'Stok bulunan araç', icon: Icons.local_shipping_rounded, color: const Color(0xFF8B5CF6)),
                      _MetricCard(label: 'Stoksuz Araç', value: '$emptyVehicleCount', detail: 'Stok bulunmayan araç', icon: Icons.remove_circle_outline, color: const Color(0xFFE65353)),
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
                onClear: () => setState(() { _query = ''; _type = 'all'; }),
              ),
              const SizedBox(height: 14),
              if (mainWarehouse != null && (_type == 'all' || _type == 'main'))
                _MainWarehouseCard(
                  warehouse: mainWarehouse,
                  stocks: mainStocks,
                  showAll: _showAllMainProducts,
                  onToggleAll: () => setState(() => _showAllMainProducts = !_showAllMainProducts),
                  onAddStock: () => _addStock(context, mainWarehouse),
                ),
              if (mainWarehouse != null && (_type == 'all' || _type == 'main')) const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Tekniker Araç Depoları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF10243A))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFEFF3F7), borderRadius: BorderRadius.circular(999)),
                    child: Text('${filteredVehicles.length} araç'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: filteredVehicles.isEmpty ? null : () => setState(() {
                      final allOpen = filteredVehicles.every((w) => _expandedWarehouses.contains(w.id));
                      if (allOpen) {
                        _expandedWarehouses.removeAll(filteredVehicles.map((w) => w.id));
                      } else {
                        _expandedWarehouses.addAll(filteredVehicles.map((w) => w.id));
                      }
                    }),
                    icon: const Icon(Icons.unfold_more_rounded),
                    label: const Text('Tümünü Aç / Kapat'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (filteredVehicles.isEmpty)
                const _WarehouseEmpty()
              else
                ...filteredVehicles.map((warehouse) {
                  final stocks = data.stocks[warehouse.id] ?? const <WarehouseStockItem>[];
                  final expanded = _expandedWarehouses.contains(warehouse.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _VehicleWarehouseAccordion(
                      warehouse: warehouse,
                      stocks: stocks,
                      expanded: expanded,
                      onToggle: () => setState(() {
                        if (expanded) {
                          _expandedWarehouses.remove(warehouse.id);
                        } else {
                          _expandedWarehouses.add(warehouse.id);
                        }
                      }),
                      onAddStock: () => _addStock(context, warehouse),
                      onReturnToMain: mainWarehouse == null ? null : () => _openTransfer(context, data.warehouses, sourceWarehouseId: warehouse.id, destinationWarehouseId: mainWarehouse.id),
                      onTransferToVehicle: () => _openTransfer(context, data.warehouses, sourceWarehouseId: warehouse.id, vehicleDestinationsOnly: true),
                    ),
                  );
                }),
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
    List<WarehouseItem> warehouses, {
    String? sourceWarehouseId,
    String? destinationWarehouseId,
    bool vehicleDestinationsOnly = false,
  }) async {
    if (warehouses.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer için en az iki depo gerekir.')),
      );
      return;
    }
    final products = await ref.read(inventoryRepositoryProvider).getProducts();
    if (!context.mounted || products.isEmpty) return;

    String source = sourceWarehouseId ?? warehouses
        .firstWhere((w) => w.type == 'main', orElse: () => warehouses.first)
        .id;
    final destinationCandidates = warehouses.where((w) => w.id != source && (!vehicleDestinationsOnly || w.type == 'vehicle')).toList(growable: false);
    if (destinationCandidates.isEmpty) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uygun hedef depo bulunamadı.')));
      return;
    }
    String destination = destinationWarehouseId != null && destinationCandidates.any((w) => w.id == destinationWarehouseId)
        ? destinationWarehouseId
        : destinationCandidates.first.id;
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
                      final candidates = warehouses.where((w) => w.id != source && (!vehicleDestinationsOnly || w.type == 'vehicle')).toList(growable: false);
                      if (candidates.isNotEmpty && !candidates.any((w) => w.id == destination)) {
                        destination = candidates.first.id;
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: destination,
                    decoration: const InputDecoration(labelText: 'Hedef depo'),
                    items: warehouses
                        .where((w) => w.id != source && (!vehicleDestinationsOnly || w.type == 'vehicle'))
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
                hintText: 'Tekniker veya ürün ara...',
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

class _MainWarehouseCard extends StatelessWidget {
  const _MainWarehouseCard({
    required this.warehouse,
    required this.stocks,
    required this.showAll,
    required this.onToggleAll,
    required this.onAddStock,
  });

  final WarehouseItem warehouse;
  final List<WarehouseStockItem> stocks;
  final bool showAll;
  final VoidCallback onToggleAll;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final total = stocks.fold<double>(0, (sum, item) => sum + item.quantity);
    final visible = showAll ? stocks : stocks.take(4).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Color(0xFFE7F7F8), child: Icon(Icons.warehouse_outlined, color: Color(0xFF0BA6B5))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(warehouse.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF10243A))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFE3F6EB), borderRadius: BorderRadius.circular(999)),
                          child: const Text('Merkez', style: TextStyle(color: Color(0xFF168650), fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text('${_WarehouseManagementScreenState._quantity(total)} adet  •  ${stocks.length} ürün', style: const TextStyle(color: Color(0xFF5E7085))),
                    ],
                  ),
                ),
                OutlinedButton.icon(onPressed: onToggleAll, icon: Icon(showAll ? Icons.expand_less : Icons.arrow_forward), label: Text(showAll ? 'Daralt' : 'Tümünü Gör')),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 130, child: Text('Öne Çıkan Ürünler', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF42556A)))),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...visible.map((item) => Container(
                                constraints: const BoxConstraints(minWidth: 155),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(color: const Color(0xFFF9FBFD), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5EBF1))),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF2F80ED)),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text('${item.productName}  ${_WarehouseManagementScreenState._quantity(item.quantity)} adet', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                                ]),
                              )),
                          if (!showAll && stocks.length > visible.length)
                            TextButton(onPressed: onToggleAll, child: Text('+ ${stocks.length - visible.length} ürün daha')),
                        ],
                      ),
                    ),
                  ],
                ),
                if (showAll) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: onAddStock, icon: const Icon(Icons.add_rounded), label: const Text('Ana Depoya Stok Ekle'))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleWarehouseAccordion extends StatelessWidget {
  const _VehicleWarehouseAccordion({
    required this.warehouse,
    required this.stocks,
    required this.expanded,
    required this.onToggle,
    required this.onAddStock,
    required this.onReturnToMain,
    required this.onTransferToVehicle,
  });

  final WarehouseItem warehouse;
  final List<WarehouseStockItem> stocks;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAddStock;
  final VoidCallback? onReturnToMain;
  final VoidCallback onTransferToVehicle;

  @override
  Widget build(BuildContext context) {
    final total = stocks.fold<double>(0, (sum, item) => sum + item.quantity);
    final displayName = (warehouse.technicianName?.trim().isNotEmpty ?? false) ? warehouse.technicianName! : warehouse.name.replaceAll(' Araç Deposu', '');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: expanded ? const Color(0xFF13B8C6) : const Color(0xFFE1E8F0), width: expanded ? 1.4 : 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Color(0xFFE7F7F8), child: Icon(Icons.local_shipping_outlined, color: Color(0xFF0BA6B5))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(child: Text(displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF10243A)))),
                          const SizedBox(width: 8),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE3F6EB), borderRadius: BorderRadius.circular(999)), child: const Text('Aktif', style: TextStyle(color: Color(0xFF168650), fontSize: 11, fontWeight: FontWeight.w800))),
                        ]),
                        const SizedBox(height: 2),
                        Text(stocks.isEmpty ? 'Araçta stok yok' : '${_WarehouseManagementScreenState._quantity(total)} adet  •  ${stocks.length} ürün', style: const TextStyle(color: Color(0xFF607287))),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: const Color(0xFF42566C)),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (stocks.isEmpty)
              const Padding(padding: EdgeInsets.all(22), child: Align(alignment: Alignment.centerLeft, child: Text('Bu araç deposunda ürün bulunmuyor.', style: TextStyle(color: Color(0xFF718196)))))
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Row(children: [
                        Expanded(flex: 4, child: Text('Ürün', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF52657A)))),
                        Expanded(flex: 2, child: Text('Stok Adedi', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF52657A)))),
                      ]),
                    ),
                    ...stocks.map((item) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE7EDF3)))),
                          child: Row(children: [
                            Expanded(flex: 4, child: Row(children: [
                              const Icon(Icons.inventory_2_outlined, color: Color(0xFF2F80ED), size: 19),
                              const SizedBox(width: 10),
                              Expanded(child: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w800))),
                            ])),
                            Expanded(flex: 2, child: Text('${_WarehouseManagementScreenState._quantity(item.quantity)} ${item.unit}', style: const TextStyle(fontWeight: FontWeight.w800))),
                          ]),
                        )),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: onAddStock, icon: const Icon(Icons.add_rounded), label: const Text('Stok Ekle')),
                  OutlinedButton.icon(onPressed: onReturnToMain, icon: const Icon(Icons.inventory_2_outlined), label: const Text('Ana Depoya İade')),
                  OutlinedButton.icon(onPressed: onTransferToVehicle, icon: const Icon(Icons.swap_horiz_rounded), label: const Text('Başka Araca Transfer')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WarehouseEmpty extends StatelessWidget {
  const _WarehouseEmpty();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE1E8F0))),
        child: const Center(child: Text('Aramaya uygun araç deposu bulunamadı.')),
      );
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
