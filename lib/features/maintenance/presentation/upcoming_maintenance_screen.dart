import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../../core/services/supabase_client_provider.dart';
import '../data/maintenance_repository.dart';
import '../../settings/data/company_app_settings.dart';

class UpcomingMaintenanceScreen extends ConsumerStatefulWidget {
  const UpcomingMaintenanceScreen({
    required this.role,
    this.assignedOnly = false,
    super.key,
  });

  final AppRole role;
  final bool assignedOnly;

  @override
  ConsumerState<UpcomingMaintenanceScreen> createState() =>
      _UpcomingMaintenanceScreenState();
}

class _UpcomingMaintenanceScreenState
    extends ConsumerState<UpcomingMaintenanceScreen> {
  bool _loading = true;
  String? _error;
  List<MaintenanceReminder> _items = const [];
  String _customerState = 'active';
  String _dateState = 'all';
  String _search = '';
  CompanyAppSettings _appSettings = const CompanyAppSettings(companyId: '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository =
          MaintenanceRepository(ref.read(supabaseClientProvider));
      final appSettings = await ref.read(companyAppSettingsProvider.future);
      final result = widget.assignedOnly
          ? await repository.getAssignedToCurrentUser()
          : await repository.getUpcoming(
              days: appSettings.maintenanceReminderDays,
            );
      if (!mounted) return;
      setState(() {
        _appSettings = appSettings;
        _items = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<MaintenanceReminder> get _filteredItems {
    final query = _search.trim().toLowerCase();
    Iterable<MaintenanceReminder> source = _items;

    if (_appSettings.onlyLatestProductMaintenance) {
      final latest = <String, MaintenanceReminder>{};
      for (final item in source) {
        final key = '${item.customerId}|${item.productName.trim().toLowerCase()}';
        final current = latest[key];
        if (current == null || item.performedAt.isAfter(current.performedAt)) {
          latest[key] = item;
        }
      }
      source = latest.values;
    }

    return source.where((item) {
      final customerMatches = switch (_customerState) {
        'active' => item.isCustomerActive,
        'passive' => !item.isCustomerActive,
        _ => true,
      };
      final dateMatches = switch (_dateState) {
        'overdue' => item.daysRemaining < 0,
        'today' => item.daysRemaining == 0,
        'upcoming' => item.daysRemaining > 0,
        _ => true,
      };
      final overdueAllowed =
          _appSettings.showOverdueMaintenances || item.daysRemaining >= 0;
      final productAllowed = !_appSettings.hideProductsWithoutMaintenance ||
          item.maintenanceMonths > 0;
      final textMatches = query.isEmpty ||
          item.customerName.toLowerCase().contains(query) ||
          item.phone.toLowerCase().contains(query) ||
          item.productName.toLowerCase().contains(query) ||
          item.address.toLowerCase().contains(query);
      return customerMatches &&
          dateMatches &&
          overdueAllowed &&
          productAllowed &&
          textMatches;
    }).toList(growable: false);
  }

  Future<void> _sendWhatsApp(MaintenanceReminder item) async {
    final digits = item.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final international =
        digits.startsWith('0') ? '90${digits.substring(1)}' : digits;
    final message = Uri.encodeComponent(
      item.daysRemaining < 0
          ? 'Merhaba ${item.customerName}, ${item.productName} bakım tarihiniz ${item.daysRemaining.abs()} gün geçti. Uygun olduğunuz günü bize yazabilirsiniz.'
          : 'Merhaba ${item.customerName}, ${item.productName} bakım zamanınız yaklaştı. Uygun olduğunuz günü bize yazabilirsiniz.',
    );
    final uri = Uri.parse('https://wa.me/$international?text=$message');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp açılamadı.')),
      );
    }
  }

  Future<void> _setMaintenanceFollowUp(MaintenanceReminder item) async {
    final currentMarkers = (item.notes ?? '')
        .split('\n')
        .where((line) => line.trim().startsWith('Bakım Takibi:'))
        .map((line) => line.trim().substring('Bakım Takibi:'.length).trim())
        .toList(growable: false);
    final currentMarker = currentMarkers.isEmpty ? '' : currentMarkers.first;
    final noteController = TextEditingController(text: currentMarker);
    bool clearNote = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${item.customerName} • Bakım Takip Notu'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notu sekreter serbestçe yazar. Müşteri bakım listesinde kalır; not sadece takip durumunu açıklar.',
                  style: TextStyle(color: Color(0xFF718096)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 3,
                  maxLines: 5,
                  enabled: !clearNote,
                  decoration: const InputDecoration(
                    labelText: 'Takip notu',
                    hintText: 'Örn: Müşteri ekimde tekrar aranacak / başka yerde yaptırmış / şu an istemiyor...',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: clearNote,
                  onChanged: (value) => setDialogState(() => clearNote = value ?? false),
                  title: const Text('Takip notunu temizle / tekrar aktif takibe al'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (saved != true) {
      noteController.dispose();
      return;
    }

    final text = clearNote ? '' : noteController.text.trim();
    noteController.dispose();
    try {
      await MaintenanceRepository(ref.read(supabaseClientProvider)).setMaintenanceFollowUpNote(
        recordId: item.id,
        currentNotes: item.notes,
        followUpLabel: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.isEmpty ? 'Bakım tekrar aktif takibe alındı.' : 'Bakım takip notu kaydedildi.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Takip notu kaydedilemedi: $error')));
    }
  }

  void _resetFilters() {
    setState(() {
      _customerState = 'active';
      _dateState = 'all';
      _search = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd.MM.yyyy', 'tr_TR');
    final items = _filteredItems;
    final overdueCount = items.where((e) => e.daysRemaining < 0).length;
    final todayCount = items.where((e) => e.daysRemaining == 0).length;
    final upcomingCount = items.where((e) => e.daysRemaining > 0).length;
    return ManagementShell(
      role: widget.role,
      title: widget.assignedOnly ? 'Bana Atanan Bakımlar' : 'Bakımı Yaklaşanlar',
      subtitle: 'Yaklaşan bakım müşterilerini takip edin ve tek tıkla iletişime geçin.',
      actions: [IconButton(tooltip: 'Yenile', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Bakım kayıtları yüklenemedi.\n$_error', textAlign: TextAlign.center))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _MaintenanceStat(label: 'Yaklaşan', value: upcomingCount, icon: Icons.notifications_active_outlined, tone: const Color(0xFFFFA726))),
                      const SizedBox(width: 12),
                      Expanded(child: _MaintenanceStat(label: 'Bugün', value: todayCount, icon: Icons.today_outlined, tone: const Color(0xFF3D8BFF))),
                      const SizedBox(width: 12),
                      Expanded(child: _MaintenanceStat(label: 'Geciken', value: overdueCount, icon: Icons.warning_amber_rounded, tone: const Color(0xFFE75252))),
                      const SizedBox(width: 12),
                      Expanded(child: _MaintenanceStat(label: 'Toplam Listede', value: items.length, icon: Icons.fact_check_outlined, tone: const Color(0xFF16A77B))),
                    ]),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
                      child: Column(children: [
                        Row(children: [Expanded(child: TextField(onChanged: (v) => setState(() => _search = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Müşteri, telefon, adres veya ürün ara'))), const SizedBox(width: 10), PopupMenuButton<String>(tooltip: 'Filtreler', icon: const Icon(Icons.filter_alt_outlined), onSelected: (value) { if (value.startsWith('customer:')) setState(() => _customerState = value.split(':').last); if (value.startsWith('date:')) setState(() => _dateState = value.split(':').last); }, itemBuilder: (_) => [const PopupMenuItem(enabled: false, child: Text('Müşteri')), CheckedPopupMenuItem(value: 'customer:active', checked: _customerState == 'active', child: const Text('Aktif müşteriler')), CheckedPopupMenuItem(value: 'customer:all', checked: _customerState == 'all', child: const Text('Tümü')), const PopupMenuDivider(), const PopupMenuItem(enabled: false, child: Text('Bakım zamanı')), CheckedPopupMenuItem(value: 'date:all', checked: _dateState == 'all', child: const Text('Tümü')), CheckedPopupMenuItem(value: 'date:overdue', checked: _dateState == 'overdue', child: const Text('Gecikenler')), CheckedPopupMenuItem(value: 'date:today', checked: _dateState == 'today', child: const Text('Bugün')), CheckedPopupMenuItem(value: 'date:upcoming', checked: _dateState == 'upcoming', child: const Text('Yaklaşanlar'))]), const SizedBox(width: 6), OutlinedButton.icon(onPressed: _resetFilters, icon: const Icon(Icons.refresh), label: const Text('Temizle'))]),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerLeft, child: Text('Yaklaşan bakım aralığı: ${_appSettings.maintenanceReminderDays} gün • ${items.length} kayıt', style: const TextStyle(color: Color(0xFF728197), fontSize: 12))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    if (items.isEmpty)
                      Container(height: 330, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircleAvatar(radius: 32, backgroundColor: Color(0xFFFFF3DE), child: Icon(Icons.notifications_none_rounded, color: Color(0xFFFFA726), size: 32)), SizedBox(height: 14), Text('Şu an takip edilecek bakım yok', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), SizedBox(height: 5), Text('Filtreleri değiştirdiğinizde veya bakım tarihi yaklaştığında kayıtlar burada görünür.', style: TextStyle(color: Color(0xFF7B8A9E))) ]))
                    else
                      Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))),
                        child: Column(children: [
                          const Padding(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.notifications_active_outlined, color: Color(0xFF0AAEC0)), SizedBox(width: 8), Text('Bakım Takip Listesi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))])),
                          const Divider(height: 1),
                          ...items.map((item) {
                            final overdue = item.daysRemaining < 0;
                            final status = overdue ? '${item.daysRemaining.abs()} gün gecikti' : item.daysRemaining == 0 ? 'Bugün' : '${item.daysRemaining} gün kaldı';
                            final followUpMarkers = (item.notes ?? '')
                                .split('\n')
                                .where((line) => line.trim().startsWith('Bakım Takibi:'))
                                .map((line) => line.trim().substring('Bakım Takibi:'.length).trim())
                                .toList(growable: false);
                            final followUpMarker = followUpMarkers.isEmpty ? null : followUpMarkers.first;
                            return Column(children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: overdue ? const Color(0xFFFFE8E8) : const Color(0xFFFFF3DE),
                                  child: Icon(overdue ? Icons.warning_amber_rounded : Icons.notifications_active_outlined, color: overdue ? const Color(0xFFE75252) : const Color(0xFFFF9E1B)),
                                ),
                                title: Row(children: [
                                  Flexible(child: Text(item.customerName, style: const TextStyle(fontWeight: FontWeight.w900))),
                                  if (followUpMarker != null && followUpMarker.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFFFF3DE), borderRadius: BorderRadius.circular(8)),
                                      child: Text('Takip pasif • $followUpMarker', style: const TextStyle(fontSize: 11, color: Color(0xFFB66A00), fontWeight: FontWeight.w800)),
                                    ),
                                  ],
                                ]),
                                subtitle: Text('${item.productName} • ${date.format(item.nextMaintenanceDate)} • $status\n${item.phone}${item.address.isNotEmpty ? ' • ${item.address}' : ''}'),
                                isThreeLine: true,
                                trailing: Wrap(spacing: 6, children: [
                                  OutlinedButton.icon(
                                    onPressed: () { final prefix = widget.role == AppRole.technician ? '/technician' : widget.role == AppRole.secretary ? '/secretary' : '/manager'; context.go('$prefix/customers/${item.customerId}'); },
                                    icon: const Icon(Icons.badge_outlined), label: const Text('Müşteri'),
                                  ),
                                  if (widget.role != AppRole.technician)
                                    OutlinedButton.icon(
                                      onPressed: () => _setMaintenanceFollowUp(item),
                                      icon: const Icon(Icons.edit_note_outlined), label: const Text('Takip Notu'),
                                    ),
                                  if (widget.role != AppRole.technician)
                                    FilledButton.tonalIcon(
                                      onPressed: () { final prefix = widget.role == AppRole.secretary ? '/secretary' : '/manager'; context.go('$prefix/service-requests/new/${item.customerId}'); },
                                      icon: const Icon(Icons.add_task_outlined), label: const Text('Servis Aç'),
                                    ),
                                  FilledButton.icon(
                                    onPressed: item.phone.isEmpty ? null : () => _sendWhatsApp(item),
                                    icon: const Icon(Icons.chat_outlined), label: const Text('WhatsApp'),
                                  ),
                                ]),
                              ),
                              const Divider(height: 1),
                            ]);
                          }),
                        ]),
                      ),
                  ]),
                ),
    );
  }

}

