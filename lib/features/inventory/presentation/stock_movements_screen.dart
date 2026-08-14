import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/inventory_providers.dart';
import '../domain/inventory_models.dart';

class InventoryStockMovementsScreen extends ConsumerStatefulWidget {
  const InventoryStockMovementsScreen({super.key});

  @override
  ConsumerState<InventoryStockMovementsScreen> createState() =>
      _InventoryStockMovementsScreenState();
}

class _InventoryStockMovementsScreenState
    extends ConsumerState<InventoryStockMovementsScreen> {
  late DateTime _start;
  late DateTime _end;
  final _searchController = TextEditingController();
  String _movementType = 'all';
  String _technician = 'all';
  bool _loading = false;
  String? _error;
  List<StockMovementItem> _items = const [];
  final Set<String> _expandedProducts = <String>{};
  final Set<String> _expandedTechnicians = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 1);
    _searchController.addListener(() => setState(() {}));
    Future.microtask(_load);
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
      final items = await ref.read(inventoryRepositoryProvider).getMovements(
            start: _start,
            end: _end,
          );
      if (!mounted) return;
      setState(() {
        _items = items;
        final availableTechnicians = items
            .map((item) => item.displayTechnician)
            .where((name) => name != '—')
            .toSet();
        if (_technician != 'all' && !availableTechnicians.contains(_technician)) {
          _technician = 'all';
        }
        if (items.isNotEmpty) {
          _expandedProducts.add(items.first.productName);
          final technician = items.first.displayTechnician;
          if (technician != '—') _expandedTechnicians.add(technician);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _start = value);
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _end.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _end = value.add(const Duration(days: 1)));
  }

  List<String> get _technicians {
    final values = _items
        .map((item) => item.displayTechnician)
        .where((value) => value != '—' && value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<StockMovementItem> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery = query.isEmpty ||
          item.productName.toLowerCase().contains(query) ||
          item.warehouseName.toLowerCase().contains(query) ||
          item.displayTechnician.toLowerCase().contains(query) ||
          (item.customerName ?? '').toLowerCase().contains(query) ||
          (item.customerPhone ?? '').toLowerCase().contains(query) ||
          (item.notes ?? '').toLowerCase().contains(query);
      final matchesType = _movementType == 'all' ||
          (_movementType == 'in' && _isIncoming(item)) ||
          (_movementType == 'out' && _isOutgoing(item)) ||
          (_movementType == 'transfer' && item.type.contains('transfer')) ||
          (_movementType == 'adjustment' && item.type.contains('adjust'));
      final matchesTechnician =
          _technician == 'all' || item.displayTechnician == _technician;
      return matchesQuery && matchesType && matchesTechnician;
    }).toList(growable: false);
  }

  Map<String, List<StockMovementItem>> _groupByProduct(List<StockMovementItem> items) {
    final result = <String, List<StockMovementItem>>{};
    for (final item in items) {
      result.putIfAbsent(item.productName, () => <StockMovementItem>[]).add(item);
    }
    return result;
  }

  Map<String, List<StockMovementItem>> _groupByTechnician(List<StockMovementItem> items) {
    final result = <String, List<StockMovementItem>>{};
    for (final item in items) {
      final name = item.displayTechnician == '—' ? 'Diğer / Ana Depo' : item.displayTechnician;
      result.putIfAbsent(name, () => <StockMovementItem>[]).add(item);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final visible = _filteredItems;
    final productGroups = _groupByProduct(visible);
    final technicianGroups = _groupByTechnician(visible);
    final totalIn = _items.where(_isIncoming).fold<double>(0, (sum, item) => sum + item.quantity);
    final totalOut = _items.where(_isOutgoing).fold<double>(0, (sum, item) => sum + item.quantity);
    final transferCount = _items.where((item) => item.type.contains('transfer')).length;
    final adjustmentTotal = _items
        .where((item) => item.type.contains('adjust'))
        .fold<double>(0, (sum, item) => sum + (_isOutgoing(item) ? -item.quantity : item.quantity));

    return ManagementShell(
      role: role,
      title: 'Stok Hareketleri',
      subtitle: 'Tüm stok giriş, çıkış ve transfer hareketlerini takip edin.',
      actions: [
        IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: () => context.push('/manager/excel-transfer'),
          icon: const Icon(Icons.table_view_outlined),
          label: const Text("Excel'e Aktar"),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1180 ? 5 : constraints.maxWidth >= 760 ? 2 : 1;
              return GridView.count(
                crossAxisCount: count,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: count == 1 ? 3.2 : 2.4,
                children: [
                  _MovementMetric('Toplam Giriş', _quantity(totalIn), Icons.south_rounded, const Color(0xFF18A66A)),
                  _MovementMetric('Toplam Çıkış', _quantity(totalOut), Icons.north_rounded, const Color(0xFFE45151)),
                  _MovementMetric('Transfer', '$transferCount', Icons.swap_horiz_rounded, const Color(0xFF2F80ED)),
                  _MovementMetric('Sayım Farkı', _signedQuantity(adjustmentTotal), Icons.rule_folder_outlined, const Color(0xFFF5A623)),
                  _MovementMetric('Toplam Hareket', '${_items.length}', Icons.inventory_2_outlined, const Color(0xFF8B5CF6)),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _MovementFilters(
            searchController: _searchController,
            start: _start,
            end: _end,
            movementType: _movementType,
            technician: _technician,
            technicians: _technicians,
            onPickStart: _pickStart,
            onPickEnd: _pickEnd,
            onMovementChanged: (value) => setState(() => _movementType = value),
            onTechnicianChanged: (value) => setState(() => _technician = value),
            onApply: _loading ? null : _load,
            onClear: () {
              final now = DateTime.now();
              setState(() {
                _start = DateTime(now.year, now.month, 1);
                _end = DateTime(now.year, now.month + 1, 1);
                _movementType = 'all';
                _technician = 'all';
                _searchController.clear();
              });
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (_loading)
            const _LoadingPanel()
          else if (_error != null)
            _MessagePanel('Stok hareketleri yüklenemedi.\n$_error')
          else if (visible.isEmpty)
            const _MessagePanel('Seçilen filtrelerde stok hareketi yok.')
          else ...[
            _SectionCard(
              title: 'Ürünlere Göre Hareketler',
              icon: Icons.inventory_2_outlined,
              badge: 'Toplam ${visible.length} hareket',
              child: Column(
                children: productGroups.entries.map((entry) {
                  final expanded = _expandedProducts.contains(entry.key);
                  return _MovementGroup(
                    title: entry.key,
                    items: entry.value,
                    expanded: expanded,
                    productMode: true,
                    onToggle: () => setState(() {
                      if (expanded) {
                        _expandedProducts.remove(entry.key);
                      } else {
                        _expandedProducts.add(entry.key);
                      }
                    }),
                    onDelete: _deleteMovement,
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Teknikerlere Göre Hareketler',
              icon: Icons.person_outline_rounded,
              badge: 'Toplam ${visible.length} hareket',
              child: Column(
                children: technicianGroups.entries.map((entry) {
                  final expanded = _expandedTechnicians.contains(entry.key);
                  return _MovementGroup(
                    title: entry.key,
                    items: entry.value,
                    expanded: expanded,
                    productMode: false,
                    onToggle: () => setState(() {
                      if (expanded) {
                        _expandedTechnicians.remove(entry.key);
                      } else {
                        _expandedTechnicians.add(entry.key);
                      }
                    }),
                    onDelete: _deleteMovement,
                  );
                }).toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteMovement(StockMovementItem item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stok hareketini sil'),
        content: Text('${item.productName} hareketi tamamen silinsin mi? Stok miktarı buna göre geri alınır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sil')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await ref.read(inventoryRepositoryProvider).deleteMovement(item.id);
      await _load();
      ref.invalidate(warehousesProvider);
      ref.invalidate(stockMovementsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok hareketi silindi.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hareket silinemedi: $error')));
    }
  }

  static bool _isIncoming(StockMovementItem item) =>
      item.type == 'in' || item.type == 'transfer_in' || (item.type.contains('adjust') && !item.type.contains('out'));

  static bool _isOutgoing(StockMovementItem item) =>
      item.type == 'out' || item.type == 'service' || item.type == 'transfer_out';

  static String _quantity(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
  static String _signedQuantity(double value) => '${value > 0 ? '+' : ''}${_quantity(value)}';
}

class _MovementFilters extends StatelessWidget {
  const _MovementFilters({
    required this.searchController,
    required this.start,
    required this.end,
    required this.movementType,
    required this.technician,
    required this.technicians,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onMovementChanged,
    required this.onTechnicianChanged,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController searchController;
  final DateTime start;
  final DateTime end;
  final String movementType;
  final String technician;
  final List<String> technicians;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<String> onMovementChanged;
  final ValueChanged<String> onTechnicianChanged;
  final VoidCallback? onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ürün, depo veya tekniker ara...'),
            ),
          ),
          OutlinedButton.icon(onPressed: onPickStart, icon: const Icon(Icons.calendar_month_outlined), label: Text(DateFormat('dd.MM.yyyy').format(start))),
          OutlinedButton.icon(onPressed: onPickEnd, icon: const Icon(Icons.calendar_month_outlined), label: Text(DateFormat('dd.MM.yyyy').format(end.subtract(const Duration(days: 1))))),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: movementType,
              decoration: const InputDecoration(labelText: 'Hareket Türü'),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tümü')),
                DropdownMenuItem(value: 'in', child: Text('Giriş')),
                DropdownMenuItem(value: 'out', child: Text('Çıkış')),
                DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                DropdownMenuItem(value: 'adjustment', child: Text('Sayım Farkı')),
              ],
              onChanged: (value) => onMovementChanged(value ?? 'all'),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: technician,
              decoration: const InputDecoration(labelText: 'Tekniker'),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Tümü')),
                ...technicians.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (value) => onTechnicianChanged(value ?? 'all'),
            ),
          ),
          FilledButton.icon(onPressed: onApply, icon: const Icon(Icons.filter_alt_outlined), label: const Text('Filtrele')),
          OutlinedButton.icon(onPressed: onClear, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Temizle')),
        ],
      ),
    );
  }
}

class _MovementMetric extends StatelessWidget {
  const _MovementMetric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
        child: Row(children: [
          CircleAvatar(radius: 23, backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
          const SizedBox(width: 13),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Color(0xFF66758A))),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10243A))),
            const Text('adet', style: TextStyle(fontSize: 11, color: Color(0xFF718096))),
          ])),
        ]),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.badge, required this.child});
  final String title;
  final IconData icon;
  final String badge;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              CircleAvatar(radius: 18, backgroundColor: const Color(0xFFEAF2FF), child: Icon(icon, size: 19, color: const Color(0xFF2F80ED))),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF10243A)))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFF3FAF5), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFDDEEE3))), child: Text(badge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ),
          const Divider(height: 1),
          child,
        ]),
      );
}

