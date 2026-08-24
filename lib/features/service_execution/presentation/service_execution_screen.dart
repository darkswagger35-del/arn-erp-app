import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/service_execution_providers.dart';
import '../data/service_execution_repository.dart';
import '../../settings/data/company_app_settings.dart';
import '../../service_requests/data/models/service_request_model.dart';
import 'technician_service_pdf.dart';

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

  String _stockLabel(double value) {
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
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
      await _showCompletionActions();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servis tamamlanamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareCompletedPdf() async {
    final job = _job;
    if (job == null) return;
    final profile = ref.read(authControllerProvider).profile;
    final technicianName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Tekniker';
    await TechnicianServicePdf.share(
      job: job,
      technicianName: technicianName,
      serviceTypeLabel: _selectedServiceType.label,
      description: _descriptionController.text.trim(),
      completionNote: _workController.text.trim(),
      items: _selectedItems,
      serviceAmount: _serviceTotal,
      extraAmount: _extraTotal,
      totalAmount: _grandTotal,
      paymentMethodLabel: _paymentMethodLabel(_paymentMethod),
    );
  }

  Future<void> _showCompletionActions() async {
    final sendPdf = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF18A566)),
            SizedBox(width: 10),
            Expanded(child: Text('Servis tamamlandı')),
          ],
        ),
        content: const Text(
          'Servis kaydedildi. PDF servis formunu şimdi müşteriye paylaşabilirsiniz. Telefonda paylaşım ekranından WhatsApp seçebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Listeye Dön'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF Paylaş'),
          ),
        ],
      ),
    );

    if (sendPdf == true) {
      try {
        await _shareCompletedPdf();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF paylaşılamadı: $error')),
          );
        }
      }
    }
    if (!mounted) return;
    context.go('/technician/jobs?refresh=${DateTime.now().millisecondsSinceEpoch}');
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

  Widget _selectedProductCard(Map<String, dynamic> product) {
    final id = product['id'].toString();
    final vehicleStock = (product['stock_quantity'] as num?)?.toDouble() ?? 0;
    final mainStock = (product['main_stock'] as num?)?.toDouble() ?? 0;
    final selectedQty = _quantities[id] ?? 0;
    final projectedVehicleStock = vehicleStock - selectedQty;
    const canChangeProducts = true;
    const canChangePrice = true;

    Widget quantityField() => SizedBox(
          width: 90,
          child: TextFormField(
            key: ValueKey('qty-$id'),
            readOnly: !canChangeProducts,
            initialValue: selectedQty.toStringAsFixed(selectedQty % 1 == 0 ? 0 : 1),
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Adet', isDense: true),
            onChanged: canChangeProducts
                ? (value) {
                    setState(() {
                      _quantities[id] = double.tryParse(value.replaceAll(',', '.')) ?? 0;
                    });
                  }
                : null,
            validator: (value) {
              final quantity = double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0;
              if (quantity <= 0) return 'Adet';
              return null;
            },
          ),
        );

    Widget priceField() => SizedBox(
          width: 125,
          child: TextFormField(
            key: ValueKey('price-$id'),
            readOnly: !canChangePrice,
            initialValue: (_unitPrices[id] ?? 0) == 0
                ? ''
                : (_unitPrices[id] ?? 0).toStringAsFixed(2),
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Fiyat (₺)', isDense: true),
            onChanged: canChangePrice
                ? (value) {
                    setState(() {
                      _unitPrices[id] = double.tryParse(value.replaceAll(',', '.')) ?? 0;
                    });
                  }
                : null,
            validator: (value) {
              final price = double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0;
              if (price < 0) return 'Fiyat';
              return null;
            },
          ),
        );

    final stockInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product['name']?.toString() ?? '-',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          'Araç: ${_stockLabel(vehicleStock)}  •  Merkez: ${_stockLabel(mainStock)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF66788A)),
        ),
        if (projectedVehicleStock < 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Bu kullanım sonrası araç stoğu ${_stockLabel(projectedVehicleStock)} olacak.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD2691E),
              ),
            ),
          ),
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stockInfo,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: quantityField()),
                      const SizedBox(width: 8),
                      Expanded(child: priceField()),
                      IconButton(
                        tooltip: 'Ürünü kaldır',
                        onPressed: canChangeProducts ? () => _removeProduct(id) : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: stockInfo),
                const SizedBox(width: 10),
                quantityField(),
                const SizedBox(width: 8),
                priceField(),
                IconButton(
                  tooltip: 'Ürünü kaldır',
                  onPressed: canChangeProducts ? () => _removeProduct(id) : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            );
          },
        ),
      ),
    );
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
    const canChangeProducts = true;
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
                        helperText: 'İsteğe bağlıdır. Gerekirse yapılan işlemi kısa not olarak yazın.',
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
            const SizedBox(height: 4),
            const Text(
              'Araçta olmayan ama merkez stoğunda bulunan ürünü de seçebilirsiniz. Kullanım sonrası araç stoğunuz eksiye düşerek eksik malzeme olarak görünür.',
              style: TextStyle(fontSize: 12, color: Color(0xFF66788A)),
            ),
            const SizedBox(height: 8),
            if (_products.isEmpty)
              const Text('Kullanılabilir firma ürünü bulunmuyor.')
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedProductId,
                      decoration: const InputDecoration(
                        labelText: 'Ürün seç',
                      ),
                      items: _products
                          .where((product) =>
                              (_quantities[product['id'].toString()] ?? 0) <= 0)
                          .map(
                            (product) => DropdownMenuItem<String>(
                              value: product['id'].toString(),
                              child: Text(
                                '${product['name']?.toString() ?? '-'}  •  Araç: ${_stockLabel((product['stock_quantity'] as num?)?.toDouble() ?? 0)}  •  Merkez: ${_stockLabel((product['main_stock'] as num?)?.toDouble() ?? 0)}',
                                overflow: TextOverflow.ellipsis,
                              ),
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
                  .map((product) => _selectedProductCard(product)),
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
