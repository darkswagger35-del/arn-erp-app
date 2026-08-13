import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../service_requests/data/models/service_request_model.dart';
import '../data/company_app_settings.dart';
import '../data/settings_control_center_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _backupBusy = false;
  bool _historyBusy = false;
  String? _backupError;
  String _selectedPanelRole = 'admin';

  late CompanyAppSettings _settings;
  List<CompanyBackupRecord> _backups = const [];
  List<SettingsAuditEntry> _audit = const [];

  final _maintenanceDaysController = TextEditingController();
  final _initialStockController = TextEditingController();
  final _onMyWayController = TextEditingController();
  final _appointmentController = TextEditingController();
  final _completedController = TextEditingController();

  final _permissionsKey = GlobalKey();
  final _serviceKey = GlobalKey();
  final _customerKey = GlobalKey();
  final _stockKey = GlobalKey();
  final _panelKey = GlobalKey();
  final _backupKey = GlobalKey();
  final _securityKey = GlobalKey();
  final _dataKey = GlobalKey();

  static const _supportedServiceTypes = <ServiceRequestType>[
    ServiceRequestType.newInstallation,
    ServiceRequestType.filterChange,
    ServiceRequestType.fault,
    ServiceRequestType.other,
  ];

  static const _permissionRows = <_PermissionRow>[
    _PermissionRow('Müşteri kartını görüntüle', 'secretary_view_customers', 'technician_view_customers'),
    _PermissionRow('Müşteri bilgilerini düzenle', 'secretary_edit_customers', 'technician_edit_customers'),
    _PermissionRow('Yeni servis talebi aç', 'secretary_create_service', 'technician_create_service'),
    _PermissionRow('Açık servisi düzenle', 'secretary_edit_service', 'technician_edit_service'),
    _PermissionRow('Tamamlanan servisi düzenle', 'secretary_edit_completed_service', 'technician_edit_completed_service'),
    _PermissionRow('Ürün / fiyatları gör', 'secretary_view_prices', 'technician_view_prices'),
    _PermissionRow('Tahsilatları gör', 'secretary_view_payments', 'technician_view_payments'),
    _PermissionRow('Stok bilgilerini gör', 'secretary_view_stock', 'technician_view_stock'),
    _PermissionRow('Excel içeri / dışarı aktar', 'secretary_excel_transfer', 'technician_excel_transfer'),
  ];

  static const _panelOptions = <String, List<_PanelOption>>{
    'admin': [
      _PanelOption('Özet kartları', 'summary'),
      _PanelOption('Son servis talepleri', 'recent_services'),
      _PanelOption('Bugünkü iş programı', 'today_schedule'),
      _PanelOption('Son tahsilatlar', 'recent_payments'),
      _PanelOption('Duyurular', 'announcements'),
    ],
    'secretary': [
      _PanelOption('Üst özet kartları', 'metrics'),
      _PanelOption('Bugünkü özet', 'today_summary'),
      _PanelOption('Son servis talepleri', 'recent_services'),
      _PanelOption('Hızlı işlemler', 'quick_actions'),
      _PanelOption('Yaklaşan bakımlar', 'upcoming_maintenance'),
    ],
    'technician': [
      _PanelOption('Üst özet kartları', 'metrics'),
      _PanelOption('Bugünkü iş listesi', 'today_jobs'),
      _PanelOption('Sıradaki iş', 'next_job'),
      _PanelOption('Günün rotası', 'route'),
      _PanelOption('Son tamamlanan işler', 'recent_completed'),
    ],
  };

  @override
  void initState() {
    super.initState();
    _settings = const CompanyAppSettings(companyId: '');
    _load();
  }

  @override
  void dispose() {
    _maintenanceDaysController.dispose();
    _initialStockController.dispose();
    _onMyWayController.dispose();
    _appointmentController.dispose();
    _completedController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final remote = await ref.read(companyAppSettingsProvider.future);
      if (!mounted) return;
      setState(() {
        _settings = remote;
        _maintenanceDaysController.text = remote.maintenanceReminderDays.toString();
        _initialStockController.text = remote.defaultInitialStock.toStringAsFixed(0);
        _onMyWayController.text = remote.onMyWayTemplate;
        _appointmentController.text = remote.appointmentTemplate;
        _completedController.text = remote.serviceCompletedTemplate;
        _loading = false;
      });
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Ayarlar yüklenemedi: $error', error: true);
    }
  }

  Future<void> _refreshControlCenter() async {
    if (_historyBusy) return;
    setState(() => _historyBusy = true);
    final repo = ref.read(settingsControlCenterRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.listBackups(),
        repo.loadAudit(),
      ]);
      if (!mounted) return;
      setState(() {
        _backups = results[0] as List<CompanyBackupRecord>;
        _audit = results[1] as List<SettingsAuditEntry>;
        _backupError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _backupError = 'Yedekleme altyapısı henüz kurulmamış olabilir. '
            '20260810_001_settings_control_center.sql migrationını uygulayın.';
      });
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  int _maintenanceDays() {
    final value = int.tryParse(_maintenanceDaysController.text.trim()) ?? 10;
    return value.clamp(1, 365).toInt();
  }

  double _initialStock() {
    final value = double.tryParse(
          _initialStockController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    return value < 0 ? 0 : value;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final supportedValues = _supportedServiceTypes.map((e) => e.value).toSet();
      var enabledTypes = _settings.enabledServiceTypes
          .where(supportedValues.contains)
          .toList(growable: false);
      if (enabledTypes.isEmpty) enabledTypes = ['other'];

      final next = _settings.copyWith(
        maintenanceReminderDays: _maintenanceDays(),
        defaultInitialStock: _initialStock(),
        onMyWayTemplate: _onMyWayController.text,
        appointmentTemplate: _appointmentController.text,
        serviceCompletedTemplate: _completedController.text,
        enabledServiceTypes: enabledTypes,
        allowTechnicianCustomerEdit:
            _settings.permission('technician_edit_customers', fallback: true),
        allowTechnicianHistoryEdit: _settings.permission(
          'technician_edit_completed_service',
        ),
      );
      await ref.read(companyAppSettingsRepositoryProvider).save(next);
      ref.invalidate(companyAppSettingsProvider);
      if (!mounted) return;
      setState(() => _settings = next);
      _showMessage('Kontrol merkezi ayarları kaydedildi.');
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Ayarlar kaydedilemedi: $error\nYeni ayar kolonları için Supabase migrationını uygulayın.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setPermission(String key, bool value) {
    final next = Map<String, bool>.from(_settings.permissions)..[key] = value;
    setState(() {
      _settings = _settings.copyWith(
        permissions: next,
        allowTechnicianCustomerEdit: key == 'technician_edit_customers'
            ? value
            : _settings.allowTechnicianCustomerEdit,
        allowTechnicianHistoryEdit: key == 'technician_edit_completed_service'
            ? value
            : _settings.allowTechnicianHistoryEdit,
      );
    });
  }

  void _setServiceRule(String key, bool value) {
    final next = Map<String, dynamic>.from(_settings.serviceRules)..[key] = value;
    setState(() => _settings = _settings.copyWith(serviceRules: next));
  }

  void _setCustomerRule(String key, bool value) {
    final next = Map<String, dynamic>.from(_settings.customerRules)..[key] = value;
    setState(() => _settings = _settings.copyWith(customerRules: next));
  }

  void _setBackupKeepCount(int value) {
    final next = Map<String, dynamic>.from(_settings.backupPolicy)
      ..['keep_count'] = value.clamp(1, 50);
    setState(() => _settings = _settings.copyWith(backupPolicy: next));
  }

  void _setPanelVisible(String role, String key, bool value) {
    final all = <String, dynamic>{};
    for (final entry in _settings.panelVisibility.entries) {
      all[entry.key] = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : entry.value;
    }
    final roleMap = Map<String, dynamic>.from(
      all[role] is Map ? all[role] as Map : const <String, dynamic>{},
    )..[key] = value;
    all[role] = roleMap;
    setState(() => _settings = _settings.copyWith(panelVisibility: all));
  }

  Future<void> _createBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      final repo = ref.read(settingsControlCenterRepositoryProvider);
      await repo.createBackup(label: 'Manuel yedek');
      if (!mounted) return;
      _showMessage('Tam işletme yedeği oluşturuldu.');
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Yedek oluşturulamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackupFile() async {
    if (_backupBusy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'ARN ERP yedek dosyasını seç',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map) throw const FormatException('Geçersiz yedek dosyası.');
      final root = Map<String, dynamic>.from(decoded);
      final snapshot = root['snapshot'];
      if (snapshot is! Map) {
        throw const FormatException('Yedek dosyasında snapshot bulunamadı.');
      }
      setState(() => _backupBusy = true);
      await ref.read(settingsControlCenterRepositoryProvider).importBackup(
            snapshot: Map<String, dynamic>.from(snapshot),
            counts: root['counts'] is Map
                ? Map<String, dynamic>.from(root['counts'] as Map)
                : const <String, dynamic>{},
            label: 'Dosyadan içe aktarıldı',
          );
      if (!mounted) return;
      _showMessage('Yedek dosyası sisteme alındı. İsterseniz şimdi güvenli geri yükleyebilirsiniz.');
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Yedek dosyası alınamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportBackup(CompanyBackupRecord backup) async {
    try {
      final fullBackup = backup.snapshot.isEmpty
          ? await ref.read(settingsControlCenterRepositoryProvider).loadBackup(backup.id)
          : backup;
      final stamp = DateFormat('yyyyMMdd_HHmm').format(fullBackup.createdAt.toLocal());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'ARN ERP yedeğini kaydet',
        fileName: 'ARN_ERP_YEDEK_$stamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) return;
      final payload = {
        'backup_id': fullBackup.id,
        'created_at': fullBackup.createdAt.toUtc().toIso8601String(),
        'counts': fullBackup.counts,
        'snapshot': fullBackup.snapshot,
      };
      await File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      if (!mounted) return;
      _showMessage('Yedek dosyası kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Yedek dosyası kaydedilemedi: $error', error: true);
    }
  }

  Future<void> _restoreBackup(CompanyBackupRecord backup) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Yedeği güvenli geri yükle'),
            content: Text(
              '${DateFormat('dd.MM.yyyy HH:mm').format(backup.createdAt.toLocal())} tarihli yedekten silinmiş / eksik kayıtlar geri getirilecek.\n\n'
              'Mevcut ve yedekten sonra oluşturulan yeni kayıtlar SİLİNMEZ. İşlem başlamadan önce sistem otomatik güvenlik yedeği alır.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Güvenli Geri Yükle'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _backupBusy) return;

    setState(() => _backupBusy = true);
    try {
      final result = await ref
          .read(settingsControlCenterRepositoryProvider)
          .restoreBackup(backup.id);
      if (!mounted) return;
      final restored = result['restored'];
      _showMessage('Geri yükleme tamamlandı. Kurtarılan kayıtlar: ${_restoredCount(restored)}');
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Geri yükleme başarısız: $error', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _deleteBackup(CompanyBackupRecord backup) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Yedeği sil'),
            content: const Text('Bu yedek geçmişten kaldırılacak. Devam edilsin mi?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(settingsControlCenterRepositoryProvider).deleteBackup(backup.id);
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Yedek silinemedi: $error', error: true);
    }
  }

  int _restoredCount(Object? raw) {
    if (raw is! Map) return 0;
    var total = 0;
    for (final value in raw.values) {
      if (value is num) total += value.toInt();
    }
    return total;
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB42318) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.admin,
      title: 'Ayarlar',
      subtitle: 'Programın çalışma şeklini, yetkileri ve veri güvenliğini yönetin.',
      dark: true,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading || _saving ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Yenile'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                _hero(),
                const SizedBox(height: 16),
                _quickNavigation(),
                const SizedBox(height: 18),
                KeyedSubtree(key: _permissionsKey, child: _permissionsSection()),
                KeyedSubtree(key: _serviceKey, child: _serviceSection()),
                KeyedSubtree(key: _customerKey, child: _customerSection()),
                KeyedSubtree(key: _stockKey, child: _stockPaymentSection()),
                KeyedSubtree(key: _panelKey, child: _panelSection()),
                KeyedSubtree(key: _backupKey, child: _backupSection()),
                KeyedSubtree(key: _securityKey, child: _securitySection()),
                KeyedSubtree(key: _dataKey, child: _dataSection()),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Tüm Ayarları Kaydet'),
                ),
              ],
            ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2234),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1B455F)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF55D6DE)),
                  SizedBox(width: 10),
                  Text(
                    'ARN ERP Kontrol Merkezi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              const Text(
                'Kod değiştirmeden kritik davranışları buradan açıp kapatın. Yönetici tam yetkilidir; sekreter ve tekniker izinları ayrı yönetilir.',
                style: TextStyle(color: Color(0xFFA8BECD)),
              ),
            ],
          );
          final status = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip(Icons.security_rounded, 'Rol bazlı yetki'),
              _statusChip(Icons.backup_rounded, '${_backups.length} yedek'),
              _statusChip(Icons.history_rounded, '${_audit.length} işlem'),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 14), status],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              status,
            ],
          );
        },
      ),
    );
  }

  Widget _statusChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF102E43),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF23506A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF55D6DE)),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(color: Color(0xFFD9E7EF), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _quickNavigation() {
    final items = [
      _NavCardData('Yetkiler', 'Sekreter / tekniker', Icons.admin_panel_settings_outlined, const Color(0xFF56D0D8), _permissionsKey),
      _NavCardData('Servis & Planlama', 'Akış ve zorunluluklar', Icons.event_note_outlined, const Color(0xFF6E8CFF), _serviceKey),
      _NavCardData('Müşteri & Bakım', 'Kayıt ve bakım kuralları', Icons.groups_2_outlined, const Color(0xFF66D29A), _customerKey),
      _NavCardData('Stok & Tahsilat', 'Stok ve ödeme davranışı', Icons.inventory_2_outlined, const Color(0xFFFFC15B), _stockKey),
      _NavCardData('Panel Ayarları', 'Rol bazlı görünürlük', Icons.dashboard_customize_outlined, const Color(0xFFB985FF), _panelKey),
      _NavCardData('Yedekleme', 'Yedek / geri yükleme', Icons.cloud_done_outlined, const Color(0xFF2DD4BF), _backupKey),
      _NavCardData('Güvenlik & Geçmiş', 'Kim ne yaptı?', Icons.shield_outlined, const Color(0xFFF48771), _securityKey),
      _NavCardData('Veri Yönetimi', 'Excel ve veri araçları', Icons.dataset_outlined, const Color(0xFF4EA1FF), _dataKey),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 1250
            ? 4
            : constraints.maxWidth >= 760
                ? 2
                : 1;
        final gap = 12.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((item) => SizedBox(width: width, child: _navCard(item)))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _navCard(_NavCardData item) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _scrollTo(item.key),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF0C2030),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF183F58)),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(item.icon, color: item.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(item.subtitle, style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF66859A)),
          ],
        ),
      ),
    );
  }

  Widget _permissionsSection() {
    return _ControlSection(
      title: 'Yetkiler',
      subtitle: 'Yönetici her zaman tam yetkili. Sekreter ve teknikerin kritik işlemlerini buradan yönetin.',
      icon: Icons.admin_panel_settings_outlined,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  children: _permissionRows
                      .map((row) => _mobilePermissionRow(row))
                      .toList(growable: false),
                );
              }
              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.8),
                  1: FlexColumnWidth(1.1),
                  2: FlexColumnWidth(1.1),
                  3: FlexColumnWidth(1.1),
                },
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFF1B3B50)),
                ),
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFF102A3D)),
                    children: [
                      _TableHead('İzin'),
                      _TableHead('Yönetici'),
                      _TableHead('Sekreter'),
                      _TableHead('Tekniker'),
                    ],
                  ),
                  ..._permissionRows.map(
                    (row) => TableRow(
                      children: [
                        _TableLabel(row.label),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(child: Icon(Icons.check_circle_rounded, color: Color(0xFF42D392))),
                        ),
                        Center(
                          child: Switch(
                            value: _settings.permission(row.secretaryKey),
                            onChanged: (value) => _setPermission(row.secretaryKey, value),
                          ),
                        ),
                        Center(
                          child: Switch(
                            value: _settings.permission(row.technicianKey),
                            onChanged: (value) => _setPermission(row.technicianKey, value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _infoBox(
            Icons.info_outline_rounded,
            'Yetki ayarları uygulama ekranlarını yönetir. Veritabanı RLS politikaları ayrıca rol bazlı güvenlik katmanı olarak çalışmaya devam eder.',
          ),
        ],
      ),
    );
  }

  Widget _mobilePermissionRow(_PermissionRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniSwitch(
                  'Sekreter',
                  _settings.permission(row.secretaryKey),
                  (value) => _setPermission(row.secretaryKey, value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniSwitch(
                  'Tekniker',
                  _settings.permission(row.technicianKey),
                  (value) => _setPermission(row.technicianKey, value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFFADC1CF)))),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _serviceSection() {
    return _ControlSection(
      title: 'Servis & Planlama',
      subtitle: 'Servis türleri, saatli randevu ve servis kapatma kuralları.',
      icon: Icons.event_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF102E43),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF23506A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: Color(0xFF55D6DE)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Servis Formu Tasarımcısı',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      Text('PDF form alanlarını, imzaları, özel alanları ve bölüm sırasını yönetin.',
                          style: TextStyle(color: Color(0xFFADC1CF), fontSize: 12)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/manager/service-form-designer'),
                  icon: const Icon(Icons.design_services_outlined),
                  label: const Text('Formu Düzenle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Aktif servis türleri', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _supportedServiceTypes.map((type) {
              final selected = _settings.enabledServiceTypes.contains(type.value);
              return FilterChip(
                selected: selected,
                label: Text(type.label),
                onSelected: (value) {
                  final next = _settings.enabledServiceTypes
                      .where((e) => _supportedServiceTypes.any((t) => t.value == e))
                      .toList();
                  if (value) {
                    if (!next.contains(type.value)) next.add(type.value);
                  } else if (next.length > 1) {
                    next.remove(type.value);
                  }
                  setState(() => _settings = _settings.copyWith(enabledServiceTypes: next));
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 14),
          _switchTile(
            'Saatli randevu kullanılabilsin',
            'Sekreter isterse gerçek saat seçer; seçmezse servis Gün İçinde kalır.',
            _settings.serviceRule('appointment_time_enabled', fallback: true),
            (v) => _setServiceRule('appointment_time_enabled', v),
          ),
          _switchTile(
            'Tamamlanan servis sonradan düzenlenebilsin',
            'Yetkisi olan kullanıcı servis içeriğini sonradan düzeltebilir.',
            _settings.serviceRule('completed_service_editable', fallback: true),
            (v) => _setServiceRule('completed_service_editable', v),
          ),
          _switchTile(
            'Tekniker kullanılan ürünleri değiştirebilsin',
            'Servis tamamlanırken ürün/adet düzenlenebilir.',
            _settings.serviceRule('technician_can_change_products', fallback: true),
            (v) => _setServiceRule('technician_can_change_products', v),
          ),
          _switchTile(
            'Tekniker fiyat değiştirebilsin',
            'Kapalı olduğunda planlanan / ürün fiyatı yönetici-sekreter kontrolünde kalır.',
            _settings.serviceRule('technician_can_change_price'),
            (v) => _setServiceRule('technician_can_change_price', v),
          ),
          _switchTile(
            'Tekniker tahsilat girebilsin',
            'Servis kapanışında ödeme bilgisi kaydedebilir.',
            _settings.serviceRule('technician_can_collect_payment', fallback: true),
            (v) => _setServiceRule('technician_can_collect_payment', v),
          ),
          const Divider(height: 26, color: Color(0xFF1B3B50)),
          const Text('Servis kapatma zorunlulukları', style: _sectionLabelStyle),
          _switchTile(
            'Yapılan işlem açıklaması zorunlu',
            'Boş açıklama ile servis tamamlanamaz.',
            _settings.serviceRule('require_work_description', fallback: true),
            (v) => _setServiceRule('require_work_description', v),
          ),
          _switchTile(
            'Filtre değişiminde ürün seçimi zorunlu',
            'Filtre değişimi ürünsüz kapatılamaz.',
            _settings.serviceRule('require_product_for_filter_change', fallback: true),
            (v) => _setServiceRule('require_product_for_filter_change', v),
          ),
          _switchTile(
            'Ödeme durumu zorunlu',
            'Tahsil edildi / açık hesap bilgisi servis kapanışında seçilir.',
            _settings.serviceRule('require_payment_status', fallback: true),
            (v) => _setServiceRule('require_payment_status', v),
          ),
          const Divider(height: 26, color: Color(0xFF1B3B50)),
          const Text('Hazır mesajlar', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          _darkTextField(
            controller: _onMyWayController,
            label: 'Tekniker – Geliyorum mesajı',
            helper: 'Kullanılabilir: {{musteri}}',
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 10),
          _darkTextField(
            controller: _appointmentController,
            label: 'Sekreter – Randevu mesajı',
            helper: '{{musteri}}, {{tarih}}, {{servis_turu}}, {{teknisyen}}',
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 10),
          _darkTextField(
            controller: _completedController,
            label: 'Servis tamamlandı mesajı',
            helper: '{{musteri}}, {{tutar}}',
            minLines: 2,
            maxLines: 4,
          ),
        ],
      ),
    );
  }

  Widget _customerSection() {
    return _ControlSection(
      title: 'Müşteri & Bakım',
      subtitle: 'Müşteri kaydı ve otomatik bakım takibinin temel kuralları.',
      icon: Icons.groups_2_outlined,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _darkTextField(
                      controller: _maintenanceDaysController,
                      label: 'Bakım kaç gün kala yaklaşan sayılır?',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _readOnlyInfo(
                      'Bakım hesabı',
                      _settings.calculateMaintenanceFromProduct
                          ? 'Ürünün bakım süresine göre otomatik'
                          : 'Manuel takip',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _switchTile(
            'Gecikmiş bakımları göster',
            'Tarihi geçmiş bakım kayıtları yaklaşan bakım listesinde görünür.',
            _settings.showOverdueMaintenances,
            (v) => setState(() => _settings = _settings.copyWith(showOverdueMaintenances: v)),
          ),
          _switchTile(
            'Bakım tarihini üründen otomatik hesapla',
            'Ürünün bakım ayı değişirse müşterinin sonraki bakım tarihi güncellenir.',
            _settings.calculateMaintenanceFromProduct,
            (v) => setState(() => _settings = _settings.copyWith(calculateMaintenanceFromProduct: v)),
          ),
          _switchTile(
            'Aynı telefonla mükerrer müşteriyi engelle',
            'Yeni kayıtta telefon numarası sistemde varsa mevcut müşteri gösterilir.',
            _settings.customerRule('duplicate_phone_check', fallback: true),
            (v) => _setCustomerRule('duplicate_phone_check', v),
          ),
          const Divider(height: 26, color: Color(0xFF1B3B50)),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Yeni müşteri kaydında zorunlu alanlar', style: _sectionLabelStyle),
          ),
          _switchTile('Telefon zorunlu', null, _settings.customerRule('phone_required', fallback: true), (v) => _setCustomerRule('phone_required', v)),
          _switchTile('Şehir zorunlu', null, _settings.customerRule('city_required', fallback: true), (v) => _setCustomerRule('city_required', v)),
          _switchTile('İlçe zorunlu', null, _settings.customerRule('district_required', fallback: true), (v) => _setCustomerRule('district_required', v)),
          _switchTile('Açık adres zorunlu', null, _settings.customerRule('address_required', fallback: true), (v) => _setCustomerRule('address_required', v)),
        ],
      ),
    );
  }

  Widget _stockPaymentSection() {
    const methods = <String, String>{
      'cash': 'Nakit',
      'card': 'Kredi Kartı',
      'transfer': 'Havale / EFT',
      'open_account': 'Açık Hesap',
    };
    return _ControlSection(
      title: 'Stok & Tahsilat',
      subtitle: 'Servis kapanınca stok ve tahsilatın nasıl davranacağını belirleyin.',
      icon: Icons.inventory_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _switchTile(
            'Servis tamamlanınca kullanılan ürün stoktan düşsün',
            null,
            _settings.autoDecreaseStockOnService,
            (v) => setState(() => _settings = _settings.copyWith(autoDecreaseStockOnService: v)),
          ),
          _switchTile(
            'Eksi stoğa izin ver',
            'Kapalı olduğunda yeterli stok yoksa işlem engellenebilir.',
            _settings.allowNegativeStock,
            (v) => setState(() => _settings = _settings.copyWith(allowNegativeStock: v)),
          ),
          _switchTile(
            'Kritik stok uyarılarını göster',
            null,
            _settings.criticalStockNotifications,
            (v) => setState(() => _settings = _settings.copyWith(criticalStockNotifications: v)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 290,
            child: _darkTextField(
              controller: _initialStockController,
              label: 'Yeni üründe varsayılan başlangıç stoğu',
              keyboardType: TextInputType.number,
            ),
          ),
          const Divider(height: 28, color: Color(0xFF1B3B50)),
          _switchTile(
            'Servis ödeme bilgisi olmadan tamamlanamasın',
            null,
            _settings.requirePaymentToCompleteService,
            (v) => setState(() => _settings = _settings.copyWith(requirePaymentToCompleteService: v)),
          ),
          _switchTile(
            'Kısmi ödemeye izin ver',
            null,
            _settings.allowPartialPayment,
            (v) => setState(() => _settings = _settings.copyWith(allowPartialPayment: v)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<String>(
              value: methods.containsKey(_settings.defaultPaymentMethod)
                  ? _settings.defaultPaymentMethod
                  : 'cash',
              dropdownColor: const Color(0xFF102A3D),
              style: const TextStyle(color: Colors.white),
              decoration: _darkInputDecoration('Varsayılan ödeme yöntemi'),
              items: methods.entries
                  .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _settings = _settings.copyWith(defaultPaymentMethod: value));
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: methods.entries.map((entry) {
              final enabled = _settings.enabledPaymentMethods.contains(entry.key);
              return FilterChip(
                selected: enabled,
                label: Text(entry.value),
                onSelected: (value) {
                  final next = List<String>.from(_settings.enabledPaymentMethods);
                  if (value) {
                    if (!next.contains(entry.key)) next.add(entry.key);
                  } else if (next.length > 1) {
                    next.remove(entry.key);
                  }
                  setState(() => _settings = _settings.copyWith(enabledPaymentMethods: next));
                },
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _panelSection() {
    const roles = <String, String>{
      'admin': 'Yönetici',
      'secretary': 'Sekreter',
      'technician': 'Tekniker',
    };
    final options = _panelOptions[_selectedPanelRole] ?? const <_PanelOption>[];
    return _ControlSection(
      title: 'Panel Ayarları',
      subtitle: 'Her rolün ana panelinde hangi bölümlerin görüneceğini seçin.',
      icon: Icons.dashboard_customize_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: roles.entries.map((entry) {
              return ChoiceChip(
                label: Text(entry.value),
                selected: _selectedPanelRole == entry.key,
                onSelected: (_) => setState(() => _selectedPanelRole = entry.key),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 14),
          ...options.map(
            (option) => _switchTile(
              option.label,
              option.key == 'announcements'
                  ? 'Duyurular varsayılan olarak kapalıdır.'
                  : null,
              _settings.panelVisible(_selectedPanelRole, option.key),
              (value) => _setPanelVisible(_selectedPanelRole, option.key, value),
            ),
          ),
          _infoBox(
            Icons.dashboard_outlined,
            'Bu seçimler kaydedildiğinde ilgili rolün ana panel görünümü değişir; temel menü yetkileri Yetkiler bölümünden yönetilir.',
          ),
        ],
      ),
    );
  }

  Widget _backupSection() {
    return _ControlSection(
      title: 'Yedekleme & Geri Yükleme',
      subtitle: 'Müşteri, servis, ürün, stok, tahsilat ve bakım verilerini güvenli kopyalayın.',
      icon: Icons.cloud_done_outlined,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _backupBusy || _backupError != null ? null : _importBackupFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Yedek Dosyası Al'),
          ),
          FilledButton.icon(
            onPressed: _backupBusy || _backupError != null ? null : _createBackup,
            icon: _backupBusy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.backup_rounded),
            label: const Text('Şimdi Yedek Al'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_backupError != null)
            _warningBox(_backupError!)
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final latest = _backups.isEmpty ? null : _backups.first;
                final cards = [
                  _backupMetric('Yedek Sayısı', '${_backups.length}', Icons.layers_outlined),
                  _backupMetric('Saklama', 'Son ${_settings.backupKeepCount}', Icons.inventory_outlined),
                  _backupMetric(
                    'Son Yedek',
                    latest == null
                        ? 'Henüz yok'
                        : DateFormat('dd.MM HH:mm').format(latest.createdAt.toLocal()),
                    Icons.schedule_rounded,
                  ),
                ];
                final count = constraints.maxWidth >= 760 ? 3 : 1;
                final gap = 10.0;
                final width = (constraints.maxWidth - gap * (count - 1)) / count;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
                );
              },
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final selector = DropdownButtonFormField<int>(
                  value: _settings.backupKeepCount,
                  dropdownColor: const Color(0xFF102A3D),
                  style: const TextStyle(color: Colors.white),
                  decoration: _darkInputDecoration('Saklanacak manuel yedek sayısı'),
                  items: const [5, 10, 14, 20, 30, 50]
                      .map((count) => DropdownMenuItem<int>(
                            value: count,
                            child: Text('Son $count yedek'),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) _setBackupKeepCount(value);
                  },
                );
                if (constraints.maxWidth < 720) return selector;
                return SizedBox(width: 340, child: selector);
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text('Yedek geçmişi', style: _sectionLabelStyle),
                ),
                IconButton(
                  tooltip: 'Yenile',
                  onPressed: _historyBusy ? null : _refreshControlCenter,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (_backups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Henüz yedek oluşturulmadı.', style: TextStyle(color: Color(0xFF8EA8B9))),
                ),
              )
            else
              ..._backups.take(8).map(_backupRow),
          ],
          const SizedBox(height: 10),
          _infoBox(
            Icons.shield_outlined,
            'Güvenli geri yükleme mevcut/yeni kayıtları silmez; yedekte olup sonradan silinmiş kayıtları geri getirir. Geri yüklemeden hemen önce otomatik güvenlik yedeği alınır. Auth şifreleri ve dosya storage içerikleri bu uygulama yedeğine dahil değildir.',
          ),
        ],
      ),
    );
  }

  Widget _backupMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF1B455F)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF52D3C5)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backupRow(CompanyBackupRecord backup) {
    String count(String key) => '${backup.counts[key] ?? 0}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(13),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                backup.label?.trim().isNotEmpty == true ? backup.label! : 'İşletme Yedeği',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                '${DateFormat('dd.MM.yyyy HH:mm').format(backup.createdAt.toLocal())} • '
                '${count('customers')} müşteri • ${count('services')} servis • '
                '${count('products')} ürün • ${count('payments')} tahsilat',
                style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'JSON indir',
                onPressed: () => _exportBackup(backup),
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                tooltip: 'Güvenli geri yükle',
                onPressed: _backupBusy ? null : () => _restoreBackup(backup),
                icon: const Icon(Icons.restore_rounded),
              ),
              IconButton(
                tooltip: 'Yedeği sil',
                onPressed: () => _deleteBackup(backup),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          );
          if (constraints.maxWidth < 650) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 8), actions],
            );
          }
          return Row(children: [Expanded(child: info), actions]);
        },
      ),
    );
  }

  Widget _securitySection() {
    return _ControlSection(
      title: 'Güvenlik & İşlem Geçmişi',
      subtitle: 'Fiyat, servis, stok, kullanıcı ve yedek gibi kritik işlemlerde kim ne yaptı görün.',
      icon: Icons.shield_outlined,
      trailing: IconButton(
        tooltip: 'Yenile',
        onPressed: _historyBusy ? null : _refreshControlCenter,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: _historyBusy && _audit.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          : _audit.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: Text('İşlem geçmişi bulunamadı.', style: TextStyle(color: Color(0xFF8EA8B9))),
                  ),
                )
              : Column(children: _audit.take(20).map(_auditRow).toList(growable: false)),
    );
  }

  Widget _auditRow(SettingsAuditEntry entry) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1B3B50))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF17364B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_auditIcon(entry.action), color: const Color(0xFF63D7DE), size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _auditLabel(entry),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.userName ?? 'Kullanıcı'} • ${entry.entityType}',
                  style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('dd.MM HH:mm').format(entry.createdAt.toLocal()),
            style: const TextStyle(color: Color(0xFF6F8A9D), fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _auditLabel(SettingsAuditEntry entry) {
    switch (entry.action) {
      case 'settings_updated':
        return 'Ayarlar değiştirildi';
      case 'backup_created':
        return 'Yeni sistem yedeği oluşturuldu';
      case 'backup_restored':
        return 'Yedekten kayıtlar geri getirildi';
      case 'create':
      case 'insert':
        return 'Yeni kayıt oluşturuldu';
      case 'update':
        return 'Kayıt güncellendi';
      case 'delete':
        return 'Kayıt silindi';
      default:
        return entry.action.replaceAll('_', ' ');
    }
  }

  IconData _auditIcon(String action) {
    if (action.contains('backup')) return Icons.backup_outlined;
    if (action.contains('delete')) return Icons.delete_outline_rounded;
    if (action.contains('update') || action.contains('settings')) return Icons.edit_note_rounded;
    if (action.contains('create') || action.contains('insert')) return Icons.add_circle_outline_rounded;
    return Icons.history_rounded;
  }

  Widget _dataSection() {
    return _ControlSection(
      title: 'Veri Yönetimi',
      subtitle: 'Excel aktarımı, veri dışa aktarma ve bakım araçlarına hızlı erişim.',
      icon: Icons.dataset_outlined,
      child: Column(
        children: [
          _actionTile(
            icon: Icons.table_view_rounded,
            title: 'Excel İçeri / Dışarı Aktar',
            subtitle: 'Müşteri ve eski işlem kayıtlarını Excel ile taşıyın.',
            actionLabel: 'Excel Aktarımını Aç',
            onTap: () => context.go('/manager/excel-transfer'),
          ),
          _actionTile(
            icon: Icons.inventory_2_outlined,
            title: 'Ürün ve Stok Kontrolü',
            subtitle: 'Ürünleri ve depo stoklarını kontrol edin.',
            actionLabel: 'Ürünlere Git',
            onTap: () => context.go('/manager/products'),
          ),
          _actionTile(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Servis Formları',
            subtitle: 'Tamamlanan servislerin PDF kayıtlarını görüntüleyin.',
            actionLabel: 'Formları Aç',
            onTap: () => context.go('/manager/service-documents'),
          ),
          const SizedBox(height: 8),
          _infoBox(
            Icons.info_outline_rounded,
            'Excel dışa aktarma günlük çalışma içindir; Yedekleme bölümü ise veri kaybına karşı sistem kopyası oluşturur. İkisi birbirinin yerine geçmez.',
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF173E55),
            child: Icon(icon, color: const Color(0xFF65D6DE)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _switchTile(
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12)),
    );
  }

  Widget _darkTextField({
    required TextEditingController controller,
    required String label,
    String? helper,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _darkInputDecoration(label).copyWith(
        helperText: helper,
        helperStyle: const TextStyle(color: Color(0xFF6F8A9D)),
      ),
    );
  }

  InputDecoration _darkInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF8EA8B9)),
      filled: true,
      fillColor: const Color(0xFF102A3D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF234A62)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF56D0D8), width: 1.4),
      ),
    );
  }

  Widget _readOnlyInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF102A3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF234A62)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, color: Color(0xFF56D0D8)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF8EA8B9), fontSize: 12)),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(IconData icon, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E3246),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1D536B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF63D7DE), size: 20),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFB7CCD8), fontSize: 12))),
        ],
      ),
    );
  }

  Widget _warningBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF42271D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8D4A2F)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB36B)),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFFFD5B0)))),
        ],
      ),
    );
  }

  static const _sectionLabelStyle = TextStyle(
    color: Color(0xFFDCEAF2),
    fontWeight: FontWeight.w900,
    fontSize: 14,
  );
}

class _ControlSection extends StatelessWidget {
  const _ControlSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1E2C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF173C54)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF12354A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF5FD4DC)),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF849EAF), fontSize: 12)),
        trailing: trailing,
        children: [child],
      ),
    );
  }
}

class _PermissionRow {
  const _PermissionRow(this.label, this.secretaryKey, this.technicianKey);
  final String label;
  final String secretaryKey;
  final String technicianKey;
}

class _PanelOption {
  const _PanelOption(this.label, this.key);
  final String label;
  final String key;
}

class _NavCardData {
  const _NavCardData(this.title, this.subtitle, this.icon, this.color, this.key);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final GlobalKey key;
}

class _TableHead extends StatelessWidget {
  const _TableHead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF9FB7C6), fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    );
  }
}