class _MovementGroup extends StatelessWidget {
  const _MovementGroup({
    required this.title,
    required this.items,
    required this.expanded,
    required this.productMode,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final List<StockMovementItem> items;
  final bool expanded;
  final bool productMode;
  final VoidCallback onToggle;
  final ValueChanged<StockMovementItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final incoming = items.where(_InventoryStockMovementsScreenState._isIncoming).fold<double>(0, (sum, item) => sum + item.quantity);
    final outgoing = items.where(_InventoryStockMovementsScreenState._isOutgoing).fold<double>(0, (sum, item) => sum + item.quantity);
    final transfers = items.where((item) => item.type.contains('transfer')).length;
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              CircleAvatar(radius: 16, backgroundColor: const Color(0xFFEAF2FF), child: Icon(productMode ? Icons.inventory_2_outlined : Icons.person_outline, color: const Color(0xFF2F80ED), size: 17)),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14283D)))),
              _MiniStat(label: 'Giriş', value: _InventoryStockMovementsScreenState._quantity(incoming), color: const Color(0xFF18A66A)),
              const SizedBox(width: 16),
              _MiniStat(label: 'Çıkış', value: _InventoryStockMovementsScreenState._quantity(outgoing), color: const Color(0xFFE45151)),
              const SizedBox(width: 16),
              _MiniStat(label: 'Transfer', value: '$transfers', color: const Color(0xFF2F80ED)),
              const SizedBox(width: 16),
              _MiniStat(label: 'Hareket', value: '${items.length}', color: const Color(0xFF53657A)),
              const SizedBox(width: 8),
              Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
            ]),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1),
          productMode
              ? _ProductMovementTable(items: items, onDelete: onDelete)
              : _TechnicianMovementTable(items: items, onDelete: onDelete),
        ],
        const Divider(height: 1),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(fontSize: 11, color: Color(0xFF607287))),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
      ]);
}

