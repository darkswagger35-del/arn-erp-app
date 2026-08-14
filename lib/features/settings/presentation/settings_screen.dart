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
import '../data/settings_repository_provider.dart';
import '../domain/settings_model.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const Color _ink = Color(0xFF10233D);
  static const Color _muted = Color(0xFF6C7A90);
  static const Color _line = Color(0xFFE2E9F1);
  static const Color _soft = Color(0xFFF6F9FC);
  static const Color _teal = Color(0xFF0CB7C5);

  bool _loading = true;
  bool _saving = false;
  bool _backupBusy = false;
  bool _logoBusy = false;
  bool _historyBusy = false;
  String? _companyLoadWarning;
  String? _backupWarning;
  String _selectedPanelRole = 'admin';

  late CompanyAppSettings _settings;
  CompanySettingsModel? _company;
  List<CompanyBackupRecord> _backups = const [];
  List<SettingsAuditEntry> _audit = const [];

  final _companyNameController = TextEditingController();
  final _authorizedController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _taxOfficeController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _maintenanceDaysController = TextEditingController();
  final _initialStockController = TextEditingController();
  final _onMyWayController = TextEditingController();
  final _appointmentController = TextEditingController();
  final _completedController = TextEditingController();
  final _formTitleController = TextEditingController();
  final _formFooterController = TextEditingController();

  final _generalKey = GlobalKey();
  final _appearanceKey = GlobalKey();
  final _permissionsKey = GlobalKey();
  final _serviceKey = GlobalKey();
  final _customerKey = GlobalKey();
  final _stockKey = GlobalKey();
  final _notificationKey = GlobalKey();
  final _formKey = GlobalKey();
  final _panelKey = GlobalKey();
  final _dataKey = GlobalKey();
  final _backupKey = GlobalKey();
  final _securityKey = GlobalKey();

  static const _serviceTypes = <ServiceRequestType>[
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
    _PermissionRow('Ürün ve fiyatları gör', 'secretary_view_prices', 'technician_view_prices'),
    _PermissionRow('Tahsilatları gör', 'secretary_view_payments', 'technician_view_payments'),
    _PermissionRow('Stok bilgilerini gör', 'secretary_view_stock', 'technician_view_stock'),
    _PermissionRow('Excel içeri / dışarı aktar', 'secretary_excel_transfer', 'technician_excel_transfer'),
  ];

  static const _panelOptions = <String, List<_PanelOption>>{
    'admin': [
      _PanelOption('Özet kartları', 'summary'),
      _PanelOption('Tekniker performansı', 'technician_performance'),
      _PanelOption('Sekreter performansı', 'secretary_performance'),
      _PanelOption('Bugünkü iş programı', 'today_schedule'),
      _PanelOption('Bugünkü tahsilatlar', 'recent_payments'),
      _PanelOption('Hızlı erişim', 'quick_access'),
    ],
    'secretary': [
      _PanelOption('Üst özet kartları', 'metrics'),
      _PanelOption('Günlük iş listesi', 'today_jobs'),
      _PanelOption('Son başvurular', 'latest_leads'),
      _PanelOption('Takip listesi', 'follow_up'),
      _PanelOption('Yaklaşan bakımlar', 'upcoming_maintenance'),
      _PanelOption('Hızlı işlemler', 'quick_actions'),
      _PanelOption('Günlük performans', 'performance'),
    ],
    'technician': [
      _PanelOption('Üst özet kartları', 'metrics'),
      _PanelOption('Sabah hazırlık / araç stoğu', 'morning_preparation'),
      _PanelOption('Günlük performans', 'performance'),
      _PanelOption('Ürün özeti', 'products'),
      _PanelOption('İş listesi', 'jobs'),
    ],
  };

  static const _sidebarPresets = <String, String>{
    'MOTUS Lacivert': '#071C2D',
    'Siyah': '#111827',
    'Petrol': '#0A3440',
    'Koyu Mavi': '#102A56',
    'Koyu Gri': '#263238',
  };

  static const _accentPresets = <String, String>{
    'Turkuaz': '#0D6578',
    'Mavi': '#2563EB',
    'Mor': '#7C3AED',
    'Yeşil': '#15803D',
    'Turuncu': '#C2410C',
  };

  @override
  void initState() {
    super.initState();
    _settings = const CompanyAppSettings(companyId: '');
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _companyNameController,
      _authorizedController,
      _companyPhoneController,
      _companyEmailController,
      _taxOfficeController,
      _taxNumberController,
      _addressController,
      _maintenanceDaysController,
      _initialStockController,
      _onMyWayController,
      _appointmentController,
      _completedController,
      _formTitleController,
      _formFooterController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final remote = await ref.read(companyAppSettingsProvider.future);
      CompanySettingsModel? company;
      String? companyWarning;
      try {
        company = await ref.read(settingsRepositoryProvider).loadSettings();
      } catch (error) {
        companyWarning = 'Firma / logo ayarları yüklenemedi: $error';
      }
      if (!mounted) return;
      setState(() {
        _settings = remote;
        _company = company;
        _companyLoadWarning = companyWarning;
        _maintenanceDaysController.text = remote.maintenanceReminderDays.toString();
        _initialStockController.text = remote.defaultInitialStock.toStringAsFixed(0);
        _onMyWayController.text = remote.onMyWayTemplate;
        _appointmentController.text = remote.appointmentTemplate;
        _completedController.text = remote.serviceCompletedTemplate;
        _formTitleController.text = remote.serviceFormTitle;
        _formFooterController.text = remote.serviceFormFooter;
        if (company != null) {
          _companyNameController.text = company.companyName;
          _authorizedController.text = company.authorizedName ?? '';
          _companyPhoneController.text = company.phone ?? '';
          _companyEmailController.text = company.email ?? '';
          _taxOfficeController.text = company.taxOffice ?? '';
          _taxNumberController.text = company.taxNumber ?? '';
          _addressController.text = company.address ?? '';
        }
        _loading = false;
      });
      await _refreshControlCenter();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Ayarlar yüklenemedi: $error', error: true);
    }
  }

  Future<void> _refreshControlCenter() async {
    if (_historyBusy) return;
    setState(() => _historyBusy = true);
    try {
      final repo = ref.read(settingsControlCenterRepositoryProvider);
      final results = await Future.wait([repo.listBackups(), repo.loadAudit()]);
      if (!mounted) return;
      setState(() {
        _backups = results[0] as List<CompanyBackupRecord>;
        _audit = results[1] as List<SettingsAuditEntry>;
        _backupWarning = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _backupWarning = 'Yedekleme / işlem geçmişi altyapısı hazır değilse 20260810_001_settings_control_center.sql migrationını uygulayın.';
      });
    } finally {
      if (mounted) setState(() => _historyBusy = false);
    }
  }

  int _maintenanceDays() =>
      (int.tryParse(_maintenanceDaysController.text.trim()) ?? 10).clamp(1, 365).toInt();

  double _initialStock() {
    final value = double.tryParse(_initialStockController.text.trim().replaceAll(',', '.')) ?? 0;
    return value < 0 ? 0 : value;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final supported = _serviceTypes.map((e) => e.value).toSet();
      var enabledTypes = _settings.enabledServiceTypes.where(supported.contains).toList(growable: false);
      if (enabledTypes.isEmpty) enabledTypes = ['other'];

      final next = _settings.copyWith(
        maintenanceReminderDays: _maintenanceDays(),
        defaultInitialStock: _initialStock(),
        onMyWayTemplate: _onMyWayController.text.trim(),
        appointmentTemplate: _appointmentController.text.trim(),
        serviceCompletedTemplate: _completedController.text.trim(),
        serviceFormTitle: _formTitleController.text.trim(),
        serviceFormFooter: _formFooterController.text.trim(),
        enabledServiceTypes: enabledTypes,
        allowTechnicianCustomerEdit: _settings.permission('technician_edit_customers', fallback: true),
        allowTechnicianHistoryEdit: _settings.permission('technician_edit_completed_service'),
      );
      await ref.read(companyAppSettingsRepositoryProvider).save(next);

      final company = _company;
      if (company != null) {
        if (_companyNameController.text.trim().isEmpty) {
          throw StateError('Firma adı boş bırakılamaz.');
        }
        final nextCompany = company.copyWith(
          companyName: _companyNameController.text.trim(),
          authorizedName: _authorizedController.text.trim(),
          phone: _companyPhoneController.text.trim(),
          email: _companyEmailController.text.trim(),
          taxOffice: _taxOfficeController.text.trim(),
          taxNumber: _taxNumberController.text.trim(),
          address: _addressController.text.trim(),
        );
        await ref.read(settingsRepositoryProvider).saveSettings(nextCompany);
        _company = nextCompany;
      }

      ref.invalidate(companyAppSettingsProvider);
      if (!mounted) return;
      setState(() => _settings = next);
      _message('Yönetim ayarları kaydedildi.');
      await _refreshControlCenter();
    } catch (error) {
      if (mounted) _message('Ayarlar kaydedilemedi: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setPermission(String key, bool value) {
    final next = Map<String, bool>.from(_settings.permissions)..[key] = value;
    setState(() => _settings = _settings.copyWith(permissions: next));
  }

  void _setServiceRule(String key, Object value) {
    final next = Map<String, dynamic>.from(_settings.serviceRules)..[key] = value;
    setState(() => _settings = _settings.copyWith(serviceRules: next));
  }

  void _setCustomerRule(String key, Object value) {
    final next = Map<String, dynamic>.from(_settings.customerRules)..[key] = value;
    setState(() => _settings = _settings.copyWith(customerRules: next));
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

  void _setAppearance(String key, Object value) {
    final all = <String, dynamic>{};
    for (final entry in _settings.panelVisibility.entries) {
      all[entry.key] = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : entry.value;
    }
    final appearance = Map<String, dynamic>.from(
      all['_appearance'] is Map ? all['_appearance'] as Map : const <String, dynamic>{},
    )..[key] = value;
    all['_appearance'] = appearance;
    setState(() => _settings = _settings.copyWith(panelVisibility: all));
  }

  String _appearance(String key, String fallback) =>
      _settings.appearanceString(key, fallback: fallback);

  Future<void> _pickLogo() async {
    if (_logoBusy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Firma / servis formu logosunu seç',
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      var bytes = file.bytes;
      if (bytes == null && file.path != null) bytes = await File(file.path!).readAsBytes();
      if (bytes == null) throw StateError('Logo dosyası okunamadı.');
      setState(() => _logoBusy = true);
      final url = await ref.read(settingsRepositoryProvider).uploadLogo(bytes: bytes, fileName: file.name);
      if (!mounted) return;
      final current = _company;
      if (current != null) setState(() => _company = current.copyWith(logoUrl: url));
      _message('Logo yüklendi. Servis formunda kullanıma hazır.');
    } catch (error) {
      if (mounted) _message('Logo yüklenemedi: $error', error: true);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _deleteLogo() async {
    if (_logoBusy || _company == null) return;
    setState(() => _logoBusy = true);
    try {
      await ref.read(settingsRepositoryProvider).deleteLogo();
      if (!mounted) return;
      setState(() => _company = _company!.copyWith(logoUrl: ''));
      _message('Logo kaldırıldı.');
    } catch (error) {
      if (mounted) _message('Logo kaldırılamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _createBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await ref.read(settingsControlCenterRepositoryProvider).createBackup(label: 'Manuel yedek');
      if (!mounted) return;
      _message('Tam işletme yedeği oluşturuldu.');
      await _refreshControlCenter();
    } catch (error) {
      if (mounted) _message('Yedek oluşturulamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackupFile() async {
    if (_backupBusy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'MOTUS yedek dosyasını seç',
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
      if (snapshot is! Map) throw const FormatException('Yedek dosyasında snapshot bulunamadı.');
      setState(() => _backupBusy = true);
      await ref.read(settingsControlCenterRepositoryProvider).importBackup(
            snapshot: Map<String, dynamic>.from(snapshot),
            counts: root['counts'] is Map
                ? Map<String, dynamic>.from(root['counts'] as Map)
                : const <String, dynamic>{},
            label: 'Dosyadan içe aktarıldı',
          );
      if (!mounted) return;
      _message('Yedek sisteme alındı. İstersen güvenli geri yükleyebilirsin.');
      await _refreshControlCenter();
    } catch (error) {
      if (mounted) _message('Yedek dosyası alınamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _exportBackup(CompanyBackupRecord backup) async {
    try {
      final full = backup.snapshot.isEmpty
          ? await ref.read(settingsControlCenterRepositoryProvider).loadBackup(backup.id)
          : backup;
      final stamp = DateFormat('yyyyMMdd_HHmm').format(full.createdAt.toLocal());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'MOTUS yedeğini kaydet',
        fileName: 'MOTUS_YEDEK_$stamp.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) return;
      await File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'backup_id': full.id,
          'created_at': full.createdAt.toUtc().toIso8601String(),
          'counts': full.counts,
          'snapshot': full.snapshot,
        }),
        flush: true,
      );
      if (mounted) _message('Yedek dosyası kaydedildi.');
    } catch (error) {
      if (mounted) _message('Yedek kaydedilemedi: $error', error: true);
    }
  }

  Future<void> _restoreBackup(CompanyBackupRecord backup) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Yedeği güvenli geri yükle'),
            content: const Text(
              'Silinmiş veya eksik kayıtlar geri getirilecek. Mevcut yeni kayıtlar silinmez ve işlem öncesi güvenlik yedeği alınır.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Geri Yükle'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || _backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await ref.read(settingsControlCenterRepositoryProvider).restoreBackup(backup.id);
      if (!mounted) return;
      _message('Geri yükleme tamamlandı.');
      await _refreshControlCenter();
    } catch (error) {
      if (mounted) _message('Geri yükleme başarısız: $error', error: true);
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(settingsControlCenterRepositoryProvider).deleteBackup(backup.id);
      await _refreshControlCenter();
    } catch (error) {
      if (mounted) _message('Yedek silinemedi: $error', error: true);
    }
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 320), alignment: .04);
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? const Color(0xFFB42318) : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.admin,
      title: 'Ayarlar',
      subtitle: 'Firma, görünüm, roller ve tüm çalışma kurallarını tek merkezden yönetin.',
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
              ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: [
                _managementOverview(),
                const SizedBox(height: 14),
                _quickNavigation(),
                const SizedBox(height: 18),
                KeyedSubtree(key: _generalKey, child: _generalSection()),
                KeyedSubtree(key: _appearanceKey, child: _appearanceSection()),
                KeyedSubtree(key: _permissionsKey, child: _permissionsSection()),
                KeyedSubtree(key: _serviceKey, child: _serviceSection()),
                KeyedSubtree(key: _customerKey, child: _customerSection()),
                KeyedSubtree(key: _stockKey, child: _stockPaymentSection()),
                KeyedSubtree(key: _notificationKey, child: _notificationSection()),
                KeyedSubtree(key: _formKey, child: _formSection()),
                KeyedSubtree(key: _panelKey, child: _panelSection()),
                KeyedSubtree(key: _dataKey, child: _dataSection()),
                KeyedSubtree(key: _backupKey, child: _backupSection()),
                KeyedSubtree(key: _securityKey, child: _securitySection()),
              ],
            ),
    );
  }

  Widget _managementOverview() {
    final companyName = _companyNameController.text.trim().isEmpty ? 'MOTUS' : _companyNameController.text.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: const Color(0xFFE3F8FA), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.admin_panel_settings_outlined, color: _teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Yönetim Merkezi • $companyName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
                    const SizedBox(height: 3),
                    const Text('Kullanıcı, veri, bildirim, marka ve operasyon ayarlarının tamamı burada.', style: TextStyle(color: _muted)),
                  ],
                ),
              ),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Tümünü Kaydet')),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 36) / 4
                  : constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _overviewCard(width, Icons.manage_accounts_outlined, 'Kullanıcılar', 'Roller, şifreler ve hesaplar', '/manager/users', const Color(0xFF2878F0)),
                  _overviewCard(width, Icons.table_view_outlined, 'Excel Aktarım', 'İçe / dışa aktarım araçları', '/manager/excel-transfer', const Color(0xFF00A878)),
                  _overviewCard(width, Icons.notifications_none_rounded, 'Bildirimler', 'Servis ve sistem bildirimleri', '/notifications', const Color(0xFF7C3AED)),
                  _overviewCard(width, Icons.security_outlined, 'Güvenlik', '${_audit.length} işlem geçmişi', null, const Color(0xFFF59E0B), onTap: () => _scrollTo(_securityKey)),
                ],
              );
            },
          ),
          if (_companyLoadWarning != null) ...[
            const SizedBox(height: 12),
            _warning(_companyLoadWarning!),
          ],
        ],
      ),
    );
  }

  Widget _overviewCard(double width, IconData icon, String title, String subtitle, String? route, Color color, {VoidCallback? onTap}) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? (route == null ? null : () => context.go(route)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                const SizedBox(height: 2),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _muted)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9BA9B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickNavigation() {
    final items = <_QuickNav>[
      _QuickNav('Firma & Marka', Icons.business_outlined, _generalKey),
      _QuickNav('Görünüm', Icons.palette_outlined, _appearanceKey),
      _QuickNav('Yetkiler', Icons.admin_panel_settings_outlined, _permissionsKey),
      _QuickNav('Servis', Icons.event_note_outlined, _serviceKey),
      _QuickNav('Müşteri', Icons.groups_2_outlined, _customerKey),
      _QuickNav('Stok & Tahsilat', Icons.inventory_2_outlined, _stockKey),
      _QuickNav('Bildirimler', Icons.notifications_active_outlined, _notificationKey),
      _QuickNav('Form & PDF', Icons.picture_as_pdf_outlined, _formKey),
      _QuickNav('Rol Panelleri', Icons.dashboard_customize_outlined, _panelKey),
      _QuickNav('Veri', Icons.dataset_outlined, _dataKey),
      _QuickNav('Yedek', Icons.cloud_done_outlined, _backupKey),
      _QuickNav('Güvenlik', Icons.shield_outlined, _securityKey),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) => ActionChip(
        avatar: Icon(item.icon, size: 17, color: _teal),
        label: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w800)),
        onPressed: () => _scrollTo(item.key),
      )).toList(growable: false),
    );
  }

  Widget _generalSection() {
    final company = _company;
    return _section(
      title: 'Firma & Marka',
      subtitle: 'Firma bilgileri ve servis formlarında kullanılacak kurumsal logo.',
      icon: Icons.business_outlined,
      child: Column(
        children: [
          LayoutBuilder(builder: (context, c) {
            final fieldWidth = c.maxWidth >= 900 ? (c.maxWidth - 24) / 3 : c.maxWidth >= 620 ? (c.maxWidth - 12) / 2 : c.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: fieldWidth, child: _field(_companyNameController, 'Firma adı')),
              SizedBox(width: fieldWidth, child: _field(_authorizedController, 'Yetkili / Ticari unvan')),
              SizedBox(width: fieldWidth, child: _field(_companyPhoneController, 'Firma telefonu')),
              SizedBox(width: fieldWidth, child: _field(_companyEmailController, 'Firma e-posta')),
              SizedBox(width: fieldWidth, child: _field(_taxOfficeController, 'Vergi dairesi')),
              SizedBox(width: fieldWidth, child: _field(_taxNumberController, 'Vergi numarası')),
              SizedBox(width: c.maxWidth, child: _field(_addressController, 'Firma adresi', maxLines: 2)),
            ]);
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
            child: LayoutBuilder(builder: (context, c) {
              final logo = company?.logoUrl?.trim() ?? '';
              final preview = Container(
                width: 150,
                height: 82,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
                child: logo.isEmpty
                    ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.image_outlined, color: _muted), SizedBox(height: 4), Text('Logo yok', style: TextStyle(color: _muted, fontSize: 11))])
                    : Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: _muted)),
              );
              final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Servis Formu / Firma Logosu', style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                const SizedBox(height: 4),
                const Text('PNG/JPG, en fazla 2 MB. Yüklenen logo servis PDF formunun üst kısmında kullanılır.', style: TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(onPressed: _logoBusy || company == null ? null : _pickLogo, icon: const Icon(Icons.upload_rounded), label: Text(_logoBusy ? 'Yükleniyor...' : 'Logo Yükle')),
                  OutlinedButton.icon(onPressed: _logoBusy || logo.isEmpty ? null : _deleteLogo, icon: const Icon(Icons.delete_outline), label: const Text('Logoyu Kaldır')),
                ]),
              ]);
              return c.maxWidth < 620
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [preview, const SizedBox(height: 12), details])
                  : Row(children: [preview, const SizedBox(width: 16), Expanded(child: details)]);
            }),
          ),
        ],
      ),
    );
  }

  Widget _appearanceSection() {
    final sidebar = _appearance('sidebar_color', '#071C2D');
    final accent = _appearance('accent_color', '#0D6578');
    final background = _appearance('content_background', '#F4F7FB');
    return _section(
      title: 'Panel Görünümü',
      subtitle: 'Sol menü ve uygulama çalışma alanının kurumsal görünümünü belirleyin.',
      icon: Icons.palette_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Sol menü rengi', style: _labelStyle),
        const SizedBox(height: 8),
        _colorPresets(_sidebarPresets, sidebar, (value) => _setAppearance('sidebar_color', value)),
        const SizedBox(height: 16),
        const Text('Seçili menü / vurgu rengi', style: _labelStyle),
        const SizedBox(height: 8),
        _colorPresets(_accentPresets, accent, (value) {
          _setAppearance('accent_color', value);
          _setAppearance('accent_icon_color', _lighterAccent(value));
        }),
        const SizedBox(height: 16),
        const Text('İçerik arka planı', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Açık Gri'), selected: background == '#F4F7FB', onSelected: (_) => _setAppearance('content_background', '#F4F7FB')),
          ChoiceChip(label: const Text('Beyaz'), selected: background == '#FFFFFF', onSelected: (_) => _setAppearance('content_background', '#FFFFFF')),
          ChoiceChip(label: const Text('Buz Beyazı'), selected: background == '#F7FAFC', onSelected: (_) => _setAppearance('content_background', '#F7FAFC')),
        ]),
        const SizedBox(height: 14),
        _info(Icons.info_outline, 'Renk değişiklikleri kaydedildikten sonra tüm yönetim ekranlarının sol menüsüne uygulanır. Ekranların onaylı yerleşimleri değişmez.'),
      ]),
    );
  }

  String _lighterAccent(String value) => switch (value) {
        '#2563EB' => '#60A5FA',
        '#7C3AED' => '#A78BFA',
        '#15803D' => '#4ADE80',
        '#C2410C' => '#FB923C',
        _ => '#22D3DC',
      };

  Widget _colorPresets(Map<String, String> presets, String selected, ValueChanged<String> onChanged) {
    return Wrap(spacing: 8, runSpacing: 8, children: presets.entries.map((entry) {
      final color = _parseColor(entry.value, _teal);
      return ChoiceChip(
        selected: selected.toUpperCase() == entry.value.toUpperCase(),
        avatar: CircleAvatar(radius: 7, backgroundColor: color),
        label: Text(entry.key),
        onSelected: (_) => onChanged(entry.value),
      );
    }).toList(growable: false));
  }

  Widget _permissionsSection() {
    return _section(
      title: 'Kullanıcı & Yetkiler',
      subtitle: 'Sekreter ve teknikerlerin uygulamada neleri görebileceğini ve değiştirebileceğini yönetin.',
      icon: Icons.admin_panel_settings_outlined,
      trailing: OutlinedButton.icon(onPressed: () => context.go('/manager/users'), icon: const Icon(Icons.manage_accounts_outlined), label: const Text('Kullanıcıları Aç')),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(color: _soft, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
              child: const Row(children: [
                Expanded(flex: 4, child: Text('Yetki', style: TextStyle(fontWeight: FontWeight.w900, color: _ink))),
                SizedBox(width: 130, child: Center(child: Text('Sekreter', style: TextStyle(fontWeight: FontWeight.w900, color: _ink)))),
                SizedBox(width: 130, child: Center(child: Text('Tekniker', style: TextStyle(fontWeight: FontWeight.w900, color: _ink)))),
              ]),
            ),
            ..._permissionRows.map((row) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
              child: Row(children: [
                Expanded(flex: 4, child: Text(row.label, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink))),
                SizedBox(width: 130, child: Center(child: Switch(value: _settings.permission(row.secretaryKey), onChanged: (v) => _setPermission(row.secretaryKey, v)))),
                SizedBox(width: 130, child: Center(child: Switch(value: _settings.permission(row.technicianKey), onChanged: (v) => _setPermission(row.technicianKey, v)))),
              ]),
            )),
          ]),
        ),
        const SizedBox(height: 10),
        _info(Icons.shield_outlined, 'Yönetici tam yetkilidir. Bu ekran uygulama davranışını yönetir; Supabase RLS güvenlik politikaları ayrıca korunur.'),
      ]),
    );
  }

  Widget _serviceSection() {
    return _section(
      title: 'Servis & Planlama',
      subtitle: 'Servis türleri, randevu davranışı, kapatma zorunlulukları ve akıllı rota kuralları.',
      icon: Icons.event_note_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Aktif servis türleri', style: _labelStyle),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: _serviceTypes.map((type) {
          final selected = _settings.enabledServiceTypes.contains(type.value);
          return FilterChip(
            selected: selected,
            label: Text(type.label),
            onSelected: (value) {
              final next = _settings.enabledServiceTypes.where((e) => _serviceTypes.any((t) => t.value == e)).toList();
              if (value && !next.contains(type.value)) next.add(type.value);
              if (!value && next.length > 1) next.remove(type.value);
              setState(() => _settings = _settings.copyWith(enabledServiceTypes: next));
            },
          );
        }).toList(growable: false)),
        const SizedBox(height: 12),
        _toggle('Tekniker kullanılan ürünleri değiştirebilsin', null, _settings.serviceRule('technician_can_change_products', fallback: true), (v) => _setServiceRule('technician_can_change_products', v)),
        _toggle('Tekniker tahsilat girebilsin', null, _settings.serviceRule('technician_can_collect_payment', fallback: true), (v) => _setServiceRule('technician_can_collect_payment', v)),
        const Divider(height: 26),
        const Text('Servis kapatma zorunlulukları', style: _labelStyle),
        _toggle('Yapılan işlem açıklaması zorunlu', null, _settings.serviceRule('require_work_description', fallback: true), (v) => _setServiceRule('require_work_description', v)),
        _toggle('Filtre değişiminde ürün seçimi zorunlu', null, _settings.serviceRule('require_product_for_filter_change', fallback: true), (v) => _setServiceRule('require_product_for_filter_change', v)),
      ]),
    );
  }

  Widget _customerSection() {
    return _section(
      title: 'Müşteri & Bakım',
      subtitle: 'Müşteri kaydı, bakım yaklaşma süresi ve zorunlu alanlar.',
      icon: Icons.groups_2_outlined,
      child: Column(children: [
        LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth >= 700 ? (c.maxWidth - 12) / 2 : c.maxWidth;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(width: width, child: _field(_maintenanceDaysController, 'Bakım kaç gün kala yaklaşan sayılır?', keyboardType: TextInputType.number)),
            SizedBox(width: width, child: _readOnly('Bakım hesabı', _settings.calculateMaintenanceFromProduct ? 'Ürün bakım süresine göre otomatik' : 'Manuel takip')),
          ]);
        }),
        const SizedBox(height: 8),
        _toggle('Gecikmiş bakımları göster', null, _settings.showOverdueMaintenances, (v) => setState(() => _settings = _settings.copyWith(showOverdueMaintenances: v))),
        _toggle('Bakım tarihini üründen otomatik hesapla', null, _settings.calculateMaintenanceFromProduct, (v) => setState(() => _settings = _settings.copyWith(calculateMaintenanceFromProduct: v))),
        _toggle('Bakım süresi olmayan ürünleri bakım listesinden gizle', null, _settings.hideProductsWithoutMaintenance, (v) => setState(() => _settings = _settings.copyWith(hideProductsWithoutMaintenance: v))),
        _toggle('Aynı telefonla mükerrer müşteriyi engelle', null, _settings.customerRule('duplicate_phone_check', fallback: true), (v) => _setCustomerRule('duplicate_phone_check', v)),
        const Divider(height: 26),
        const Align(alignment: Alignment.centerLeft, child: Text('Yeni müşteri kaydında zorunlu alanlar', style: _labelStyle)),
        _toggle('Telefon zorunlu', null, _settings.customerRule('phone_required', fallback: true), (v) => _setCustomerRule('phone_required', v)),
        _toggle('Şehir zorunlu', null, _settings.customerRule('city_required', fallback: true), (v) => _setCustomerRule('city_required', v)),
        _toggle('İlçe zorunlu', null, _settings.customerRule('district_required', fallback: true), (v) => _setCustomerRule('district_required', v)),
        _toggle('Açık adres zorunlu', null, _settings.customerRule('address_required', fallback: true), (v) => _setCustomerRule('address_required', v)),
      ]),
    );
  }

  Widget _stockPaymentSection() {
    const methods = <String, String>{'cash': 'Nakit', 'card': 'Kredi Kartı', 'transfer': 'Havale / EFT', 'open_account': 'Açık Hesap'};
    return _section(
      title: 'Stok & Tahsilat',
      subtitle: 'Servis tamamlandığında stok ve ödeme işlemlerinin nasıl davranacağını belirleyin.',
      icon: Icons.inventory_2_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _toggle('Servis tamamlanınca kullanılan ürün stoktan düşsün', null, _settings.autoDecreaseStockOnService, (v) => setState(() => _settings = _settings.copyWith(autoDecreaseStockOnService: v))),
        _toggle('Yeni ürün otomatik ana depoya eklensin', null, _settings.autoAddNewProductToMainWarehouse, (v) => setState(() => _settings = _settings.copyWith(autoAddNewProductToMainWarehouse: v))),
        _toggle('Eksi stoğa izin ver', null, _settings.allowNegativeStock, (v) => setState(() => _settings = _settings.copyWith(allowNegativeStock: v))),
        const SizedBox(height: 8),
        SizedBox(width: 340, child: _field(_initialStockController, 'Yeni üründe varsayılan başlangıç stoğu', keyboardType: TextInputType.number)),
        const Divider(height: 28),
        _toggle('Ödeme bilgisi olmadan servis tamamlanamasın', null, _settings.requirePaymentToCompleteService, (v) => setState(() => _settings = _settings.copyWith(requirePaymentToCompleteService: v))),
        _toggle('Kısmi ödemeye izin ver', null, _settings.allowPartialPayment, (v) => setState(() => _settings = _settings.copyWith(allowPartialPayment: v))),
        const SizedBox(height: 8),
        SizedBox(
          width: 340,
          child: DropdownButtonFormField<String>(
            value: methods.containsKey(_settings.defaultPaymentMethod) ? _settings.defaultPaymentMethod : 'cash',
            decoration: const InputDecoration(labelText: 'Varsayılan ödeme yöntemi'),
            items: methods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _settings = _settings.copyWith(defaultPaymentMethod: value));
            },
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: methods.entries.map((entry) {
          final enabled = _settings.enabledPaymentMethods.contains(entry.key);
          return FilterChip(
            selected: enabled,
            label: Text(entry.value),
            onSelected: (value) {
              final next = List<String>.from(_settings.enabledPaymentMethods);
              if (value && !next.contains(entry.key)) next.add(entry.key);
              if (!value && next.length > 1) next.remove(entry.key);
              setState(() => _settings = _settings.copyWith(enabledPaymentMethods: next));
            },
          );
        }).toList(growable: false)),
      ]),
    );
  }

  Widget _notificationSection() {
    return _section(
      title: 'Bildirim & Hazır Mesajlar',
      subtitle: 'Tekniker atama bildirimi ve hazır müşteri mesajlarını yönetin.',
      icon: Icons.notifications_active_outlined,
      trailing: OutlinedButton.icon(onPressed: () => context.go('/notifications'), icon: const Icon(Icons.notifications_none_rounded), label: const Text('Bildirim Merkezi')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _toggle('Teknikere iş atanınca uygulama bildirimi oluştur', null, _settings.technicianAssignmentNotifications, (v) => setState(() => _settings = _settings.copyWith(technicianAssignmentNotifications: v))),
        const Divider(height: 28),
        const Text('Hazır mesajlar', style: _labelStyle),
        const SizedBox(height: 8),
        _field(_onMyWayController, 'Tekniker – Geliyorum mesajı', helper: 'Kullanılabilir: {{musteri}}', maxLines: 3),
        const SizedBox(height: 10),
        _field(_appointmentController, 'Sekreter – Randevu mesajı', helper: '{{musteri}}, {{tarih}}, {{servis_turu}}, {{teknisyen}}', maxLines: 3),
        const SizedBox(height: 10),
        _field(_completedController, 'Servis tamamlandı mesajı', helper: '{{musteri}}, {{tutar}}', maxLines: 3),
      ]),
    );
  }

  Widget _formSection() {
    final company = _company;
    final form = _settings.serviceFormConfig;
    bool formBool(String key, {bool fallback = true}) {
      final value = form[key];
      return value is bool ? value : fallback;
    }
    void setFormBool(String key, bool value) {
      final next = Map<String, dynamic>.from(_settings.serviceFormConfig)..[key] = value;
      setState(() => _settings = _settings.copyWith(serviceFormConfig: next));
    }

    return _section(
      title: 'Servis Formu & PDF',
      subtitle: 'Servis PDF başlığı, logo, fiyat, imza ve form alanlarını buradan yönetin.',
      icon: Icons.picture_as_pdf_outlined,
      trailing: OutlinedButton.icon(onPressed: () => context.go('/manager/service-form-designer'), icon: const Icon(Icons.design_services_outlined), label: const Text('Form Tasarımcısı')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field(_formTitleController, 'Servis formu başlığı'),
        const SizedBox(height: 10),
        _field(_formFooterController, 'Servis formu alt notu', maxLines: 2),
        const SizedBox(height: 10),
        if (company != null) _toggle('PDF’de firma logosunu göster', null, company.pdfShowLogo, (v) => setState(() => _company = company.copyWith(pdfShowLogo: v))),
        if (company != null) _toggle('PDF’de kaşe alanını göster', null, company.pdfShowSeal, (v) => setState(() => _company = company.copyWith(pdfShowSeal: v))),
        if (company != null) _toggle('PDF’de imza alanlarını göster', null, company.pdfShowSignature, (v) => setState(() => _company = company.copyWith(pdfShowSignature: v))),
        _toggle('Müşteri telefonu görünsün', null, formBool('show_phone'), (v) => setFormBool('show_phone', v)),
        _toggle('Müşteri adresi görünsün', null, formBool('show_address'), (v) => setFormBool('show_address', v)),
        _toggle('Kullanılan ürünler görünsün', null, formBool('show_products'), (v) => setFormBool('show_products', v)),
        _toggle('Fiyatlar görünsün', null, formBool('show_prices'), (v) => setFormBool('show_prices', v)),
        _toggle('Müşteri imzası görünsün', null, formBool('show_customer_signature'), (v) => setFormBool('show_customer_signature', v)),
        _toggle('Tekniker imzası görünsün', null, formBool('show_technician_signature'), (v) => setFormBool('show_technician_signature', v)),
        _toggle('TDS giriş alanı', null, formBool('show_tds_in', fallback: false), (v) => setFormBool('show_tds_in', v)),
        _toggle('TDS çıkış alanı', null, formBool('show_tds_out', fallback: false), (v) => setFormBool('show_tds_out', v)),
        _toggle('Tank basıncı alanı', null, formBool('show_tank_pressure', fallback: false), (v) => setFormBool('show_tank_pressure', v)),
        const SizedBox(height: 8),
        _info(Icons.image_outlined, 'Firma & Marka bölümünde yüklediğin logo artık servis PDF formunda kullanılabilir.'),
      ]),
    );
  }

  Widget _panelSection() {
    const roles = <String, String>{'admin': 'Yönetici', 'secretary': 'Sekreter', 'technician': 'Tekniker'};
    final options = _panelOptions[_selectedPanelRole] ?? const <_PanelOption>[];
    return _section(
      title: 'Rol Bazlı Ana Panel',
      subtitle: 'Yönetici, sekreter ve tekniker ana ekranlarında hangi blokların görüneceğini seçin.',
      icon: Icons.dashboard_customize_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: roles.entries.map((e) => ChoiceChip(label: Text(e.value), selected: _selectedPanelRole == e.key, onSelected: (_) => setState(() => _selectedPanelRole = e.key))).toList(growable: false)),
        const SizedBox(height: 12),
        ...options.map((option) => _toggle(option.label, option.key == 'announcements' ? 'Duyurular varsayılan olarak kapalı tutulur.' : null, _settings.panelVisible(_selectedPanelRole, option.key), (v) => _setPanelVisible(_selectedPanelRole, option.key, v))),
      ]),
    );
  }

  Widget _dataSection() {
    return _section(
      title: 'Veri & Excel Yönetimi',
      subtitle: 'Müşteri, eski işlem, ürün ve servis verilerine hızlı erişim.',
      icon: Icons.dataset_outlined,
      child: LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth >= 900 ? (c.maxWidth - 24) / 3 : c.maxWidth >= 600 ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          _actionCard(width, Icons.table_view_outlined, 'Excel İçeri / Dışarı Aktar', 'Müşteri ve eski işlem kayıtlarını Excel ile taşı.', () => context.go('/manager/excel-transfer')),
          _actionCard(width, Icons.inventory_2_outlined, 'Ürün & Stok', 'Ürün ve depoları kontrol et.', () => context.go('/manager/products')),
          _actionCard(width, Icons.description_outlined, 'Servis Formları', 'Tamamlanan servis PDF kayıtlarını aç.', () => context.go('/manager/service-documents')),
        ]);
      }),
    );
  }

  Widget _backupSection() {
    return _section(
      title: 'Yedekleme & Geri Yükleme',
      subtitle: 'Müşteri, servis, stok ve tahsilat verilerinin güvenli kopyalarını yönetin.',
      icon: Icons.cloud_done_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _backupBusy || _backupWarning != null ? null : _createBackup, icon: const Icon(Icons.backup_outlined), label: const Text('Şimdi Yedek Al')),
          OutlinedButton.icon(onPressed: _backupBusy || _backupWarning != null ? null : _importBackupFile, icon: const Icon(Icons.upload_file_outlined), label: const Text('Yedek Dosyası Al')),
        ]),
        if (_backupWarning != null) ...[const SizedBox(height: 10), _warning(_backupWarning!)],
        const SizedBox(height: 12),
        if (_backups.isEmpty)
          const Text('Henüz yedek yok.', style: TextStyle(color: _muted))
        else
          ..._backups.take(6).map(_backupRow),
      ]),
    );
  }

  Widget _backupRow(CompanyBackupRecord backup) {
    String count(String key) => '${backup.counts[key] ?? 0}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Row(children: [
        const CircleAvatar(backgroundColor: Color(0xFFE2F7EF), child: Icon(Icons.cloud_done_outlined, color: Color(0xFF15805B))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(backup.label?.trim().isNotEmpty == true ? backup.label! : 'İşletme Yedeği', style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
          Text('${DateFormat('dd.MM.yyyy HH:mm').format(backup.createdAt.toLocal())} • ${count('customers')} müşteri • ${count('services')} servis • ${count('products')} ürün • ${count('payments')} tahsilat', style: const TextStyle(color: _muted, fontSize: 11.5)),
        ])),
        IconButton(tooltip: 'JSON indir', onPressed: () => _exportBackup(backup), icon: const Icon(Icons.download_rounded)),
        IconButton(tooltip: 'Geri yükle', onPressed: _backupBusy ? null : () => _restoreBackup(backup), icon: const Icon(Icons.restore_rounded)),
        IconButton(tooltip: 'Sil', onPressed: () => _deleteBackup(backup), icon: const Icon(Icons.delete_outline_rounded)),
      ]),
    );
  }

  Widget _securitySection() {
    return _section(
      title: 'Güvenlik & İşlem Geçmişi',
      subtitle: 'Kritik işlemlerde kim ne yaptı, ne zaman yaptı görün.',
      icon: Icons.shield_outlined,
      trailing: IconButton(onPressed: _historyBusy ? null : _refreshControlCenter, icon: const Icon(Icons.refresh_rounded)),
      child: _historyBusy && _audit.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          : _audit.isEmpty
              ? const Text('İşlem geçmişi bulunamadı.', style: TextStyle(color: _muted))
              : Column(children: _audit.take(15).map(_auditRow).toList(growable: false)),
    );
  }

  Widget _auditRow(SettingsAuditEntry entry) {
    final label = switch (entry.action) {
      'settings_updated' => 'Ayarlar değiştirildi',
      'backup_created' => 'Yeni sistem yedeği oluşturuldu',
      'backup_restored' => 'Yedekten kayıtlar geri getirildi',
      'create' => 'Yeni kayıt oluşturuldu',
      'insert' => 'Yeni kayıt oluşturuldu',
      'update' => 'Kayıt güncellendi',
      'delete' => 'Kayıt silindi',
      _ => entry.action.replaceAll('_', ' '),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE8F8FA), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.history_rounded, color: _teal, size: 19)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          Text('${entry.userName ?? 'Kullanıcı'} • ${entry.entityType}', style: const TextStyle(color: _muted, fontSize: 11.5)),
        ])),
        Text(DateFormat('dd.MM HH:mm').format(entry.createdAt.toLocal()), style: const TextStyle(color: _muted, fontSize: 11)),
      ]),
    );
  }

  Widget _section({required String title, required String subtitle, required IconData icon, required Widget child, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFE5F8FA), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _teal)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
          ])),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  Widget _toggle(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F3F7)))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: const TextStyle(fontSize: 11.5, color: _muted))],
        ])),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _field(TextEditingController controller, String label, {String? helper, int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, helperText: helper, filled: true, fillColor: Colors.white),
    );
  }

  Widget _readOnly(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
      child: Row(children: [
        const Icon(Icons.auto_awesome_outlined, color: _teal),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: _muted, fontSize: 11.5)), Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink))])),
      ]),
    );
  }

  Widget _actionCard(double width, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(13), border: Border.all(color: _line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: const Color(0xFFE5F8FA), child: Icon(icon, color: _teal)),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11.5)),
            const SizedBox(height: 9),
            const Row(mainAxisSize: MainAxisSize.min, children: [Text('Aç', style: TextStyle(color: _teal, fontWeight: FontWeight.w800)), SizedBox(width: 3), Icon(Icons.arrow_forward_rounded, size: 16, color: _teal)]),
          ]),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFEEF9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCBECEF))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 19, color: _teal), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF496273), fontSize: 11.5)))]),
    );
  }

  Widget _warning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF6D99D))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFC77B00)), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: Color(0xFF805500), fontSize: 11.5)))]),
    );
  }

  Color _parseColor(String value, Color fallback) {
    final cleaned = value.replaceFirst('#', '');
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null || (cleaned.length != 6 && cleaned.length != 8)) return fallback;
    return Color(cleaned.length == 6 ? 0xFF000000 | parsed : parsed);
  }

  static const _labelStyle = TextStyle(fontWeight: FontWeight.w900, color: _ink, fontSize: 13);
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

class _QuickNav {
  const _QuickNav(this.label, this.icon, this.key);
  final String label;
  final IconData icon;
  final GlobalKey key;
}
