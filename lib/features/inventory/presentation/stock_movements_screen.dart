import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String _movementType = 'all';
  String _query = '';
  bool _loading = false;
  String? _error;
  List<StockMovementItem> _items = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 1);
    Future.microtask(_load);
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
      setState(() => _items = items);
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

  List<StockMovementItem> get _filteredItems {
    final query = _query.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery = query.isEmpty ||
          item.productName.toLowerCase().contains(query) ||
          item.warehouseName.toLowerCase().contains(query) ||
          (item.notes ?? '').toLowerCase().contains(query);
      final matchesType = _movementType == 'all' ||
          (_movementType == 'in' && item.type == 'in') ||
          (_movementType == 'out' &&
              {'out', 'service'}.contains(item.type)) ||
          (_movementType == 'transfer' && item.type.contains('transfer')) ||
          (_movementType == 'adjustment' && item.type.contains('adjust'));
      return matchesQuery && matchesType;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final visible = _filteredItems;
    final totalIn = _items
        .where((item) => item.type == 'in' || item.type == 'transfer_in')
        .fold<double>(0, (sum, item) => sum + item.quantity);
    final totalOut = _items
        .where((item) =>
            item.type == 'out' ||
            item.type == 'service' ||
            item.type == 'transfer_out')
        .fold<double>(0, (sum, item) => sum + item.quantity);
    final transferCount = _items.where((item) => item.type.contains('transfer')).length;
    final adjustmentCount = _items.where((item) => item.type.contains('adjust')).length;

    return ManagementShell(
      role: role,
      title: 'Stok Hareketleri',
      subtitle: 'Tüm stok giriş, çıkış ve transfer hareketlerini takip edin.',
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1200
                  ? 5
                  : constraints.maxWidth >= 750
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: count,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: count == 1 ? 3.2 : 2.35,
                children: [
                  _MovementMetric('Toplam Giriş', _quantity(totalIn), Icons.south_rounded,
                      const Color(0xFF18A66A)),
                  _MovementMetric('Toplam Çıkış', _quantity(totalOut), Icons.north_rounded,
                      const Color(0xFFE45151)),
                  _MovementMetric('Transfer', '$transferCount', Icons.swap_horiz_rounded,
                      const Color(0xFF2F80ED)),
                  _MovementMetric('Sayım Farkı', '$adjustmentCount', Icons.rule_folder_outlined,
                      const Color(0xFFF5A623)),
                  _MovementMetric('Toplam Hareket', '${_items.length}',
                      Icons.inventory_2_outlined, const Color(0xFF8B5CF6)),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
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
                  width: MediaQuery.sizeOf(context).width < 600 ? (MediaQuery.sizeOf(context).width - 64).clamp(220.0, 350.0) : 350,
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Ürün, depo veya açıklama ara...',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(DateFormat('dd.MM.yyyy').format(_start)),
                ),
                OutlinedButton.icon(
                  onPressed: _pickEnd,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    DateFormat('dd.MM.yyyy')
                        .format(_end.subtract(const Duration(days: 1))),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _movementType,
                    decoration: const InputDecoration(labelText: 'Hareket Türü'),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tümü')),
                      DropdownMenuItem(value: 'in', child: Text('Giriş')),
                      DropdownMenuItem(value: 'out', child: Text('Çıkış')),
                      DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                      DropdownMenuItem(value: 'adjustment', child: Text('Sayım Farkı')),
                    ],
                    onChanged: (value) =>
                        setState(() => _movementType = value ?? 'all'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('Filtrele'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final now = DateTime.now();
                    setState(() {
                      _start = DateTime(now.year, now.month, 1);
                      _end = DateTime(now.year, now.month + 1, 1);
                      _movementType = 'all';
                      _query = '';
                    });
                    _load();
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Temizle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E8F0)),
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text('Stok hareketleri yüklenemedi.\n$_error'),
                        ),
                      )
                    : visible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(
                              child: Text('Seçilen filtrelerde stok hareketi yok.'),
                            ),
                          )
                        : Column(
                            children: [
                              const _MovementHeader(),
                              ...visible.map(
                                (item) => _MovementRow(
                                  item: item,
                                  onDelete: () => _deleteMovement(item),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('Toplam ${visible.length} kayıt'),
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMovement(StockMovementItem item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stok hareketini sil'),
        content: Text(
          '${item.productName} hareketi tamamen silinsin mi? Stok miktarı buna göre geri alınır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await ref.read(inventoryRepositoryProvider).deleteMovement(item.id);
      await _load();
      ref.invalidate(warehousesProvider);
      ref.invalidate(stockMovementsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stok hareketi silindi.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hareket silinemedi: $error')),
        );
      }
    }
  }

  static String _quantity(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 2);
}

class _MovementMetric extends StatelessWidget {
  const _MovementMetric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF66758A))),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementHeader extends StatelessWidget {
  const _MovementHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Tarih / Saat')),
          Expanded(flex: 3, child: Text('Ürün')),
          Expanded(flex: 2, child: Text('Hareket Türü')),
          Expanded(flex: 3, child: Text('Depo')),
          Expanded(flex: 2, child: Text('Miktar')),
          Expanded(flex: 4, child: Text('Açıklama')),
          SizedBox(width: 70, child: Text('İşlem')),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.item, required this.onDelete});

  final StockMovementItem item;
  final VoidCallback onDelete;

  bool get outgoing =>
      item.type == 'out' || item.type == 'service' || item.type == 'transfer_out';

  Color get color {
    if (item.type.contains('transfer')) return const Color(0xFF2F80ED);
    if (item.type.contains('adjust')) return const Color(0xFFF5A623);
    return outgoing ? const Color(0xFFE45151) : const Color(0xFF18A66A);
  }

  String get label {
    switch (item.type) {
      case 'in':
        return 'Giriş';
      case 'out':
        return 'Çıkış';
      case 'service':
        return 'Servis Kullanımı';
      case 'transfer_in':
        return 'Transfer Giriş';
      case 'transfer_out':
        return 'Transfer Çıkış';
      default:
        return item.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE9EEF4))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd.MM.yyyy\nHH:mm', 'tr_TR').format(item.createdAt.toLocal()),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(item.productName,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          Expanded(flex: 3, child: Text(item.warehouseName)),
          Expanded(
            flex: 2,
            child: Text(
              '${outgoing ? '-' : '+'}${_InventoryStockMovementsScreenState._quantity(item.quantity)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(flex: 4, child: Text(item.notes ?? '-')),
          SizedBox(
            width: 70,
            child: IconButton(
              tooltip: 'Hareketi sil',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
