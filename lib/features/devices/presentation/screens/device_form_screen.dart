import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/widgets/arn_app_bar.dart';
import '../../../customers/data/models/customer_model.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../data/models/customer_device_model.dart';
import '../controllers/device_controller.dart';
import '../providers/device_providers.dart';

class DeviceFormScreen extends ConsumerStatefulWidget {
  const DeviceFormScreen({
    super.key,
    required this.role,
    this.deviceId,
    this.customerId,
  });

  final AppRole role;
  final String? deviceId;
  final String? customerId;

  @override
  ConsumerState<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends ConsumerState<DeviceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _serialNumberController;
  late final TextEditingController _qrCodeController;
  late final TextEditingController _membraneTypeController;
  late final TextEditingController _installationDateController;
  late final TextEditingController _lastMaintenanceDateController;
  late final TextEditingController _nextMaintenanceDateController;
  late final TextEditingController _descriptionController;

  late final Future<List<CustomerModel>> _customersFuture;
  Future<CustomerDeviceModel?>? _deviceFuture;
  String? _selectedCustomerId;
  DeviceType? _selectedDeviceType;
  PumpType? _selectedPumpType;
  bool _isActive = true;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _brandController = TextEditingController();
    _modelController = TextEditingController();
    _serialNumberController = TextEditingController();
    _qrCodeController = TextEditingController();
    _membraneTypeController = TextEditingController();
    _installationDateController = TextEditingController();
    _lastMaintenanceDateController = TextEditingController();
    _nextMaintenanceDateController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedCustomerId = widget.customerId;
    _customersFuture = _loadCustomers();
    if (widget.deviceId != null && widget.deviceId!.isNotEmpty) {
      _deviceFuture = ref.read(deviceDetailProvider(widget.deviceId!).future);
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _serialNumberController.dispose();
    _qrCodeController.dispose();
    _membraneTypeController.dispose();
    _installationDateController.dispose();
    _lastMaintenanceDateController.dispose();
    _nextMaintenanceDateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.role == AppRole.technician) {
      return Scaffold(
        appBar: ArnAppBar(
          title: 'Cihaz',
          role: widget.role,
          fallbackRoute: _dashboardFallbackRoute(),
        ),
        body: const Center(
          child: Text('Bu sayfaya erişim yetkiniz bulunmuyor.'),
        ),
      );
    }

    final state = ref.watch(deviceControllerProvider);
    final controller = ref.read(deviceControllerProvider.notifier);