class _MaintenanceStat extends StatelessWidget {
  const _MaintenanceStat({required this.label, required this.value, required this.icon, required this.tone});
  final String label; final int value; final IconData icon; final Color tone;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E8F0))), child: Row(children: [CircleAvatar(radius: 23, backgroundColor: tone.withOpacity(0.12), child: Icon(icon, color: tone)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF718096), fontSize: 12)), const SizedBox(height: 3), Text('$value', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35)))]) ]));
}

class _CompactFilterBar extends StatelessWidget {
  const _CompactFilterBar({
    required this.visibleCount,
    required this.totalCount,
    required this.customerState,
    required this.dateState,
    required this.search,
    required this.onSearchChanged,
    required this.onCustomerStateChanged,
    required this.onDateStateChanged,
    required this.onReset,
  });

  final int visibleCount;
  final int totalCount;
  final String customerState;
  final String dateState;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCustomerStateChanged;
  final ValueChanged<String> onDateStateChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Müşteri, telefon veya ürün ara',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Filtreler',
            icon: Badge(
              isLabelVisible: customerState != 'active' ||
                  dateState != 'all' ||
                  search.isNotEmpty,
              child: const Icon(Icons.filter_list),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(enabled: false, child: Text('Müşteri durumu')),
              CheckedPopupMenuItem(
                value: 'customer:active',
                checked: customerState == 'active',
                child: const Text('Yalnızca aktif müşteriler'),
              ),
              CheckedPopupMenuItem(
                value: 'customer:passive',
                checked: customerState == 'passive',
                child: const Text('Yalnızca pasif müşteriler'),
              ),
              CheckedPopupMenuItem(
                value: 'customer:all',
                checked: customerState == 'all',
                child: const Text('Aktif ve pasif'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Bakım durumu')),
              CheckedPopupMenuItem(
                value: 'date:all',
                checked: dateState == 'all',
                child: const Text('Tümü'),
              ),
              CheckedPopupMenuItem(
                value: 'date:overdue',
                checked: dateState == 'overdue',
                child: const Text('Gecikenler'),
              ),
              CheckedPopupMenuItem(
                value: 'date:today',
                checked: dateState == 'today',
                child: const Text('Bugün'),
              ),
              CheckedPopupMenuItem(
                value: 'date:upcoming',
                checked: dateState == 'upcoming',
                child: const Text('Yaklaşanlar'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.restart_alt),
                  title: Text('Filtreleri sıfırla'),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'reset') {
                onReset();
              } else if (value.startsWith('customer:')) {
                onCustomerStateChanged(value.split(':').last);
              } else if (value.startsWith('date:')) {
                onDateStateChanged(value.split(':').last);
              }
            },
          ),
          const SizedBox(width: 6),
          Text('$visibleCount/$totalCount'),
        ],
      ),
    );
  }
}
