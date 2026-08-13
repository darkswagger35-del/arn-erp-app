import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/widgets/arn_app_bar.dart';
import '../../data/models/customer_device_model.dart';
import '../controllers/device_controller.dart';
import '../providers/device_providers.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.role,
    required this.deviceId,
  });

  final AppRole role;
  final String deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  bool get _canDeleteDevices {
    return widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        widget.role.canDeleteDevices;
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceDetailProvider(widget.deviceId));
    final deviceState = ref.watch(deviceControllerProvider);
    final controller = ref.read(deviceControllerProvider.notifier);

    return Scaffold(
      appBar: ArnAppBar(
        title: 'Cihaz Detayı',
        role: widget.role,
        fallbackRoute: _dashboardFallbackRoute(),
        actions: [
          if (widget.role.canEditDevices)
            IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: deviceState.isSaving
                  ? null
                  : () => context.go('/devices/${widget.deviceId}/edit'),
            ),
        ],
      ),
      body: deviceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Cihaz yüklenemedi. ${error.toString()}')),
        data: (device) {
          if (device == null) {
            return const Center(child: Text('Cihaz bulunamadı.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.customerName?.isNotEmpty == true
                            ? device.customerName!
                            : 'Müşteri',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                        label: 'Müşteri Telefonu',
                        value: device.customerPhone ?? '-',
                      ),
                      _InfoRow(
                        label: 'Müşteri Adresi',
                        value: device.customerAddress ?? '-',
                      ),
                      _InfoRow(label: 'Marka', value: device.brand ?? '-'),
                      _InfoRow(label: 'Model', value: device.model ?? '-'),
                      _InfoRow(
                        label: 'Cihaz Tipi',
                        value: device.deviceTypeLabel,
                      ),
                      _InfoRow(
                        label: 'Pompa Tipi',
                        value: device.pumpTypeLabel,
                      ),
                      _InfoRow(
                        label: 'Seri Numarası',
                        value: device.serialNumber ?? '-',
                      ),
                      _InfoRow(label: 'QR Kodu', value: device.qrCode ?? '-'),
                      _InfoRow(
                        label: 'Membran Tipi',
                        value: device.membraneType ?? '-',
                      ),
                      _InfoRow(
                        label: 'Montaj Tarihi',
                        value: _formatDate(device.installationDate),
                      ),
                      _InfoRow(
                        label: 'Son Bakım Tarihi',
                        value: _formatDate(device.lastMaintenanceDate),
                      ),
                      _InfoRow(
                        label: 'Sonraki Bakım Tarihi',
                        value: _formatDate(device.nextMaintenanceDate),
                      ),
                      _InfoRow(
                        label: 'Açıklama',
                        value: device.description ?? '-',
                      ),
                      _InfoRow(
                        label: 'Durum',
                        value: device.isActive ? 'Aktif' : 'Pasif',
                      ),
                      _InfoRow(
                        label: 'Oluşturulma Tarihi',
                        value: _formatDateTime(device.createdAt),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: device.customerId == null
                        ? null
                        : () => context.go(_customerRoute(device.customerId!)),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('Müşteri Detayı'),
                  ),
                  ElevatedButton.icon(
                    onPressed: device.qrCode == null || device.qrCode!.isEmpty
                        ? null
                        : () {
                            final messenger = ScaffoldMessenger.of(context);
                            Clipboard.setData(
                              ClipboardData(text: device.qrCode!),
                            ).then((_) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('QR kod kopyalandı.'),
                                ),
                              );
                            });
                          },
                    icon: const Icon(Icons.qr_code_outlined),
                    label: const Text('QR Kopyala'),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        device.serialNumber == null ||
                            device.serialNumber!.isEmpty
                        ? null
                        : () {
                            final messenger = ScaffoldMessenger.of(context);
                            Clipboard.setData(
                              ClipboardData(text: device.serialNumber!),
                            ).then((_) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Seri numarası kopyalandı.'),
                                ),
                              );
                            });
                          },
                    icon: const Icon(Icons.confirmation_number_outlined),
                    label: const Text('Seri Kopyala'),
                  ),
                  if (widget.role.canChangeDeviceStatus)
                    ElevatedButton.icon(
                      onPressed: deviceState.isSaving
                          ? null
                          : () => _toggleStatus(controller, device),
                      icon: const Icon(Icons.toggle_on_outlined),
                      label: Text(device.isActive ? 'Pasif Yap' : 'Aktif Yap'),
                    ),
                  if (_canDeleteDevices)
                    ElevatedButton.icon(
                      onPressed: deviceState.isSaving
                          ? null
                          : () => _confirmDelete(controller, device),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Sil'),
                    ),
                  if (widget.role.canEditDevices)
                    ElevatedButton.icon(
                      onPressed: deviceState.isSaving
                          ? null
                          : () =>
                                context.go('/devices/${widget.deviceId}/edit'),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Düzenle'),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _toggleStatus(DeviceController controller, CustomerDeviceModel device) {
    final messenger = ScaffoldMessenger.of(context);
    controller
        .changeDeviceStatus(device.id!, !device.isActive)
        .then((_) {
          if (!mounted) return;
          ref.invalidate(deviceDetailProvider(widget.deviceId));
          messenger.showSnackBar(
            const SnackBar(content: Text('Cihaz durumu güncellendi.')),
          );
        })
        .catchError((Object error) {
          final message = error is AppException
              ? error.message
              : 'Cihaz durumu güncellenemedi.';
          messenger.showSnackBar(SnackBar(content: Text(message)));
        });
  }

  void _confirmDelete(DeviceController controller, CustomerDeviceModel device) {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cihazı sil'),
        content: const Text('Bu cihazı silmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true) {
        return;
      }

      controller
          .softDeleteDevice(device.id!)
          .then((_) {
            if (!mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('Cihaz silindi.')),
            );
            router.go('/devices');
          })
          .catchError((Object error) {
            final message = error is AppException
                ? error.message
                : 'Cihaz silinemedi.';
            messenger.showSnackBar(SnackBar(content: Text(message)));
          });
    });
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

  String _customerRoute(String customerId) {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/manager/customers/$customerId';
      case AppRole.secretary:
        return '/secretary/customers/$customerId';
      case AppRole.technician:
        return '/technician/customers/$customerId';
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day.$month.$year';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label: $value'),
    );
  }
}
