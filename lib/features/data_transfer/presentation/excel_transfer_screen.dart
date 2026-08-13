import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/excel_transfer_repository.dart';

class ExcelTransferScreen extends ConsumerStatefulWidget {
  const ExcelTransferScreen({super.key});

  @override
  ConsumerState<ExcelTransferScreen> createState() => _ExcelTransferScreenState();
}

class _ExcelTransferScreenState extends ConsumerState<ExcelTransferScreen> {
  late final ExcelTransferRepository _repo;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _repo = ExcelTransferRepository(Supabase.instance.client);
  }

  Future<void> _createTemplate() async {
    await _run(() async {
      final refs = await _repo.importReferenceData();
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final sheet = excel['Iceri_Aktar'];
      _appendTextRow(sheet, const [
        'Ad Soyad',
        'Telefon',
        'İl',
        'İlçe',
        'Adres',
        'İşlem Tarihi',
        'Ürün',
        'Adet',
        'Toplam Tutar',
        'Ödeme Durumu',
        'Ödeme Tarihi',
        'Sekreter',
        'Tekniker',
      ]);
      _appendTextRow(sheet, const [
        'Örnek Müşteri',
        '5321234567',
        'İzmir',
        'Buca',
        'Örnek Mah. No:1',
        '08.08.2026',
        'Tam Takım',
        '1',
        '1500',
        'Ödendi',
        '',
        '',
        '',
      ]);

      final products = excel['Urun_Listesi'];
      _appendTextRow(products, const ['Ürün', 'Bakım Süresi (Ay)']);
      for (final p in refs.products) {
        _appendTextRow(products, [
          p['name']?.toString() ?? '',
          p['maintenance_months']?.toString() ?? '0',
        ]);
      }

      final staff = excel['Personel_Listesi'];
      _appendTextRow(staff, const ['Ad Soyad', 'Rol']);
      for (final p in refs.staff) {
        _appendTextRow(staff, [
          p['full_name']?.toString() ?? '',
          _roleLabel(p['role']?.toString() ?? ''),
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw StateError('Excel dosyası oluşturulamadı.');
      await _saveBytes(bytes, 'ARN_ERP_Excel_Aktarim_Sablonu.xlsx');
      _setStatus('Excel içe aktarım şablonu hazırlandı.');
    });
  }

  Future<void> _exportAll() async {
    await _run(() async {
      final results = await Future.wait([
        _repo.exportCustomers(),
        _repo.exportHistory(),
        _repo.exportProducts(),
        _repo.exportStaff(),
      ]);
      final customers = results[0];
      final history = results[1];
      final products = results[2];
      final staff = results[3];

      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final customerSheet = excel['Musteriler'];
      _appendTextRow(customerSheet, const [
        'Müşteri ID', 'Tip', 'Ad Soyad', 'Firma', 'Telefon', 'Alternatif Telefon',
        'E-posta', 'İl', 'İlçe', 'Mahalle', 'Adres', 'Not', 'Aktif', 'Kayıt Tarihi',
      ]);
      for (final c in customers) {
        _appendTextRow(customerSheet, [
          c['id']?.toString() ?? '',
          c['customer_type']?.toString() == 'corporate' ? 'Kurumsal' : 'Bireysel',
          c['full_name']?.toString() ?? '',
          c['company_name']?.toString() ?? '',
          c['phone']?.toString() ?? '',
          c['alternative_phone']?.toString() ?? '',
          c['email']?.toString() ?? '',
          c['city']?.toString() ?? '',
          c['district']?.toString() ?? '',
          c['neighborhood']?.toString() ?? '',
          c['address']?.toString() ?? '',
          c['notes']?.toString() ?? '',
          c['is_active'] == false ? 'Hayır' : 'Evet',
          _formatDate(c['registration_date'] ?? c['created_at']),
        ]);
      }

      final historySheet = excel['Islem_Gecmisi'];
      _appendTextRow(historySheet, const [
        'Kaynak', 'Tarih', 'Müşteri', 'İşlem Tipi', 'Ürün', 'Adet', 'Tutar',
        'Ödeme Durumu', 'Tekniker', 'Sekreter', 'Açıklama',
      ]);
      for (final row in history) {
        _appendTextRow(historySheet, [
          row['source_type']?.toString() == 'historical' ? 'Excel / Eski Kayıt' : 'Servis',
          _formatDate(row['transaction_date']),
          row['customer_name']?.toString() ?? '',
          row['service_type']?.toString() ?? '',
          row['product_name']?.toString() ?? '',
          _numText(row['quantity']),
          _numText(row['amount']),
          row['payment_status']?.toString() ?? '',
          row['technician_name']?.toString() ?? '',
          row['secretary_name']?.toString() ?? '',
          row['description']?.toString() ?? '',
        ]);
      }

      final productSheet = excel['Urunler'];
      _appendTextRow(productSheet, const [
        'Ürün ID', 'Ürün', 'Kategori', 'Birim', 'Stok', 'Bakım Süresi (Ay)', 'Aktif',
      ]);
      for (final p in products) {
        final category = p['product_categories'] is Map<String, dynamic>
            ? p['product_categories'] as Map<String, dynamic>
            : const <String, dynamic>{};
        _appendTextRow(productSheet, [
          p['id']?.toString() ?? '',
          p['name']?.toString() ?? '',
          category['name']?.toString() ?? '',
          p['unit']?.toString() ?? '',
          _numText(p['stock_quantity']),
          p['maintenance_months']?.toString() ?? '0',
          p['is_active'] == false ? 'Hayır' : 'Evet',
        ]);
      }

      final staffSheet = excel['Personel'];
      _appendTextRow(staffSheet, const ['Personel ID', 'Ad Soyad', 'Rol', 'Aktif']);
      for (final p in staff) {
        _appendTextRow(staffSheet, [
          p['id']?.toString() ?? '',
          p['full_name']?.toString() ?? '',
          _roleLabel(p['role']?.toString() ?? ''),
          p['is_active'] == false ? 'Hayır' : 'Evet',
        ]);
      }

      final bytes = excel.encode();
      if (bytes == null) throw StateError('Excel dosyası oluşturulamadı.');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await _saveBytes(bytes, 'ARN_ERP_Yedek_$stamp.xlsx');
      _setStatus(
        '${customers.length} müşteri ve ${history.length} işlem Excel’e aktarıldı.',
      );
    });
  }

  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showError('Dosya okunamadı. Lütfen .xlsx dosyasını tekrar seçin.');
      return;
    }

    await _run(() async {
      final excel = Excel.decodeBytes(bytes);
      final parsed = _parseImportRows(excel);
      if (parsed.rows.isEmpty) {
        throw StateError(parsed.errors.isEmpty
            ? 'Aktarılacak kayıt bulunamadı.'
            : parsed.errors.join('\n'));
      }

      final preview = await _confirmImport(parsed.rows, parsed.errors);
      if (!preview || !mounted) return;

      final batchId = 'APP_XLSX_${_fnv1a(bytes).toRadixString(16).toUpperCase()}';
      final result = await _repo.importRows(batchId: batchId, rows: parsed.rows);
      if (!mounted) return;

      final allErrors = <String>[...parsed.errors, ...result.errors];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Excel aktarımı tamamlandı'),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width < 760 ? MediaQuery.sizeOf(context).width * .82 : 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Başarılı: ${result.imported}'),
                  Text('Daha önce aktarılmış / atlanan: ${result.skipped}'),
                  Text('Hatalı: ${allErrors.length}'),
                  if (allErrors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Hata detayları:', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    ...allErrors.take(30).map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $e'),
                        )),
                    if (allErrors.length > 30)
                      Text('... ve ${allErrors.length - 30} hata daha'),
                  ],
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
        ),
      );
      _setStatus('${result.imported} kayıt başarıyla içeri aktarıldı.');
    });
  }

  _ParsedImport _parseImportRows(Excel excel) {
    final aliases = <String, List<String>>{
      'name': ['ad soyad', 'musteri adi', 'müşteri adı', 'adi soyadi', 'adı soyadı', 'isim'],
      'phone': ['telefon', 'tel', 'gsm', 'telefon no', 'telefon numarasi', 'telefon numarası'],
      'city': ['il', 'şehir', 'sehir'],
      'district': ['ilce', 'ilçe'],
      'address': ['adres', 'acik adres', 'açık adres'],
      'date': ['islem tarihi', 'işlem tarihi', 'tarih', 'kayit tarihi', 'kayıt tarihi'],
      'product': ['urun', 'ürün', 'urun adi', 'ürün adı', 'yapilan islem', 'yapılan işlem', 'islem', 'işlem'],
      'quantity': ['adet', 'miktar'],
      'amount': ['toplam tutar', 'tutar', 'toplam', 'ciro'],
      'payment': ['odeme durumu', 'ödeme durumu', 'odeme', 'ödeme'],
      'due': ['odeme tarihi', 'ödeme tarihi', 'vade tarihi'],
      'secretary': ['sekreter', 'kaydi acan sekreter', 'kaydı açan sekreter'],
      'technician': ['tekniker', 'teknisyen', 'giden tekniker', 'giden teknisyen'],
    };

    Sheet? selected;
    Map<String, int>? columns;
    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;
      final header = sheet.rows.first.map(_cellText).toList(growable: false);
      final found = <String, int>{};
      for (final field in aliases.entries) {
        for (var i = 0; i < header.length; i++) {
          final h = _normalizeHeader(header[i]);
          if (field.value.any((a) => _normalizeHeader(a) == h)) {
            found[field.key] = i;
            break;
          }
        }
      }
      if (found.containsKey('name') && found.containsKey('date') && found.containsKey('product')) {
        selected = sheet;
        columns = found;
        break;
      }
    }
    if (selected == null || columns == null) {
      return const _ParsedImport(
        rows: [],
        errors: ['Başlıklar bulunamadı. Şablonu indirip aynı sütun başlıklarını kullanın.'],
      );
    }

    final rows = <ExcelImportRow>[];
    final errors = <String>[];
    for (var i = 1; i < selected.rows.length; i++) {
      final sourceRow = i + 1;
      final row = selected.rows[i];
      String value(String key) {
        final index = columns![key];
        if (index == null || index >= row.length) return '';
        return _cellText(row[index]).trim();
      }

      final name = value('name');
      final product = value('product');
      final dateText = value('date');
      if (name.isEmpty && product.isEmpty && dateText.isEmpty) continue;
      if (name.isEmpty) {
        errors.add('Satır $sourceRow: Ad Soyad boş.');
        continue;
      }
      if (product.isEmpty) {
        errors.add('Satır $sourceRow: Ürün boş.');
        continue;
      }
      final date = _parseDate(dateText);
      if (date == null) {
        errors.add('Satır $sourceRow: Tarih okunamadı ($dateText).');
        continue;
      }
      final quantity = _parseNumber(value('quantity'), fallback: 1);
      final amount = _parseNumber(value('amount'), fallback: 0);
      if (quantity <= 0) {
        errors.add('Satır $sourceRow: Adet 0’dan büyük olmalı.');
        continue;
      }
      final paymentStatus = _paymentStatus(value('payment'));
      final due = value('due').isEmpty ? null : _parseDate(value('due'));

      rows.add(ExcelImportRow(
        sourceRow: sourceRow,
        fullName: name,
        phone: value('phone'),
        city: value('city'),
        district: value('district'),
        address: value('address'),
        transactionDate: date,
        productName: product,
        quantity: quantity,
        amount: amount,
        paymentStatus: paymentStatus,
        paymentDueDate: due,
        secretaryName: value('secretary'),
        technicianName: value('technician'),
      ));
    }
    return _ParsedImport(rows: rows, errors: errors);
  }

  Future<bool> _confirmImport(List<ExcelImportRow> rows, List<String> parseErrors) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excel içeri aktarılsın mı?'),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width < 790 ? MediaQuery.sizeOf(context).width * .82 : 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${rows.length} geçerli kayıt bulundu.'),
                if (parseErrors.isNotEmpty)
                  Text('${parseErrors.length} satır biçim hatası nedeniyle atlanacak.'),
                const SizedBox(height: 10),
                const Text(
                  'Aynı telefon numarası sistemde varsa mevcut müşteriye işlem eklenir. '
                  'Yeni telefonlar yeni müşteri olarak açılır. Ürün ve personel isimleri sistemdeki isimlerle eşleşmelidir.',
                ),
                const SizedBox(height: 12),
                const Text('İlk kayıtlar:', style: TextStyle(fontWeight: FontWeight.w800)),
                ...rows.take(5).map((r) => Text(
                      '• ${r.fullName} — ${DateFormat('dd.MM.yyyy').format(r.transactionDate)} — ${r.productName} — ${r.quantity} adet',
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('İçeri Aktar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _saveBytes(List<int> bytes, String fileName) async {
    await FilePicker.platform.saveFile(
      dialogTitle: 'Excel dosyasını kaydet',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showError(_cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _showError(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), backgroundColor: Colors.red.shade700),
    );
  }

  static void _appendTextRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map(TextCellValue.new).toList(growable: false));
  }

  static String _cellText(Data? cell) => cell?.value?.toString() ?? '';

  static String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  static DateTime? _parseDate(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final direct = DateTime.tryParse(text);
    if (direct != null) return DateTime(direct.year, direct.month, direct.day);
    for (final pattern in ['dd.MM.yyyy', 'd.M.yyyy', 'dd/MM/yyyy', 'd/M/yyyy', 'dd-MM-yyyy', 'd-M-yyyy']) {
      try {
        return DateFormat(pattern).parseStrict(text);
      } catch (_) {}
    }
    final serial = double.tryParse(text.replaceAll(',', '.'));
    if (serial != null && serial > 20000 && serial < 100000) {
      return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    }
    final match = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
    if (match != null) {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
    }
    return null;
  }

  static double _parseNumber(String value, {required double fallback}) {
    var text = value.trim().replaceAll('₺', '').replaceAll('TL', '').replaceAll('tl', '').replaceAll(' ', '');
    if (text.isEmpty) return fallback;
    if (text.contains(',') && text.contains('.')) {
      if (text.lastIndexOf(',') > text.lastIndexOf('.')) {
        text = text.replaceAll('.', '').replaceAll(',', '.');
      } else {
        text = text.replaceAll(',', '');
      }
    } else if (text.contains(',')) {
      text = text.replaceAll(',', '.');
    }
    return double.tryParse(text) ?? fallback;
  }

  static String _paymentStatus(String value) {
    final normalized = _normalizeHeader(value);
    if (normalized.contains('borc') || normalized.contains('odenmedi') || normalized == 'debt') {
      return 'debt';
    }
    return 'paid';
  }

  static String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? value?.toString() ?? '' : DateFormat('dd.MM.yyyy').format(date.toLocal());
  }

  static String _numText(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (n == null) return value?.toString() ?? '';
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _roleLabel(String role) => switch (role) {
        'admin' => 'Yönetici',
        'manager' => 'Yönetici',
        'secretary' => 'Sekreter',
        'technician' => 'Tekniker',
        _ => role,
      };

  static int _fnv1a(List<int> bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _cleanError(Object error) {
    final value = error.toString();
    return value.startsWith('Bad state: ') ? value.substring(11) : value;
  }

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.manager,
      title: 'Excel İçeri / Dışarı Aktar',
      subtitle: 'Müşteri ve işlem geçmişini Excel ile toplu yönetin.',
      dark: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 3),
                if (_busy) const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _TransferCard(
                      icon: Icons.download_rounded,
                      title: 'Excel Dışarı Aktar',
                      description: 'Müşteriler, işlem geçmişi, ürünler ve personel ayrı sayfalarda tek Excel dosyasına çıkar.',
                      buttonText: 'Excel Oluştur',
                      onPressed: _busy ? null : _exportAll,
                    ),
                    _TransferCard(
                      icon: Icons.upload_file_rounded,
                      title: 'Excel İçeri Aktar',
                      description: 'Eski müşteri ve satış/bakım kayıtlarını toplu ekler. Aynı telefon varsa mevcut müşteriye işler.',
                      buttonText: 'Excel Seç ve Aktar',
                      onPressed: _busy ? null : _importExcel,
                    ),
                    _TransferCard(
                      icon: Icons.table_view_rounded,
                      title: 'Aktarım Şablonu',
                      description: 'Doğru sütunları, güncel ürün listesini ve personel isimlerini içeren hazır Excel şablonu oluşturur.',
                      buttonText: 'Şablonu İndir',
                      onPressed: _busy ? null : _createTemplate,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A26),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF223241)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('İçe aktarım mantığı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
                      Text('• Telefon numarası mevcutsa yeni müşteri açılmaz; işlem mevcut müşteriye eklenir.'),
                      Text('• Ürün adı sistemdeki aktif ürün adıyla eşleşir ve bakım süresi otomatik uygulanır.'),
                      Text('• Sekreter / tekniker yazılmışsa personel performansına doğru kişiyle yansır.'),
                      Text('• Aynı Excel dosyası tekrar seçilirse daha önce aktarılan satırlar yeniden eklenmez.'),
                      Text('• Hatalı satırlar diğer kayıtları durdurmaz; aktarım sonunda hata listesi gösterilir.'),
                    ],
                  ),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(_status, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 325,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF12313B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF12B8C4)),
              ),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(description, style: const TextStyle(color: Color(0xFFA6B5C4), height: 1.35)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(icon, size: 19),
                  label: Text(buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParsedImport {
  const _ParsedImport({required this.rows, required this.errors});
  final List<ExcelImportRow> rows;
  final List<String> errors;
}
