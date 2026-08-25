import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/auth/app_role.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../customers/data/models/customer_model.dart';
import '../../data/models/service_request_model.dart';
import '../providers/service_request_providers.dart';
import '../../../settings/data/company_app_settings.dart';
import '../../../customers/presentation/screens/customer_module_shell.dart';

class ServiceRequestFormScreen extends ConsumerStatefulWidget {
  const ServiceRequestFormScreen({
    super.key,
    required this.role,
    required this.customerId,
  });

  final AppRole role;
  final String customerId;

  @override
  ConsumerState<ServiceRequestFormScreen> createState() =>
      _ServiceRequestFormScreenState();
}

class _ServiceRequestFormScreenState
    extends ConsumerState<ServiceRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _addressController = TextEditingController();
  final _customerNotesController = TextEditingController();
  String? _syncedCustomerId;
  bool _editingCustomer = false;

  ServiceRequestType _serviceType = ServiceRequestType.filterChange;
  DateTime? _plannedDate;
  String _appointmentMode = 'day';
  TimeOfDay? _plannedTime;
  TimeOfDay? _plannedEndTime;
  List<Map<String, dynamic>> _products = const [];
  String? _selectedProductId;
  double _selectedProductPrice = 0;
  final _quantityController = TextEditingController(text: '1');
  List<String> _enabledServiceTypes = ServiceRequestType.values
      .map((type) => type.value)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(customerControllerProvider).loadCustomer(widget.customerId);
      _loadProducts();
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _neighborhoodController.dispose();
    _addressController.dispose();
    _customerNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerState = ref.watch(customerControllerProvider).state;
    final serviceRequestState = ref.watch(serviceRequestControllerProvider).state;
    final customer = customerState.currentCustomer;
    if (customer != null) {
      _syncCustomerEditors(customer);
    }

    return CustomerModuleShell(
      role: widget.role,
      title: 'Servis Talebi Oluştur',
      actions: [
        OutlinedButton.icon(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Geri Dön'),
        ),
      ],
      child: customerState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : customer == null
              ? const Center(child: Text('Müşteri bulunamadı.'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(22),
                    children: [
                      const Text(
                        'Müşteri için yeni servis talebi oluşturun.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: _panelDecoration(),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: const Color(0xFF0DB6C1),
                              child: Text(
                                _initials(customer.displayName),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          customer.displayName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF102033),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE3F7EC),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'Aktif Müşteri',
                                          style: TextStyle(color: Color(0xFF169B55), fontWeight: FontWeight.w800, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 24,
                                    runSpacing: 8,
                                    children: [
                                      _miniInfo(Icons.phone_outlined, customer.phone),
                                      _miniInfo(Icons.location_on_outlined, '${customer.city ?? '-'} / ${customer.district ?? '-'}'),
                                      _miniInfo(Icons.home_outlined, customer.address),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (widget.role != AppRole.technician)
                                  OutlinedButton.icon(
                                    onPressed: serviceRequestState.isSaving
                                        ? null
                                        : () => setState(() => _editingCustomer = !_editingCustomer),
                                    icon: Icon(_editingCustomer ? Icons.close : Icons.edit_outlined),
                                    label: Text(_editingCustomer ? 'Düzenlemeyi Kapat' : 'Bilgileri Düzenle'),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => context.go(_customerRoute()),
                                  icon: const Icon(Icons.badge_outlined),
                                  label: const Text('Müşteri Kartını Görüntüle'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 900;
                          final left = _serviceInformationPanel(serviceRequestState.isSaving);
                          final right = _addressAndNotePanel(customer, serviceRequestState.isSaving);
                          return narrow
                              ? Column(children: [left, const SizedBox(height: 16), right])
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: left),
                                    const SizedBox(width: 16),
                                    Expanded(child: right),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF5FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFB9DAF8)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF1673C9)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Teknisyen ataması yönetici tarafından yapılacaktır.',
                                    style: TextStyle(color: Color(0xFF135FA7), fontWeight: FontWeight.w900),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Talep oluşturulduğunda “Atama Bekliyor” durumuyla yönetici ekranına düşecektir.',
                                    style: TextStyle(color: Color(0xFF356E9E)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (serviceRequestState.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(serviceRequestState.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          OutlinedButton(onPressed: serviceRequestState.isSaving ? null : _goBack, child: const Text('İptal')),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: serviceRequestState.isSaving ? null : _save,
                            icon: serviceRequestState.isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.save_outlined),
                            label: Text(serviceRequestState.isSaving ? 'Kaydediliyor...' : 'Servis Talebini Oluştur'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  bool get _isSecretary => widget.role == AppRole.secretary;

  bool _serviceNeedsPlannedProduct(ServiceRequestType type) =>
      type == ServiceRequestType.newInstallation ||
      type == ServiceRequestType.filterChange;

  bool get _needsPlannedProduct => _serviceNeedsPlannedProduct(_serviceType);

  void _changeServiceType(ServiceRequestType value) {
    final previouslyNeededProduct = _needsPlannedProduct;
    setState(() {
      _serviceType = value;
      if (!_serviceNeedsPlannedProduct(value)) {
        _selectedProductId = null;
        _selectedProductPrice = 0;
        _quantityController.text = '1';
        _priceController.text = '0';
      } else if (!previouslyNeededProduct) {
        _selectedProductId = null;
        _selectedProductPrice = 0;
        _quantityController.text = '1';
        _priceController.clear();
      }
    });
  }

  Widget _serviceInformationPanel(bool saving) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Servis Bilgileri', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
          const SizedBox(height: 18),
          DropdownButtonFormField<ServiceRequestType>(
            value: _serviceType,
            decoration: const InputDecoration(labelText: 'Servis Türü *'),
            items: ServiceRequestType.values
                .where((type) => const [ServiceRequestType.newInstallation, ServiceRequestType.filterChange, ServiceRequestType.fault, ServiceRequestType.other].contains(type))
                .where((type) => _enabledServiceTypes.contains(type.value) || type == ServiceRequestType.other)
                .map((type) => DropdownMenuItem(value: type, child: Text(_serviceTypeLabel(type))))
                .toList(),
            onChanged: saving ? null : (value) => value == null ? null : _changeServiceType(value),
          ),
          const SizedBox(height: 14),
          if (_needsPlannedProduct) ...[
            DropdownButtonFormField<String>(
              value: _selectedProductId,
              decoration: const InputDecoration(
                labelText: 'Ürün / İşlem *',
                hintText: 'Planlanan ürünü seçin',
              ),
              items: _products.map((product) {
                final id = product['id'].toString();
                final name = product['name']?.toString() ?? '-';
                return DropdownMenuItem(value: id, child: Text(name));
              }).toList(),
              onChanged: saving
                  ? null
                  : (value) {
                      Map<String, dynamic>? product;
                      for (final item in _products) {
                        if (item['id'].toString() == value) product = item;
                      }
                      setState(() {
                        _selectedProductId = value;
                        _selectedProductPrice =
                            (product?['sale_price'] as num?)?.toDouble() ?? 0;
                        if (_selectedProductPrice > 0) {
                          _priceController.text =
                              _selectedProductPrice.toStringAsFixed(0);
                        }
                      });
                    },
              validator: (value) =>
                  _needsPlannedProduct && value == null ? 'Bir ürün seçin.' : null,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    enabled: !saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Adet *'),
                    validator: (value) =>
                        (double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0) <= 0
                            ? 'Geçerli adet girin.'
                            : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    enabled: !saving,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Toplam Fiyat *',
                      prefixText: '₺ ',
                    ),
                    validator: (value) {
                      final price = double.tryParse((value ?? '')
                          .trim()
                          .replaceAll('.', '')
                          .replaceAll(',', '.'));
                      return price == null || price <= 0
                          ? 'Geçerli fiyat girin.'
                          : null;
                    },
                  ),
                ),
              ],
            ),
          ] else ...[
            TextFormField(
              controller: _priceController,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Planlanan Tutar',
                helperText: 'Arıza / Servis talebi 0 TL olarak açılabilir.',
                prefixText: '₺ ',
              ),
              validator: (value) {
                final price = double.tryParse((value ?? '0')
                    .trim()
                    .replaceAll('.', '')
                    .replaceAll(',', '.'));
                return price == null || price < 0
                    ? 'Tutar 0 veya daha büyük olmalıdır.'
                    : null;
              },
            ),
          ],
          const SizedBox(height: 14),
          InkWell(
            onTap: saving ? null : _selectPlannedDate,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Planlanan Tarih'),
              child: Row(children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 8),
                Text(_plannedDate == null ? 'Tarih seçilmedi' : _formatDate(_plannedDate!)),
                const Spacer(),
                if (_plannedDate != null)
                  IconButton(onPressed: () => setState(() => _plannedDate = null), icon: const Icon(Icons.clear), tooltip: 'Temizle'),
              ]),
            ),
          ),
          if (!_isSecretary) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _appointmentMode,
              decoration: const InputDecoration(
                labelText: 'Randevu Zamanı',
                helperText:
                    'Gün içinde, net saat veya saat aralığı seçebilirsiniz.',
              ),
              items: const [
                DropdownMenuItem(value: 'day', child: Text('Gün İçinde')),
                DropdownMenuItem(value: 'exact', child: Text('Net Saat')),
                DropdownMenuItem(value: 'range', child: Text('Saat Aralığı')),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() {
                        _appointmentMode = value ?? 'day';
                        if (_appointmentMode == 'day') {
                          _plannedTime = null;
                          _plannedEndTime = null;
                        } else if (_appointmentMode == 'exact') {
                          _plannedEndTime = null;
                        }
                      }),
            ),
            if (_appointmentMode != 'day') ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: saving ? null : _selectPlannedTime,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _appointmentMode == 'range'
                        ? 'Başlangıç Saati'
                        : 'Randevu Saati',
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _plannedTime == null
                            ? 'Saat seçin'
                            : _plannedTime!.format(context),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_appointmentMode == 'range') ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: saving ? null : _selectPlannedEndTime,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Bitiş Saati'),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _plannedEndTime == null
                            ? 'Bitiş saati seçin'
                            : _plannedEndTime!.format(context),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _descriptionController,
            enabled: !saving,
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: _isSecretary ? 'Sekreter Notu' : 'Açıklama / Şikayet',
              hintText: _isSecretary
                  ? 'Gerekirse saat bilgisini ve müşteri talebini buraya yazın.'
                  : 'Müşterinin talebini ve yapılacak işlemi yazın.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressAndNotePanel(CustomerModel customer, bool saving) {
    final canEdit = widget.role != AppRole.technician && _editingCustomer;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Müşteri / Servis Bilgileri',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF102033)),
                ),
              ),
              if (canEdit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7FAF8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text(
                    'Düzenleme açık',
                    style: TextStyle(color: Color(0xFF087E88), fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (canEdit) ...[
            TextFormField(
              controller: _customerNameController,
              enabled: !saving,
              decoration: const InputDecoration(labelText: 'Ad Soyad *', prefixIcon: Icon(Icons.person_outline)),
              validator: (value) => (value ?? '').trim().isEmpty ? 'Ad soyad girin.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _customerPhoneController,
              enabled: !saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefon *', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (value) => (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 10 ? 'Geçerli telefon girin.' : null,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(child: _customerField('Şehir', _cityController, canEdit, saving)),
              const SizedBox(width: 12),
              Expanded(child: _customerField('İlçe', _districtController, canEdit, saving)),
            ],
          ),
          const SizedBox(height: 12),
          _customerField('Mahalle', _neighborhoodController, canEdit, saving),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            readOnly: !canEdit,
            enabled: !saving,
            minLines: 4,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Adres *',
              filled: true,
              fillColor: canEdit ? Colors.white : const Color(0xFFF8FAFC),
            ),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Adres girin.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _customerNotesController,
            readOnly: !canEdit,
            enabled: !saving,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Müşteri Notu',
              filled: true,
              fillColor: canEdit ? Colors.white : const Color(0xFFF8FAFC),
            ),
          ),
          if (canEdit) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : () => _saveCustomerInfo(customer),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Müşteri Bilgilerini Kaydet'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF08A9B7),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Buradaki değişiklikler müşteri kartına da kaydedilir.',
              style: TextStyle(fontSize: 11, color: Color(0xFF7B8DA0)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customerField(
    String label,
    TextEditingController controller,
    bool canEdit,
    bool saving,
  ) {
    return TextFormField(
      controller: controller,
      readOnly: !canEdit,
      enabled: !saving,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: canEdit ? Colors.white : const Color(0xFFF8FAFC),
      ),
    );
  }

  void _syncCustomerEditors(CustomerModel customer) {
    if (_syncedCustomerId == customer.id) return;
    _syncedCustomerId = customer.id;
    _customerNameController.text = customer.fullName;
    _customerPhoneController.text = customer.phone;
    _cityController.text = customer.city ?? '';
    _districtController.text = customer.district ?? '';
    _neighborhoodController.text = customer.neighborhood ?? '';
    _addressController.text = customer.address;
    _customerNotesController.text = customer.notes ?? '';
  }

  Future<void> _saveCustomerInfo(CustomerModel customer) async {
    final updated = customer.copyWith(
      fullName: _customerNameController.text.trim(),
      phone: _customerPhoneController.text.trim(),
      city: _cityController.text.trim(),
      district: _districtController.text.trim(),
      neighborhood: _neighborhoodController.text.trim(),
      address: _addressController.text.trim(),
      notes: _customerNotesController.text.trim(),
    );

    await ref.read(customerControllerProvider).saveCustomer(updated);
    if (!mounted) return;
    final state = ref.read(customerControllerProvider).state;
    if (state.errorMessage != null) {
      _showMessage(state.errorMessage!);
      return;
    }
    _showMessage('Müşteri bilgileri güncellendi.');
    setState(() {
      _editingCustomer = false;
      _syncedCustomerId = null;
    });
    await ref.read(customerControllerProvider).loadCustomer(widget.customerId);
  }

  Widget _miniInfo(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19, color: const Color(0xFF65778A)), const SizedBox(width: 7), Text(text)]);

  BoxDecoration _panelDecoration() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1EAF0)));

  String _customerRoute() {
    final prefix = widget.role == AppRole.secretary ? '/secretary' : widget.role == AppRole.technician ? '/technician' : '/manager';
    return '$prefix/customers/${widget.customerId}';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }


  Future<void> _loadProducts() async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id, name, sale_price')
          .eq('is_active', true)
          .order('name');
      final settings = await ref.read(companyAppSettingsProvider.future);
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(rows);
        const allowed = <ServiceRequestType>[
          ServiceRequestType.newInstallation,
          ServiceRequestType.filterChange,
          ServiceRequestType.fault,
          ServiceRequestType.other,
        ];
        final configured = settings.enabledServiceTypes.isEmpty
            ? allowed.map((type) => type.value).toList(growable: false)
            : List<String>.from(settings.enabledServiceTypes);
        _enabledServiceTypes = allowed
            .where((type) => configured.contains(type.value) || type == ServiceRequestType.other)
            .map((type) => type.value)
            .toList(growable: false);
        if (!_enabledServiceTypes.contains(_serviceType.value)) {
          _serviceType = allowed.firstWhere(
            (type) => _enabledServiceTypes.contains(type.value),
            orElse: () => ServiceRequestType.other,
          );
        }
        if (!_serviceNeedsPlannedProduct(_serviceType) &&
            _priceController.text.trim().isEmpty) {
          _priceController.text = '0';
        }
      });
    } catch (_) {
      if (!mounted) return;
      _showMessage('Ürünler yüklenemedi.');
    }
  }

  String _selectedProductName() {
    for (final item in _products) {
      if (item['id'].toString() == _selectedProductId) {
        return item['name']?.toString() ?? '';
      }
    }
    return '';
  }

  Future<void> _selectPlannedDate() async {
    final now = DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _plannedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      _plannedDate = selectedDate;
    });
  }

  Future<void> _selectPlannedTime() async {
    if (_plannedDate == null) {
      _showMessage('Önce planlanan tarihi seçin.');
      return;
    }
    final selected = await showTimePicker(
      context: context,
      initialTime: _plannedTime ?? TimeOfDay.now(),
      helpText: 'Servis saatini seçin',
      cancelText: 'İptal',
      confirmText: 'Tamam',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _plannedTime = selected);
    }
  }


  Future<void> _selectPlannedEndTime() async {
    if (_plannedDate == null) {
      _showMessage('Önce planlanan tarihi seçin.');
      return;
    }
    final selected = await showTimePicker(
      context: context,
      initialTime: _plannedEndTime ?? _plannedTime ?? TimeOfDay.now(),
      helpText: 'Randevu bitiş saatini seçin',
      cancelText: 'İptal',
      confirmText: 'Tamam',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _plannedEndTime = selected);
    }
  }

  int _minutesOfDay(TimeOfDay value) => value.hour * 60 + value.minute;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_plannedDate == null) {
      _showMessage('Servis talebi için tarih seçmek zorunludur. Tarihsiz iş oluşturulamaz.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      _showMessage('Oturum doğrulanamadı.');
      return;
    }

    final normalizedPrice = _priceController.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final price = double.tryParse(normalizedPrice) ?? 0;

    if (!_isSecretary && _appointmentMode == 'exact' && _plannedTime == null) {
      _showMessage('Net saat için randevu saatini seçin.');
      return;
    }
    if (!_isSecretary && _appointmentMode == 'range') {
      if (_plannedTime == null || _plannedEndTime == null) {
        _showMessage('Saat aralığı için başlangıç ve bitiş saatini seçin.');
        return;
      }
      if (_minutesOfDay(_plannedEndTime!) <= _minutesOfDay(_plannedTime!)) {
        _showMessage('Bitiş saati başlangıç saatinden sonra olmalıdır.');
        return;
      }
    }

    final effectiveAppointmentMode = _isSecretary ? 'day' : _appointmentMode;
    final plannedDateTime = _plannedDate == null
        ? null
        : DateTime(
            _plannedDate!.year,
            _plannedDate!.month,
            _plannedDate!.day,
            effectiveAppointmentMode == 'day' ? 0 : (_plannedTime?.hour ?? 0),
            effectiveAppointmentMode == 'day' ? 0 : (_plannedTime?.minute ?? 0),
          );
    final timeTag = _isSecretary
        ? ''
        : switch (effectiveAppointmentMode) {
            'exact' =>
              '[Saat:${_plannedTime!.hour.toString().padLeft(2, '0')}:${_plannedTime!.minute.toString().padLeft(2, '0')}] ',
            'range' =>
              '[Aralık:${_plannedTime!.hour.toString().padLeft(2, '0')}:${_plannedTime!.minute.toString().padLeft(2, '0')}-${_plannedEndTime!.hour.toString().padLeft(2, '0')}:${_plannedEndTime!.minute.toString().padLeft(2, '0')}] ',
            _ => '[Gün içinde] ',
          };
    final quantity = _needsPlannedProduct
        ? (double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1)
        : 0.0;

    final request = ServiceRequestModel(
      customerId: widget.customerId,
      serviceType: _serviceType,
      description: '$timeTag${_descriptionController.text.trim()}',
      price: price,
      status: ServiceRequestStatus.pending,
      plannedDate: plannedDateTime,
      createdBy: user.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      plannedProductId: _needsPlannedProduct ? _selectedProductId : null,
      plannedProductName: _needsPlannedProduct ? _selectedProductName() : '',
      plannedQuantity: quantity,
      plannedUnitPrice: _needsPlannedProduct && quantity > 0 ? price / quantity : 0,
    );

    final success = await ref
        .read(serviceRequestControllerProvider)
        .createServiceRequest(request);

    if (!mounted) {
      return;
    }

    final state = ref.read(serviceRequestControllerProvider).state;

    if (!success) {
      _showMessage(state.errorMessage ?? 'Servis talebi oluşturulamadı.');
      return;
    }

    _showMessage(state.successMessage ?? 'Servis talebi oluşturuldu.');

    final customer = ref.read(customerControllerProvider).state.currentCustomer;
    if (customer != null) {
      final sendWhatsApp = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Randevu mesajı'),
          content: const Text(
            'Müşteriye “Randevunuz oluşturulmuştur” WhatsApp mesajı gönderilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Şimdi Değil'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp Gönder'),
            ),
          ],
        ),
      );

      if (sendWhatsApp == true && mounted) {
        await _sendAppointmentMessage(
          phone: customer.phone,
          customerName: customer.displayName,
        );
      }
    }

    if (mounted) _goBack();
  }

  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_customerRoute());
    }
  }

  Future<void> _sendAppointmentMessage({
    required String phone,
    required String customerName,
  }) async {
    var cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0')) cleaned = '90${cleaned.substring(1)}';
    if (cleaned.isEmpty) {
      _showMessage('Müşterinin telefon numarası bulunamadı.');
      return;
    }

    final settings = await ref.read(companyAppSettingsProvider.future);
    final appointmentText = switch (_appointmentMode) {
      'exact' when _plannedTime != null =>
        '${_plannedTime!.hour.toString().padLeft(2, '0')}:${_plannedTime!.minute.toString().padLeft(2, '0')}',
      'range' when _plannedTime != null && _plannedEndTime != null =>
        '${_plannedTime!.hour.toString().padLeft(2, '0')}:${_plannedTime!.minute.toString().padLeft(2, '0')} - ${_plannedEndTime!.hour.toString().padLeft(2, '0')}:${_plannedEndTime!.minute.toString().padLeft(2, '0')}',
      _ => 'gün içinde',
    };
    final dateText = _plannedDate == null
        ? 'belirlenecek tarihte'
        : _isSecretary
            ? DateFormat('dd.MM.yyyy', 'tr_TR').format(_plannedDate!)
            : '${DateFormat('dd.MM.yyyy', 'tr_TR').format(_plannedDate!)} • $appointmentText';
    final message = settings.appointmentTemplate
        .replaceAll('{{musteri}}', customerName)
        .replaceAll('{{müşteri}}', customerName)
        .replaceAll('{{tarih}}', dateText)
        .replaceAll('{{servis_turu}}', _serviceTypeLabel(_serviceType))
        .replaceAll('{{teknisyen}}', 'Atama sonrası bildirilecektir');

    final uri = Uri.https('wa.me', '/$cleaned', {'text': message});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage('WhatsApp açılamadı.');
    }
  }

  String _serviceTypeLabel(ServiceRequestType type) {
    switch (type) {
      case ServiceRequestType.newInstallation:
        return 'Yeni Kurulum';
      case ServiceRequestType.filterChange:
        return 'Filtre Değişimi';
      case ServiceRequestType.maintenance:
        return 'Bakım';
      case ServiceRequestType.fault:
        return 'Arıza';
      case ServiceRequestType.membrane:
        return 'Membran Değişimi';
      case ServiceRequestType.externalFilter:
        return 'Harici Filtre';
      case ServiceRequestType.relocation:
        return 'Taşıma';
      case ServiceRequestType.removal:
        return 'Söküm';
      case ServiceRequestType.other:
        return 'Servis';
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day.$month.${date.year}';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