class _ProductMovementTable extends StatelessWidget {
  const _ProductMovementTable({required this.items, required this.onDelete});
  final List<StockMovementItem> items;
  final ValueChanged<StockMovementItem> onDelete;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1180,
          child: Column(children: [
            const _TableHeader(labels: ['Tarih / Saat', 'Hareket Türü', 'Tekniker', 'Depo', 'Müşteri', 'Açıklama', 'Miktar']),
            ...items.map((item) => _MovementDataRow(item: item, productMode: true, onDelete: () => onDelete(item))),
          ]),
        ),
      );
}

class _TechnicianMovementTable extends StatelessWidget {
  const _TechnicianMovementTable({required this.items, required this.onDelete});
  final List<StockMovementItem> items;
  final ValueChanged<StockMovementItem> onDelete;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1180,
          child: Column(children: [
            const _TableHeader(labels: ['Tarih / Saat', 'Hareket Türü', 'Ürün', 'Müşteri', 'İşlem Türü', 'Depo', 'Miktar']),
            ...items.map((item) => _MovementDataRow(item: item, productMode: false, onDelete: () => onDelete(item))),
          ]),
        ),
      );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.labels});
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF8FAFC),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          for (final label in labels) Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF506278)))),
          const SizedBox(width: 42),
        ]),
      );
}

