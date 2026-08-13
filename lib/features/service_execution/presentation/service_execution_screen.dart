import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/service_execution_providers.dart';
import '../data/service_execution_repository.dart';
import '../../settings/data/company_app_settings.dart';
import '../../service_requests/data/models/service_request_model.dart';

class ServiceExecutionScreen extends ConsumerStatefulWidget {
  const ServiceExecutionScreen({super.key, required this.serviceRequestId});

  final String serviceRequestId;

  @override
  ConsumerState<ServiceExecutionScreen> createState() =>
      _ServiceExecutionScreenState();
}

class _ServiceExecutionScreenState
    extends ConsumerState<ServiceExecutionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _workController = TextEditingController();
  final _serviceFeeController = TextEditingController();
  final _extraFeeController = TextEditingController(text: '0');

  TechnicianJob? _job;
  List<Map<String, dynamic>> _products = const [];
  final Map<String, double> _quantities = {};
  final Map<String, double> _unitPrices = {};
  bool _loading = true;
  bool _saving = false;
  String _paymentMethod = 'cash';
  CompanyAppSettings _appSettings = const CompanyAppSettings(companyId: '');
  String? _selectedProductId;
  ServiceRequestType _selectedServiceType = ServiceRequestType.other;

  @override
  void initState() {
    super.initState();
    _serviceFeeController.addListener(_refreshAmounts);
    _extraFeeController.addListener(_refreshAmounts);
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _workController.dispose();
    _serviceFeeController.removeListener(_refreshAmounts);
    _extraFeeController.removeListener(_refreshAmounts);
    _serviceFeeController.dispose();
    _extraFeeController.dispose();
    super.dispose();
  }


  void _refreshAmounts() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(serviceExecutionRepositoryProvider);
      final results = await Future.wait([
        repo.getJob(widget.serviceRequestId),
        repo.getActiveProducts(ref.read(authControllerProvider).profile?.id ?? ''),
        ref.read(companyAppSettingsProvider.future),
      ]);
      if (!mounted) return;
      setState(() {
        _job = results[0] as TechnicianJob?;
        _products = results[1] as List<Map<String, dynamic>>;
        _selectedServiceType = _technicianServiceType(ServiceRequestTypeX.fromValue(_job?.serviceType));
        _descriptionController.text = _job?.description ?? '';
        _workController.text = _job?.completionNote ?? '';
        _appSettings = results[2] as CompanyAppSettings;
        if (!_appSettings.serviceRule('technician_can_collect_payment', fallback: true)) {
          _paymentMethod = 'open_account';
        } else {
          _paymentMethod = _appSettings.enabledPaymentMethods.contains(
            _appSettings.defaultPaymentMethod,
          )
              ? _appSettings.defaultPaymentMethod
              : _appSettings.enabledPaymentMethods.first;
        }
        _loading = false;
        // Sekreterin seçtiği ürün servis bedeli olarak değil, gerçek ürün
        // satırı olarak işlenir. Böylece teknisyen araç stokundan düşer.
        _serviceFeeController.text = '0';

        final plannedProductName = _job?.plannedProductName.trim() ?? '';
        String? plannedId = _job?.plannedProductId;

        // Eski/Excel kayıtlarında planned_product_id boş olup yalnızca ürün adı
        // bulunabiliyor. Bu durumda araç deposundaki ürün adına göre eşleştir.
        if ((plannedId == null || plannedId.isEmpty) &&
            plannedProductName.isNotEmpty) {
          for (final product in _products) {
            final productName = product['name']?.toString().trim() ?? '';
            if (productName.toLowerCase() == plannedProductName.toLowerCase()) {
              plannedId = product['id']?.toString();
              break;
            }
          }
        }

        if (plannedId != null &&
            plannedId.isNotEmpty &&
            (_job?.plannedQuantity ?? 0) > 0) {
          _quantities[plannedId] = _job!.plannedQuantity.toDouble();
          double defaultPrice = _job!.plannedUnitPrice > 0
              ? _job!.plannedUnitPrice
              : _job!.price;
          if (defaultPrice <= 0) {
            for (final product in _products) {
              if (product['id']?.toString() == plannedId) {
                defaultPrice = (product['sale_price'] as num?)?.toDouble() ?? 0;
                break;
              }
            }
          }
          _unitPrices[plannedId] = defaultPrice;
        }
        final available = _products
            .where((p) => (_quantities[p['id'].toString()] ?? 0) <= 0)
            .toList(growable: false);
        _selectedProductId =
            available.isEmpty ? null : available.first['id'].toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis bilgileri yüklenemedi.')),
      );
    }
  }


  ServiceRequestType _technicianServiceType(ServiceRequestType type) {
    switch (type) {
      case ServiceRequestType.newInstallation:
      case ServiceRequestType.filterChange:
      case ServiceRequestType.fault:
      case ServiceRequestType.other:
        return type;
      case ServiceRequestType.maintenance:
      case ServiceRequestType.membrane:
      case ServiceRequestType.externalFilter:
      case ServiceRequestType.relocation:
      case ServiceRequestType.removal:
        return ServiceRequestType.other;
    }
  }

  double _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  List<Map<String, dynamic>> get _selectedItems {
    return _products
        .where((product) => (_quantities[product['id'].toString()] ?? 0) > 0)
        .map((product) {
          final id = product['id'].toString();
          return {
            'product_id': id,
            'product_name': product['name']?.toString() ?? '',
            'quantity': _quantities[id] ?? 0,
            'unit_price': _unitPrices[id] ?? 0,
            'warehouse_id': product['warehouse_id'],
          };
        })
        .toList(growable: false);
  }

  double get _productTotal => _selectedItems.fold<double>(
    0,
    (sum, item) =>
        sum +
        ((item['quantity'] as num?)?.toDouble() ?? 0) *
            ((item['unit_price'] as num?)?.toDouble() ?? 0),
  );

  double get _serviceTotal => _number(_serviceFeeController);

  double get _extraTotal => _number(_extraFeeController);

  double get _grandTotal => _serviceTotal + _productTotal + _extraTotal;

  double get _collectedAmount =>
      _paymentMethod == 'open_account' ? 0 : _grandTotal;

  Future<void> _startService() async {
    await ref
        .read(serviceExecutionRepositoryProvider)
        .startService(widget.serviceRequestId);
    if (!mounted) return;
    setState(() {
      final current = _job;
      if (current != null) {
        _job = TechnicianJob(
          id: current.id,
          customerId: current.customerId,
          customerName: current.customerName,
          phone: current.phone,
          address: current.address,
          serviceType: current.serviceType,
          description: current.description,
          status: 'in_progress',
          price: current.price,
          plannedDate: current.plannedDate,
          plannedProductId: current.plannedProductId,
          plannedProductName: current.plannedProductName,
          plannedQuantity: current.plannedQuantity,
          plannedUnitPrice: current.plannedUnitPrice,
          secretaryName: current.secretaryName,
          completionNote: current.completionNote,
          latitude: current.latitude,
          longitude: current.longitude,
          mapsUrl: current.mapsUrl,
          city: current.city,
          district: current.district,
          neighborhood: current.neighborhood,
          routeOrder: current.routeOrder,
          routePlanDate: current.routePlanDate,
        );
      }
    });
  }

  void _addSelectedProduct() {
    final id = _selectedProductId;
    if (id == null || id.isEmpty) return;
    setState(() {
      _quantities[id] = 1;
      double defaultPrice = 0;
      for (final product in _products) {
        if (product['id']?.toString() == id) {
          defaultPrice = (product['sale_price'] as num?)?.toDouble() ?? 0;
          break;
        }
      }
      _unitPrices.putIfAbsent(id, () => defaultPrice);
      final available = _products
          .where((p) => (_quantities[p['id'].toString()] ?? 0) <= 0)
          .toList(growable: false);
      _selectedProductId =
          available.isEmpty ? null : available.first['id'].toString();
    });
  }

  void _removeProduct(String id) {
    setState(() {
      _quantities.remove(id);
      _unitPrices.remove(id);
      _selectedProductId ??= id;
    });
  }

  Future<void> _complete() async {
    if (!(_formKey.currentState?.validate() ?? false) || _job == null) return;

    if (_appSettings.serviceRule('require_work_description', fallback: true) &&
        _workController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yapılan işlem / tamamlama notu zorunludur.')),
      );
      return;
    }
    if (_selectedServiceType == ServiceRequestType.filterChange &&
        _appSettings.serviceRule('require_product_for_filter_change', fallback: true) &&
        _selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Filtre Değişimi için en az bir ürün seçilmelidir.')),
      );
      return;
    }

    final auth = ref.read(authControllerProvider);
    final profile = auth.profile;
    if (profile == null) return;

    setState(() => _saving = true);
    try {
      final repository = ref.read(serviceExecutionRepositoryProvider);
      await repository.updateServiceContent(
        serviceRequestId: widget.serviceRequestId,
        serviceType: _selectedServiceType.value,
        description: _descriptionController.text,
        completionNote: _workController.text,
      );
      await repository.completeService(
            serviceRequestId: widget.serviceRequestId,
            customerId: _job!.customerId,
            companyId: profile.companyId,
            technicianId: profile.id,
            workDescription: _workController.text.trim().isNotEmpty
                ? _workController.text.trim()
                : 'Servis tamamlandı',
            serviceAmount: _serviceTotal,
            extraAmount: _extraTotal,
            collectedAmount: _collectedAmount,
            paymentMethod: _paymentMethod,
            items: _selectedItems,
          );
      // complete_service_v5 eski kurulumlarda açıklama alanını yeniden yazabildiği
      // için teknisyenin son seçimini tamamlamadan sonra bir kez daha sabitliyoruz.
      await repository.updateServiceContent(
        serviceRequestId: widget.serviceRequestId,
        serviceType: _selectedServiceType.value,
        description: _descriptionController.text,
        completionNote: _workController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis başarıyla tamamlandı.')),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/technician/jobs?refresh=${DateTime.now().millisecondsSinceEpoch}');
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servis tamamlanamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markIncomplete() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Servis tamamlanamadı'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Sebep'),
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
    if (reason == null || reason.isEmpty) return;
    await ref
        .read(serviceExecutionRepositoryProvider)
        .markCouldNotComplete(
          serviceRequestId: widget.serviceRequestId,
          reason: reason,
        );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/technician/jobs?refresh=${DateTime.now().millisecondsSinceEpoch}');
    });
  }

  String _plannedDateLabel(DateTime raw) {
    final value = raw.toLocal();
    final date = DateFormat('dd.MM.yyyy', 'tr_TR').format(value);
    if (value.hour == 0 && value.minute == 0) return '$date • Gün içinde';
    return '$date • ${DateFormat('HH:mm', 'tr_TR').format(value)}';
  }

  String _paymentMethodLabel(String method) {
    return switch (method) {
      'cash' => 'Nakit',
      'card' => 'Kredi Kartı',
      'transfer' => 'Havale / EFT',
      'open_account' => 'Açık Hesap',
      _ => method,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final job = _job;
    if (job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Servis')),
        body: const Center(child: Text('Servis kaydı bulunamadı.')),
      );
    }

    // Tekniker sahada müşteri talebini ve servis açıklamasını güncelleyebilir.
    const canEditService = true;
    final canChangeProducts = _appSettings.serviceRule(
      'technician_can_change_products',
      fallback: true,
    );
    // Tekniker sahada gerçekleşen satış fiyatını güncelleyebilir.
    const canChangePrice = true;
    final canCollectPayment = _appSettings.serviceRule(
      'technician_can_collect_payment',
      fallback: true,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/technician/jobs'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(job.customerName),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.address),
                    if (job.plannedDate != null) ...[
                      const SizedBox(height: 8),
                      Text(_plannedDateLabel(job.plannedDate!)),
                    ],
                    const SizedBox(height: 12),
                    if (job.status != 'in_progress')
                      FilledButton.icon(
                        onPressed: _startService,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Servise Başla'),
                      )
                    else
                      const Chip(label: Text('Servis devam ediyor')),
                  ],
                ),
              ),
            ),
            if (job.plannedProductName.isNotEmpty) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Sekreterin seçtiği ürün: ${job.plannedProductName}'),
                  subtitle: Text('Planlanan adet: ${job.plannedQuantity}'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Servis İçeriğini Güncelle',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ServiceRequestType>(
                      value: _selectedServiceType,
                      decoration: const InputDecoration(
                        labelText: 'Servis Türü',
                        border: OutlineInputBorder(),
                      ),
                      items: const <ServiceRequestType>[
                            ServiceRequestType.newInstallation,
                            ServiceRequestType.filterChange,
                            ServiceRequestType.fault,
                            ServiceRequestType.other,
                          ]
                          .where((type) => _appSettings.enabledServiceTypes.contains(type.value) || type == _selectedServiceType)
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ))
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedServiceType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      readOnly: !canEditService,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama / Müşteri Talebi',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _workController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Tamamlama Notu / Yapılan İşlem',
                        helperText: 'Teknisyen burada yapılan gerçek işlemi yazar.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Kullanılan Ürünler',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_products.isEmpty)
              const Text('Araç deponuzda kullanılabilir ürün bulunmuyor.')
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedProductId,
                      decoration: const InputDecoration(
                        labelText: 'Araçtan ürün seç',
                      ),
                      items: _products
                          .where((product) =>
                              (_quantities[product['id'].toString()] ?? 0) <= 0)
                          .map(
                            (product) => DropdownMenuItem<String>(
                              value: product['id'].toString(),
                              child: Text(product['name']?.toString() ?? '-'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: canChangeProducts
                          ? (value) => setState(() => _selectedProductId = value)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: !canChangeProducts || _selectedProductId == null
                        ? null
                        : _addSelectedProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._products
                  .where((product) =>
                      (_quantities[product['id'].toString()] ?? 0) > 0)
                  .map((product) {
                final id = product['id'].toString();
                final stock =
                    (product['stock_quantity'] as num?)?.toDouble() ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            product['name']?.toString() ?? '-',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 82,
                          child: TextFormField(
                            key: ValueKey('qty-$id'),
                            readOnly: !canChangeProducts,
                            initialValue: (_quantities[id] ?? 1).toStringAsFixed(
                              (_quantities[id] ?? 1) % 1 == 0 ? 0 : 1,
                            ),
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Adet',
                              isDense: true,
                            ),
                            onChanged: canChangeProducts
                                ? (value) {
                                    setState(() {
                                      _quantities[id] = double.tryParse(
                                            value.replaceAll(',', '.'),
                                          ) ??
                                          0;
                                    });
                                  }
                                : null,
                            validator: (value) {
                              final quantity = double.tryParse(
                                    (value ?? '').replaceAll(',', '.'),
                                  ) ??
                                  0;
                              if (quantity <= 0) return 'Adet';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            key: ValueKey('price-$id'),
                            readOnly: !canChangePrice,
                            initialValue: (_unitPrices[id] ?? 0) == 0
                                ? ''
                                : (_unitPrices[id] ?? 0).toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Fiyat (₺)',
                              isDense: true,
                            ),
                            onChanged: canChangePrice
                                ? (value) {
                                    setState(() {
                                      _unitPrices[id] = double.tryParse(
                                            value.replaceAll(',', '.'),
                                          ) ??
                                          0;
                                    });
                                  }
                                : null,
                            validator: (value) {
                              final price = double.tryParse(
                                    (value ?? '').replaceAll(',', '.'),
                                  ) ??
                                  0;
                              if (price < 0) return 'Fiyat';
                              return null;
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ürünü kaldır',
                          onPressed: canChangeProducts ? () => _removeProduct(id) : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _extraFeeController,
              readOnly: !canChangePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Ekstra Ücret (₺)',
                helperText: 'Ekstra ücret stoktan ürün düşürmez.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(labelText: 'Ödeme Yöntemi'),
              items: _appSettings.enabledPaymentMethods
                  .map(
                    (method) => DropdownMenuItem<String>(
                      value: method,
                      child: Text(_paymentMethodLabel(method)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: canCollectPayment
                  ? (value) {
                      if (value == null) return;
                      setState(() => _paymentMethod = value);
                    }
                  : null,
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _AmountRow(label: 'Ürün Toplamı', amount: _productTotal),
                    if (_extraTotal > 0)
                      _AmountRow(label: 'Ekstra Ücret', amount: _extraTotal),
                    const Divider(),
                    _AmountRow(
                      label: 'Genel Toplam',
                      amount: _grandTotal,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving || job.status != 'in_progress'
                  ? null
                  : _complete,
              icon: const Icon(Icons.task_alt),
              label: Text(_saving ? 'Kaydediliyor...' : 'Servisi Tamamla'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : _markIncomplete,
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Tamamlanamadı Olarak İşaretle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final double amount;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(amount),
            style: style,
          ),
        ],
      ),
    );
  }
}
