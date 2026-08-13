import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceEditProduct {
  const ServiceEditProduct({required this.id, required this.name, required this.salePrice});

  final String id;
  final String name;
  final double salePrice;

  factory ServiceEditProduct.fromMap(Map<String, dynamic> map) {
    return ServiceEditProduct(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      salePrice: (map['sale_price'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ServiceRequestEditResult {
  const ServiceRequestEditResult({
    required this.serviceType,
    required this.plannedDate,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.price,
    required this.description,
  });

  final String serviceType;
  final DateTime plannedDate;
  final String? productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double price;
  final String description;
}

Future<List<ServiceEditProduct>> loadActiveServiceProducts() async {
  final rows = await Supabase.instance.client
      .from('products')
      .select('id, name, sale_price')
      .eq('is_active', true)
      .order('name');
  return List<Map<String, dynamic>>.from(rows)
      .map(ServiceEditProduct.fromMap)
      .where((p) => p.id.isNotEmpty && p.name.trim().isNotEmpty)
      .toList(growable: false);
}

Future<ServiceRequestEditResult?> showServiceRequestEditDialog({
  required BuildContext context,
  required String title,
  required String initialServiceType,
  required DateTime? initialPlannedDate,
  required String? initialProductId,
  required String initialProductName,
  required double initialQuantity,
  required double initialUnitPrice,
  required double initialPrice,
  required String initialDescription,
}) async {
  List<ServiceEditProduct> products;
  try {
    products = await loadActiveServiceProducts();
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ürün listesi yüklenemedi: $e')),
    );
    return null;
  }
  if (!context.mounted) return null;

  return showDialog<ServiceRequestEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ServiceRequestEditDialog(
      title: title,
      products: products,
      initialServiceType: initialServiceType,
      initialPlannedDate: initialPlannedDate,
      initialProductId: initialProductId,
      initialProductName: initialProductName,
      initialQuantity: initialQuantity,
      initialUnitPrice: initialUnitPrice,
      initialPrice: initialPrice,
      initialDescription: initialDescription,
    ),
  );
}

class _ServiceRequestEditDialog extends StatefulWidget {
  const _ServiceRequestEditDialog({
    required this.title,
    required this.products,
    required this.initialServiceType,
    required this.initialPlannedDate,
    required this.initialProductId,
    required this.initialProductName,
    required this.initialQuantity,
    required this.initialUnitPrice,
    required this.initialPrice,
    required this.initialDescription,
  });

  final String title;
  final List<ServiceEditProduct> products;
  final String initialServiceType;
  final DateTime? initialPlannedDate;
  final String? initialProductId;
  final String initialProductName;
  final double initialQuantity;
  final double initialUnitPrice;
  final double initialPrice;
  final String initialDescription;

  @override
  State<_ServiceRequestEditDialog> createState() => _ServiceRequestEditDialogState();
}

class _ServiceRequestEditDialogState extends State<_ServiceRequestEditDialog> {
  late String _serviceType;
  DateTime? _plannedDate;
  ServiceEditProduct? _selectedProduct;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  bool _recalculating = false;

  @override
  void initState() {
    super.initState();
    _serviceType = const ['new_installation', 'filter_change', 'fault', 'other'].contains(widget.initialServiceType)
        ? widget.initialServiceType
        : 'other';
    _plannedDate = widget.initialPlannedDate;
    _selectedProduct = widget.products.cast<ServiceEditProduct?>().firstWhere(
          (p) => p?.id == widget.initialProductId ||
              (widget.initialProductId == null && p?.name.toLowerCase() == widget.initialProductName.toLowerCase()),
          orElse: () => null,
        );
    _quantityController = TextEditingController(text: _numberText(widget.initialQuantity));
    _unitPriceController = TextEditingController(text: _numberText(widget.initialUnitPrice));
    _priceController = TextEditingController(text: _numberText(widget.initialPrice));
    _descriptionController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _unitPriceController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _numberText(double value) {
    if (value <= 0) return '';
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  double _parse(String text) => double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  void _recalculateTotal() {
    if (_recalculating) return;
    _recalculating = true;
    final total = _parse(_quantityController.text) * _parse(_unitPriceController.text);
    _priceController.text = _numberText(total);
    _recalculating = false;
    setState(() {});
  }

  Future<void> _pickDateTime() async {
    final base = _plannedDate ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      _plannedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  void _save() {
    if (_plannedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarih ve saat zorunlu.')));
      return;
    }
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen ürün listesinden bir ürün seçin.')));
      return;
    }
    final qty = _parse(_quantityController.text);
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adet 0’dan büyük olmalı.')));
      return;
    }
    final unitPrice = _parse(_unitPriceController.text);
    final total = _parse(_priceController.text);
    Navigator.of(context).pop(
      ServiceRequestEditResult(
        serviceType: _serviceType,
        plannedDate: _plannedDate!,
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name,
        quantity: qty,
        unitPrice: unitPrice,
        price: total,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _serviceType,
                decoration: const InputDecoration(labelText: 'Servis Türü'),
                items: const [
                  DropdownMenuItem(value: 'new_installation', child: Text('Yeni Kurulum')),
                  DropdownMenuItem(value: 'filter_change', child: Text('Filtre Değişimi')),
                  DropdownMenuItem(value: 'fault', child: Text('Arıza')),
                  DropdownMenuItem(value: 'other', child: Text('Servis')),
                ],
                onChanged: (value) => setState(() => _serviceType = value ?? 'other'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Planlanan Tarih / Saat *'),
                  child: Text(
                    _plannedDate == null
                        ? 'Tarih ve saat seçin'
                        : DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(_plannedDate!),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Autocomplete<ServiceEditProduct>(
                initialValue: TextEditingValue(text: _selectedProduct?.name ?? widget.initialProductName),
                displayStringForOption: (option) => option.name,
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  if (query.isEmpty) return widget.products;
                  return widget.products.where((p) => p.name.toLowerCase().contains(query));
                },
                onSelected: (product) {
                  setState(() => _selectedProduct = product);
                  _unitPriceController.text = _numberText(product.salePrice);
                  if (_parse(_quantityController.text) <= 0) _quantityController.text = '1';
                  _recalculateTotal();
                },
                fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Planlanan Ürün / İşlem *',
                      hintText: 'Ürün adı yazın ve listeden seçin',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      final selected = _selectedProduct;
                      if (selected != null && value.trim() != selected.name) {
                        setState(() => _selectedProduct = null);
                      }
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  final list = options.toList(growable: false);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 590),
                        child: list.isEmpty
                            ? const Padding(padding: EdgeInsets.all(16), child: Text('Eşleşen ürün bulunamadı.'))
                            : ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: list.length,
                                itemBuilder: (context, index) {
                                  final product = list[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(product.name),
                                    trailing: Text(product.salePrice > 0 ? '₺${product.salePrice.toStringAsFixed(2)}' : 'Fiyat yok'),
                                    onTap: () => onSelected(product),
                                  );
                                },
                              ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Adet'),
                      onChanged: (_) => _recalculateTotal(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _unitPriceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Birim Fiyat', prefixText: '₺ '),
                      onChanged: (_) => _recalculateTotal(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Toplam Tutar',
                  prefixText: '₺ ',
                  helperText: 'Adet × birim fiyat ile otomatik hesaplanır; gerekirse değiştirilebilir.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Açıklama / Not'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
