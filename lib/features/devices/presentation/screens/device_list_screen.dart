import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/app_role.dart';
import '../../../../core/widgets/arn_app_bar.dart';
import '../../data/models/customer_device_model.dart';
import '../controllers/device_controller.dart';
import '../providers/device_providers.dart';

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  final _searchController = TextEditingController();
  bool _initialized = false;

  bool get _canDeleteDevices {
    return widget.role == AppRole.admin ||
        widget.role == AppRole.manager ||
        widget.role.canDeleteDevices;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(deviceControllerProvider.notifier).loadDevices();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceControllerProvider);
    final controller = ref.read(deviceControllerProvider.notifier);

    if (_searchController.text != state.search) {
      _searchController.value = _searchController.value.copyWith(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
        composing: TextRange.empty,
      );
    }

    return Scaffold(
      appBar: ArnAppBar(
        title: 'Cihazlar',
        role: widget.role,
        fallbackRoute: _dashboardFallbackRoute(),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: controller.refresh,
          ),
        ],
      ),
      floatingActionButton: widget.role.canEditDevices
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/devices/new'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Cihaz'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Ara',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: controller.updateSearch,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(
                          'device-type-${state.deviceType ?? 'all'}',
                        ),
                        initialValue: state.deviceType,
                        decoration: const InputDecoration(
                          labelText: 'Cihaz Tipi',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tümü'),
                          ),
                          ...DeviceType.values.map(
                            (value) => DropdownMenuItem<String?>(
                              value: value.value,
                              child: Text(value.label),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            controller.updateFilters(deviceType: value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('pump-type-${state.pumpType ?? 'all'}'),
                        initialValue: state.pumpType,
                        decoration: const InputDecoration(
                          labelText: 'Pompa Tipi',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tümü'),
                          ),
                          ...PumpType.values.map(
                            (value) => DropdownMenuItem<String?>(
                              value: value.value,
                              child: Text(value.label),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            controller.updateFilters(pumpType: value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool?>(
                  key: ValueKey(
                    'is-active-${state.isActive?.toString() ?? 'all'}',
                  ),
                  initialValue: state.isActive,
                  decoration: const InputDecoration(labelText: 'Durum'),
                  items: const [
                    DropdownMenuItem<bool?>(value: null, child: Text('Tümü')),
                    DropdownMenuItem<bool?>(value: true, child: Text('Aktif')),
                    DropdownMenuItem<bool?>(value: false, child: Text('Pasif')),
                  ],
                  onChanged: (value) =>
                      controller.updateFilters(isActive: value),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, state, controller)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DeviceState state,
    DeviceController controller,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: controller.refresh,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.items.isEmpty) {
      return const Center(child: Text('Kayıt bulunamadı.'));
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: state.isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton.icon(
                        onPressed: controller.loadMoreDevices,
                        icon: const Icon(Icons.more_horiz),
                        label: const Text('Daha Fazla Yükle'),
                      ),
              ),
            );
          }

          final device = state.items[index];
          return Card(
            child: ListTile(
              onTap: () => context.go('/devices/${device.id}'),
              title: Text(
                device.customerName?.trim().isNotEmpty == true
                    ? device.customerName!
                    : 'Müşteri',
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [
                    _brandModelText(device),
                    '${device.deviceTypeLabel} • ${device.pumpTypeLabel}',
                    'Seri: ${device.serialNumber ?? '-'}',
                    'Sonraki bakım: ${_formatDate(device.nextMaintenanceDate)}',
                    'Durum: ${device.isActive ? 'Aktif' : 'Pasif'}',
                  ].join('\n'),
                ),
              ),
              isThreeLine: true,
              trailing: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Detay',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => context.go('/devices/${device.id}'),
                  ),
                  if (widget.role.canEditDevices)
                    IconButton(
                      tooltip: 'Düzenle',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => context.go('/devices/${device.id}/edit'),
                    ),
                  if (widget.role.canChangeDeviceStatus)
                    IconButton(
                      tooltip: device.isActive ? 'Pasif Yap' : 'Aktif Yap',
                      icon: const Icon(Icons.toggle_on_outlined),
                      onPressed: state.isSaving
                          ? null
                          : () async {
                              try {
                                await controller.changeDeviceStatus(
                                  device.id!,
                                  !device.isActive,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cihaz durumu güncellenemedi.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                  if (_canDeleteDevices)
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: state.isSaving
                          ? null
                          : () => _confirmDelete(
                              context,
                              controller,
                              device,
                              state.isSaving,
                            ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

  void _confirmDelete(
    BuildContext context,
    DeviceController controller,
    CustomerDeviceModel device,
    bool isSaving,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cihazı sil'),
          content: const Text('Bu cihazı silmek istediğinize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      Navigator.of(dialogContext).pop();
                      try {
                        await controller.softDeleteDevice(device.id!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cihaz silindi.')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cihaz silinemedi.')),
                          );
                        }
                      }
                    },
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
  }

  String _brandModelText(CustomerDeviceModel device) {
    final brand = device.brand?.trim();
    final model = device.model?.trim();
    if ((brand == null || brand.isEmpty) && (model == null || model.isEmpty)) {
      return '-';
    }
    return [
      brand,
      model,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' / ');
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
}