    return Scaffold(
      appBar: ArnAppBar(
        title: widget.deviceId == null ? 'Yeni Cihaz' : 'Cihazı Düzenle',
        role: widget.role,
        fallbackRoute: _dashboardFallbackRoute(),
      ),
      body: FutureBuilder<List<CustomerModel>>(
        future: _customersFuture,
        builder: (context, customersSnapshot) {
          if (customersSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (customersSnapshot.hasError) {
            return Center(
              child: Text(
                'Müşteri listesi yüklenemedi. ${customersSnapshot.error}',
              ),
            );
          }

          final customers = customersSnapshot.data ?? const <CustomerModel>[];
          final existingDeviceFuture = _deviceFuture;

          if (existingDeviceFuture == null) {
            return _buildForm(context, state, controller, customers, null);
          }

          return FutureBuilder<CustomerDeviceModel?>(
            future: existingDeviceFuture,
            builder: (context, deviceSnapshot) {
              if (deviceSnapshot.connectionState == ConnectionState.waiting &&
                  !_hydrated) {
                return const Center(child: CircularProgressIndicator());
              }

              if (deviceSnapshot.hasError) {
                return Center(
                  child: Text(
                    'Cihaz bilgisi yüklenemedi. ${deviceSnapshot.error}',
                  ),
                );
              }

              final device = deviceSnapshot.data;
              if (device != null && !_hydrated) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _hydrated) {
                    return;
                  }
                  _hydrateDevice(device);
                });
              }

              return _buildForm(context, state, controller, customers, device);
            },
          );
        },
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    DeviceState state,
    DeviceController controller,
    List<CustomerModel> customers,
    CustomerDeviceModel? existingDevice,
  ) {
    final selectedCustomerExists =
        _selectedCustomerId != null &&
        customers.any((customer) => customer.id == _selectedCustomerId);
    final customerValue = selectedCustomerExists ? _selectedCustomerId : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: customerValue,
              decoration: const InputDecoration(labelText: 'Müşteri *'),
              items: customers
                  .map(
                    (customer) => DropdownMenuItem<String?>(
                      value: customer.id,
                      child: Text(customer.displayName),
                    ),
                  )
                  .toList(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Müşteri seçimi zorunludur.'
                  : null,
              onChanged: (value) {
                setState(() => _selectedCustomerId = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DeviceType>(
              initialValue: _selectedDeviceType,
              decoration: const InputDecoration(labelText: 'Cihaz Tipi *'),
              items: DeviceType.values
                  .map(
                    (value) => DropdownMenuItem<DeviceType>(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              validator: (value) =>
                  value == null ? 'Cihaz tipi zorunludur.' : null,
              onChanged: (value) => setState(() => _selectedDeviceType = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PumpType>(
              initialValue: _selectedPumpType,
              decoration: const InputDecoration(labelText: 'Pompa Tipi *'),
              items: PumpType.values
                  .map(
                    (value) => DropdownMenuItem<PumpType>(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              validator: (value) =>
                  value == null ? 'Pompa tipi zorunludur.' : null,
              onChanged: (value) => setState(() => _selectedPumpType = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(labelText: 'Marka'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serialNumberController,
              decoration: const InputDecoration(labelText: 'Seri Numarası'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qrCodeController,
              decoration: const InputDecoration(labelText: 'QR Kodu'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _membraneTypeController,
              decoration: const InputDecoration(labelText: 'Membran Tipi'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _installationDateController,
              decoration: const InputDecoration(
                labelText: 'Montaj Tarihi',
                hintText: 'gg.aa.yyyy',
              ),
              validator: (value) {
                final date = _parseDate(value);
                if (date == null) {
                  return null;
                }
                if (date.isAfter(_today())) {
                  return 'Montaj tarihi gelecekte olamaz.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastMaintenanceDateController,
              decoration: const InputDecoration(
                labelText: 'Son Bakım Tarihi',
                hintText: 'gg.aa.yyyy',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nextMaintenanceDateController,
              decoration: const InputDecoration(
                labelText: 'Sonraki Bakım Tarihi',
                hintText: 'gg.aa.yyyy',
              ),
              validator: (value) {
                final nextMaintenance = _parseDate(value);
                final lastMaintenance = _parseDate(
                  _lastMaintenanceDateController.text,
                );
                if (nextMaintenance != null &&
                    lastMaintenance != null &&
                    nextMaintenance.isBefore(lastMaintenance)) {
                  return 'Sonraki bakım tarihi, son bakım tarihinden önce olamaz.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Açıklama'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aktif'),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.isSaving
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);

                      if (!_formKey.currentState!.validate()) {
                        return;
                      }

                      final selectedCustomer =
                          customers
                              .where(
                                (customer) =>
                                    customer.id == _selectedCustomerId,
                              )
                              .isNotEmpty
                          ? customers.firstWhere(
                              (customer) => customer.id == _selectedCustomerId,
                            )
                          : null;

                      if (_selectedCustomerId == null ||
                          _selectedDeviceType == null ||
                          _selectedPumpType == null ||
                          selectedCustomer == null) {
                        _showMessage('Lütfen zorunlu alanları doldurun.');
                        return;
                      }

                      final installationDate = _parseDate(
                        _installationDateController.text,
                      );
                      final lastMaintenanceDate = _parseDate(
                        _lastMaintenanceDateController.text,
                      );
                      final nextMaintenanceDate = _parseDate(
                        _nextMaintenanceDateController.text,
                      );

                      if (installationDate != null &&
                          installationDate.isAfter(_today())) {
                        _showMessage('Montaj tarihi gelecekte olamaz.');
                        return;
                      }

                      if (lastMaintenanceDate != null &&
                          nextMaintenanceDate != null &&
                          nextMaintenanceDate.isBefore(lastMaintenanceDate)) {
                        _showMessage(
                          'Sonraki bakım tarihi, son bakım tarihinden önce olamaz.',
                        );
                        return;
                      }

                      final router = GoRouter.of(context);

                      final device = CustomerDeviceModel(
                        id: existingDevice?.id,
                        companyId: existingDevice?.companyId,
                        customerId: _selectedCustomerId,
                        customerName: selectedCustomer.displayName,
                        customerPhone: selectedCustomer.phone,
                        customerAddress: selectedCustomer.address,
                        brand: _brandController.text,
                        model: _modelController.text,
                        deviceType: _selectedDeviceType!,
                        pumpType: _selectedPumpType!,
                        serialNumber: _serialNumberController.text,
                        qrCode: _qrCodeController.text,
                        membraneType: _membraneTypeController.text,
                        installationDate: installationDate,
                        lastMaintenanceDate: lastMaintenanceDate,
                        nextMaintenanceDate: nextMaintenanceDate,
                        description: _descriptionController.text,
                        isActive: _isActive,
                        createdAt: existingDevice?.createdAt,
                        updatedAt: existingDevice?.updatedAt,
                        deletedAt: existingDevice?.deletedAt,
                      );

                      try {
                        final saved = await controller.saveDevice(device);
                        if (!mounted) {
                          return;
                        }
                        if (widget.deviceId == null &&
                            widget.customerId != null) {
                          router.go(_customerRoute(widget.customerId!));
                          return;
                        }
                        router.go('/devices/${saved.id}');
                      } on AppException catch (error) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(error.message)),
                        );
                      }
                    },
              icon: state.isSaving
                  ? const SizedBox.shrink()
                  : const Icon(Icons.save_outlined),
              label: Text(state.isSaving ? 'Kaydediliyor...' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<CustomerModel>> _loadCustomers() async {
    final repository = ref.read(customerRepositoryProvider);
    final response = await repository.listCustomers(
      page: 1,
      pageSize: 250,
      search: '',
      isActive: null,
      city: '',
      district: '',
    );
    return response.items;
  }

  void _hydrateDevice(CustomerDeviceModel device) {
    _brandController.text = device.brand ?? '';
    _modelController.text = device.model ?? '';
    _serialNumberController.text = device.serialNumber ?? '';
    _qrCodeController.text = device.qrCode ?? '';
    _membraneTypeController.text = device.membraneType ?? '';
    _installationDateController.text = _formatDate(device.installationDate);
    _lastMaintenanceDateController.text = _formatDate(
      device.lastMaintenanceDate,
    );
    _nextMaintenanceDateController.text = _formatDate(
      device.nextMaintenanceDate,
    );
    _descriptionController.text = device.description ?? '';
    _selectedCustomerId = device.customerId ?? _selectedCustomerId;
    _selectedDeviceType = device.deviceType;
    _selectedPumpType = device.pumpType;
    _isActive = device.isActive;
    _hydrated = true;
    setState(() {});
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _customerRoute(String customerId) {
    switch (widget.role) {
      case AppRole.manager:
        return '/manager/customers/$customerId';
      case AppRole.secretary:
        return '/secretary/customers/$customerId';
      case AppRole.technician:
        return '/technician/customers/$customerId';
      default:
        return '/manager/customers/$customerId';
    }
  }

  String _dashboardFallbackRoute() {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/admin-dashboard';
      case AppRole.secretary:
        return '/secretary-dashboard';
      case AppRole.technician:
        return '/technician-dashboard';
    }
  }

  DateTime? _parseDate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    final parts = text.split(RegExp(r'[./-]'));
    if (parts.length != 3) {
      return null;
    }

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) {
      return null;
    }

    if (parts[0].length == 4) {
      return DateTime(first, second, third);
    }

    return DateTime(third, second, first);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day.$month.$year';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