class _MovementDataRow extends StatelessWidget {
  const _MovementDataRow({required this.item, required this.productMode, required this.onDelete});
  final StockMovementItem item;
  final bool productMode;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final outgoing = _InventoryStockMovementsScreenState._isOutgoing(item);
    final color = _movementColor(item);
    final customer = (item.customerName?.trim().isNotEmpty ?? false) ? item.customerName! : '—';
    final customerText = (item.customerPhone?.trim().isNotEmpty ?? false) ? '$customer\n${item.customerPhone}' : customer;
    final cells = productMode
        ? <Widget>[
            Text(DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(item.createdAt.toLocal())),
            _MovementBadge(item: item),
            Text(item.displayTechnician),
            Text(item.warehouseName),
            Text(customerText),
            Text(item.notes?.trim().isNotEmpty == true ? item.notes! : (item.serviceType ?? '—')),
            Text('${outgoing ? '-' : '+'}${_InventoryStockMovementsScreenState._quantity(item.quantity)}', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ]
        : <Widget>[
            Text(DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(item.createdAt.toLocal())),
            _MovementBadge(item: item),
            Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(customerText),
            Text(item.serviceType?.trim().isNotEmpty == true ? item.serviceType! : (item.notes ?? '—')),
            Text(item.warehouseName),
            Text('${outgoing ? '-' : '+'}${_InventoryStockMovementsScreenState._quantity(item.quantity)}', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8EDF2)))),
      child: Row(children: [
        for (final cell in cells) Expanded(child: DefaultTextStyle(style: const TextStyle(fontSize: 12, color: Color(0xFF263A50)), child: cell)),
        SizedBox(width: 42, child: IconButton(tooltip: 'Hareketi sil', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 18))),
      ]),
    );
  }
}

class _MovementBadge extends StatelessWidget {
  const _MovementBadge({required this.item});
  final StockMovementItem item;
  @override
  Widget build(BuildContext context) {
    final color = _movementColor(item);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
        child: Text(_movementLabel(item), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

Color _movementColor(StockMovementItem item) {
  if (item.type.contains('transfer')) return const Color(0xFF2F80ED);
  if (item.type.contains('adjust')) return const Color(0xFFF5A623);
  return _InventoryStockMovementsScreenState._isOutgoing(item) ? const Color(0xFFE45151) : const Color(0xFF18A66A);
}

String _movementLabel(StockMovementItem item) {
  switch (item.type) {
    case 'in':
      return 'Giriş';
    case 'out':
      return 'Çıkış';
    case 'service':
      return 'Servis';
    case 'transfer_in':
      return 'Transfer Giriş';
    case 'transfer_out':
      return 'Transfer Çıkış';
    default:
      return item.type.contains('adjust') ? 'Sayım Farkı' : item.type;
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();
  @override
  Widget build(BuildContext context) => Container(
        height: 180,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
        child: const Center(child: CircularProgressIndicator()),
      );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(42),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}
