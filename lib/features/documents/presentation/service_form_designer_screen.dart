import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../settings/data/company_app_settings.dart';

class ServiceFormDesignerScreen extends ConsumerStatefulWidget {
  const ServiceFormDesignerScreen({super.key});

  @override
  ConsumerState<ServiceFormDesignerScreen> createState() =>
      _ServiceFormDesignerScreenState();
}

class _ServiceFormDesignerScreenState
    extends ConsumerState<ServiceFormDesignerScreen> {
  bool _loading = true;
  bool _saving = false;
  late CompanyAppSettings _settings;
  late Map<String, dynamic> _config;
  final _titleController = TextEditingController();
  final _footerController = TextEditingController();

  static const _sections = <String, String>{
    'customer': 'Müşteri Bilgileri',
    'service': 'Servis Bilgileri',
    'description': 'Açıklama / Notlar',
    'products': 'Kullanılan Ürünler',
    'total': 'Toplam Tutar',
    'signatures': 'İmzalar',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await ref.read(companyAppSettingsProvider.future);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _config = Map<String, dynamic>.from(settings.serviceFormConfig);
        _titleController.text = settings.serviceFormTitle;
        _footerController.text = settings.serviceFormFooter;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Servis formu ayarları yüklenemedi: $error', error: true);
    }
  }

  bool _flag(String key, {bool fallback = false}) {
    final value = _config[key];
    return value is bool ? value : fallback;
  }

  void _setFlag(String key, bool value) {
    setState(() => _config[key] = value);
  }

  List<String> get _order {
    final raw = _config['section_order'];
    final values = raw is List
        ? raw.map((e) => e.toString()).where(_sections.containsKey).toList()
        : <String>[];
    for (final key in _sections.keys) {
      if (!values.contains(key)) values.add(key);
    }
    return values;
  }

  List<Map<String, dynamic>> get _customFields {
    final raw = _config['custom_fields'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: true);
  }

  void _moveSection(String key, int delta) {
    final order = _order;
    final index = order.indexOf(key);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= order.length) return;
    final item = order.removeAt(index);
    order.insert(target, item);
    setState(() => _config['section_order'] = order);
  }

  String _normalizedFieldType(Map<String, dynamic> field) {
    final raw = field['type']?.toString().trim().toLowerCase() ?? '';
    if (const {'text', 'multiline', 'number', 'date', 'time', 'select', 'boolean'}.contains(raw)) {
      return raw;
    }
    final label = field['label']?.toString().toLowerCase() ?? '';
    if (label.contains('tarih')) return 'date';
    if (label.contains('saat')) return 'time';
    if (label.contains('tds') || label.contains('basınç') || label.contains('basinc')) return 'number';
    return 'text';
  }

  String _fieldTypeLabel(String type) => switch (type) {
        'multiline' => 'Uzun metin',
        'number' => 'Sayı',
        'date' => 'Tarih',
        'time' => 'Saat',
        'select' => 'Seçim listesi',
        'boolean' => 'Evet / Hayır',
        _ => 'Metin',
      };

  Future<Map<String, dynamic>?> _showCustomFieldDialog({
    Map<String, dynamic>? initial,
  }) async {
    final label = TextEditingController(text: initial?['label']?.toString() ?? '');
    final placeholder = TextEditingController(text: initial?['placeholder']?.toString() ?? '');
    final rawOptions = initial?['options'];
    final options = TextEditingController(
      text: rawOptions is List ? rawOptions.map((e) => e.toString()).join('\n') : '',
    );
    var type = initial == null ? 'text' : _normalizedFieldType(initial);
    var required = initial?['required'] == true;
    var enabled = initial?['enabled'] != false;
    var showOnPanel = initial?['show_on_panel'] != false;
    var showOnPdf = initial?['show_on_pdf'] != false;
    var defaultToday = initial?['default_today'] == true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(initial == null ? 'Yeni Form Alanı' : 'Form Alanını Düzenle'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: label,
                    autofocus: initial == null,
                    decoration: const InputDecoration(
                      labelText: 'Panelde / PDF’de yazacak başlık',
                      hintText: 'Örn. Montaj Tarihi, TDS Giriş, Cihaz Seri No',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Alan tipi'),
                    items: const [
                      DropdownMenuItem(value: 'text', child: Text('Metin')),
                      DropdownMenuItem(value: 'multiline', child: Text('Uzun metin')),
                      DropdownMenuItem(value: 'number', child: Text('Sayı')),
                      DropdownMenuItem(value: 'date', child: Text('Tarih')),
                      DropdownMenuItem(value: 'time', child: Text('Saat')),
                      DropdownMenuItem(value: 'select', child: Text('Seçim listesi')),
                      DropdownMenuItem(value: 'boolean', child: Text('Evet / Hayır')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (type != 'boolean')
                    TextField(
                      controller: placeholder,
                      decoration: const InputDecoration(
                        labelText: 'Yardım yazısı / örnek',
                        hintText: 'Örn. Ölçülen değeri girin',
                      ),
                    ),
                  if (type == 'select') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: options,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Seçenekler',
                        helperText: 'Her satıra bir seçenek yazın.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                  if (type == 'date') ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bugünün tarihini otomatik getir'),
                      subtitle: const Text('Tekniker isterse tarihi değiştirebilir.'),
                      value: defaultToday,
                      onChanged: (value) => setDialogState(() => defaultToday = value),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Zorunlu alan'),
                    value: required,
                    onChanged: (value) => setDialogState(() => required = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tekniker servis tamamlama panelinde göster'),
                    value: showOnPanel,
                    onChanged: (value) => setDialogState(() => showOnPanel = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Servis PDF formunda göster'),
                    value: showOnPdf,
                    onChanged: (value) => setDialogState(() => showOnPdf = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alan aktif'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final text = label.text.trim();
                if (text.isEmpty) return;
                final parsedOptions = options.text
                    .split(RegExp(r'[\n,;]+'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toSet()
                    .toList(growable: false);
                if (type == 'select' && parsedOptions.isEmpty) return;
                Navigator.pop(dialogContext, {
                  'id': initial?['id']?.toString().trim().isNotEmpty == true
                      ? initial!['id'].toString()
                      : 'custom_${DateTime.now().millisecondsSinceEpoch}',
                  'label': text,
                  'type': type,
                  'placeholder': placeholder.text.trim(),
                  'options': type == 'select' ? parsedOptions : const <String>[],
                  'required': required,
                  'enabled': enabled,
                  'show_on_panel': showOnPanel,
                  'show_on_pdf': showOnPdf,
                  'default_today': type == 'date' && defaultToday,
                });
              },
              child: Text(initial == null ? 'Ekle' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    placeholder.dispose();
    options.dispose();
    return result;
  }

  Future<void> _addCustomField() async {
    final result = await _showCustomFieldDialog();
    if (result == null) return;
    final fields = _customFields..add(result);
    setState(() => _config['custom_fields'] = fields);
  }

  Future<void> _editCustomField(int index) async {
    final fields = _customFields;
    if (index < 0 || index >= fields.length) return;
    final result = await _showCustomFieldDialog(initial: fields[index]);
    if (result == null) return;
    fields[index] = result;
    setState(() => _config['custom_fields'] = fields);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final next = _settings.copyWith(
        serviceFormTitle: _titleController.text.trim().isEmpty
            ? 'ARN SU ARITMA SERVİS FORMU'
            : _titleController.text.trim(),
        serviceFormFooter: _footerController.text.trim(),
        showPricesOnForm: _flag('show_prices', fallback: true),
        showSignatureOnForm: _flag('show_customer_signature', fallback: true) ||
            _flag('show_technician_signature', fallback: true),
        showCustomerAddressOnForm: _flag('show_address', fallback: true),
        serviceFormConfig: _config,
      );
      await ref.read(companyAppSettingsRepositoryProvider).save(next);
      ref.invalidate(companyAppSettingsProvider);
      if (!mounted) return;
      setState(() => _settings = next);
      _message('Servis formu tasarımı kaydedildi. Tekniker servis paneli ve yeni PDF formları bu şablonu kullanacak.');
    } catch (error) {
      if (!mounted) return;
      _message('Servis formu kaydedilemedi: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.manager,
      title: 'Servis Formu Tasarımcısı',
      subtitle:
          'Alanları burada tanımlayın; tekniker servis tamamlama paneli ve PDF formu otomatik olarak bu şablonu kullanır.',
      dark: true,
      actions: [
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Şablonu Kaydet'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1150;
                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: _editor()),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: _preview()),
                        ],
                      )
                    else ...[
                      _editor(),
                      const SizedBox(height: 16),
                      _preview(),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _editor() {
    return Column(
      children: [
        _card(
          title: 'Form Başlığı',
          icon: Icons.title_rounded,
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Form başlığı'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _footerController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Form alt yazısı'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Gösterilecek Alanlar',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              _toggle('Telefon', 'show_phone', true),
              _toggle('Müşteri adresi', 'show_address', true),
              _toggle('Servis türü', 'show_service_type', true),
              _toggle('Tekniker', 'show_technician', true),
              _toggle('Tamamlanma tarihi', 'show_completed_at', true),
              _toggle('Açıklama / şikayet', 'show_description', true),
              _toggle('Tamamlama notu', 'show_completion_note', true),
              _toggle('Kullanılan ürünler', 'show_products', true),
              _toggle('Fiyatlar ve toplam', 'show_prices', true),
              _toggle('Müşteri imzası', 'show_customer_signature', true),
              _toggle('Tekniker imzası', 'show_technician_signature', true),
              const Divider(height: 24),
              _toggle('TDS giriş alanı', 'show_tds_in', false),
              _toggle('TDS çıkış alanı', 'show_tds_out', false),
              _toggle('Tank basıncı alanı', 'show_tank_pressure', false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Kapatma Zorunlulukları',
          icon: Icons.verified_outlined,
          child: Column(
            children: [
              _toggle('Tamamlama notu zorunlu', 'required_completion_note', false),
              _toggle('Müşteri imzası zorunlu', 'required_customer_signature', false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Bölüm Sırası',
          icon: Icons.reorder_rounded,
          child: Column(
            children: _order.asMap().entries.map((entry) {
              final index = entry.key;
              final key = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                ),
                title: Text(_sections[key] ?? key),
                trailing: Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      tooltip: 'Yukarı taşı',
                      onPressed: index == 0 ? null : () => _moveSection(key, -1),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Aşağı taşı',
                      onPressed: index == _order.length - 1
                          ? null
                          : () => _moveSection(key, 1),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        _card(
          title: 'Özel Alanlar',
          icon: Icons.add_box_outlined,
          trailing: OutlinedButton.icon(
            onPressed: _addCustomField,
            icon: const Icon(Icons.add),
            label: const Text('Yeni Alan Ekle'),
          ),
          child: _customFields.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Özel alan yok. Yeni alan eklediğinizde alan tipini ve Tekniker paneli / PDF görünürlüğünü seçebilirsiniz.',
                    style: TextStyle(color: Color(0xFF91A4B7)),
                  ),
                )
              : Column(
                  children: _customFields.asMap().entries.map((entry) {
                    final fields = _customFields;
                    final field = entry.value;
                    final type = _normalizedFieldType(field);
                    final placements = <String>[
                      if (field['show_on_panel'] != false) 'Tekniker paneli',
                      if (field['show_on_pdf'] != false) 'PDF',
                    ];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(type == 'date'
                          ? Icons.calendar_month_outlined
                          : type == 'number'
                              ? Icons.numbers_rounded
                              : type == 'select'
                                  ? Icons.list_alt_outlined
                                  : Icons.text_fields_rounded),
                      title: Text(field['label']?.toString() ?? 'Alan'),
                      subtitle: Text(
                        '${_fieldTypeLabel(type)} • ${field['required'] == true ? 'Zorunlu' : 'İsteğe bağlı'} • ${placements.isEmpty ? 'Gösterim kapalı' : placements.join(' + ')}',
                      ),
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          IconButton(
                            tooltip: 'Düzenle',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editCustomField(entry.key),
                          ),
                          IconButton(
                            tooltip: 'Kaldır',
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
                            onPressed: () {
                              fields.removeAt(entry.key);
                              setState(() => _config['custom_fields'] = fields);
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _toggle(String title, String key, bool fallback) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      value: _flag(key, fallback: fallback),
      onChanged: (value) => _setFlag(key, value),
    );
  }

  Widget _preview() {
    final order = _order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_outlined, color: Color(0xFF12B8C4)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Canlı Önizleme',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12B8C4).withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('A4 PDF', style: TextStyle(color: Color(0xFF22D3DC))),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(color: Color(0xFF172B3A), fontSize: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleController.text.trim().isEmpty
                          ? 'ARN SU ARITMA SERVİS FORMU'
                          : _titleController.text.trim(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    const Text('Form No: ÖRNEK-0001'),
                    const Divider(height: 24),
                    ...order.expand((section) => _previewSection(section)),
                    if (_flag('show_tds_in') || _flag('show_tds_out') || _flag('show_tank_pressure')) ...[
                      const Divider(height: 24),
                      const Text('Ölçüm Bilgileri', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      if (_flag('show_tds_in')) const Text('TDS Giriş: 350'),
                      if (_flag('show_tds_out')) const Text('TDS Çıkış: 15'),
                      if (_flag('show_tank_pressure')) const Text('Tank Basıncı: 7'),
                    ],
                    if (_customFields.any((f) => f['enabled'] != false && f['show_on_pdf'] != false)) ...[
                      const Divider(height: 24),
                      const Text('Özel Alanlar', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      ..._customFields.where((f) => f['enabled'] != false && f['show_on_pdf'] != false).map((f) {
                        final type = _normalizedFieldType(f);
                        final sample = switch (type) {
                          'date' => '24.08.2026',
                          'time' => '14:30',
                          'number' => '125',
                          'boolean' => 'Evet',
                          'select' => (f['options'] is List && (f['options'] as List).isNotEmpty)
                              ? (f['options'] as List).first.toString()
                              : 'Seçim',
                          _ => f['placeholder']?.toString().trim().isNotEmpty == true
                              ? f['placeholder'].toString().trim()
                              : '____________________',
                        };
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${f['label']}: $sample'),
                        );
                      }),
                    ],
                    if (_footerController.text.trim().isNotEmpty) ...[
                      const Divider(height: 28),
                      Text(_footerController.text.trim(),
                          style: const TextStyle(color: Color(0xFF60758A), fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _previewSection(String section) sync* {
    if (section == 'customer') {
      yield const Text('Müşteri Bilgileri', style: TextStyle(fontWeight: FontWeight.w900));
      yield const SizedBox(height: 5);
      yield const Text('Müşteri: Abdullah Ceylan');
      if (_flag('show_phone', fallback: true)) yield const Text('Telefon: 0538 000 00 00');
      if (_flag('show_address', fallback: true)) yield const Text('Adres: Bayraklı / İzmir');
      yield const SizedBox(height: 12);
    } else if (section == 'service') {
      if (_flag('show_service_type', fallback: true) ||
          _flag('show_technician', fallback: true) ||
          _flag('show_completed_at', fallback: true)) {
        yield const Text('Servis Bilgileri', style: TextStyle(fontWeight: FontWeight.w900));
        yield const SizedBox(height: 5);
        if (_flag('show_service_type', fallback: true)) yield const Text('Servis Türü: Filtre Değişimi');
        if (_flag('show_technician', fallback: true)) yield const Text('Tekniker: Ali Sevinç');
        if (_flag('show_completed_at', fallback: true)) yield const Text('Tarih: 10.08.2026 14:30');
        yield const SizedBox(height: 12);
      }
    } else if (section == 'description') {
      if (_flag('show_description', fallback: true) || _flag('show_completion_note', fallback: true)) {
        yield const Text('Açıklama / Notlar', style: TextStyle(fontWeight: FontWeight.w900));
        if (_flag('show_description', fallback: true)) yield const Text('Müşteri şikayeti ve servis açıklaması...');
        if (_flag('show_completion_note', fallback: true)) yield const Text('Tamamlama notu...');
        yield const SizedBox(height: 12);
      }
    } else if (section == 'products' && _flag('show_products', fallback: true)) {
      yield const Text('Kullanılan Ürünler', style: TextStyle(fontWeight: FontWeight.w900));
      yield Text(_flag('show_prices', fallback: true)
          ? 'Tam Takım × 1  •  ₺2.200'
          : 'Tam Takım × 1');
      yield const SizedBox(height: 12);
    } else if (section == 'total' && _flag('show_prices', fallback: true)) {
      yield const Align(
        alignment: Alignment.centerRight,
        child: Text('Toplam: ₺2.200', style: TextStyle(fontWeight: FontWeight.w900)),
      );
      yield const SizedBox(height: 16);
    } else if (section == 'signatures') {
      if (_flag('show_customer_signature', fallback: true) ||
          _flag('show_technician_signature', fallback: true)) {
        yield Row(
          children: [
            if (_flag('show_customer_signature', fallback: true))
              const Expanded(child: Text('Müşteri İmzası\n\n________________')),
            if (_flag('show_technician_signature', fallback: true))
              const Expanded(child: Text('Tekniker İmzası\n\n________________')),
          ],
        );
      }
    }
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF12B8C4)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFFB42318) : null,
      ),
    );
  }
}
