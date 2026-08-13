import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../service_requests/data/models/service_request_model.dart';
import '../../service_requests/presentation/providers/service_request_providers.dart';
import '../../settings/data/company_app_settings.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';

class ServiceDocumentsScreen extends ConsumerStatefulWidget {
  const ServiceDocumentsScreen({super.key});

  @override
  ConsumerState<ServiceDocumentsScreen> createState() =>
      _ServiceDocumentsScreenState();
}

class _ServiceDocumentsScreenState
    extends ConsumerState<ServiceDocumentsScreen> {
  late Future<List<ServiceRequestModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref
        .read(serviceRequestRepositoryProvider)
        .getServiceRequests(status: ServiceRequestStatus.completed);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.admin;
    return ManagementShell(
      role: role,
      title: 'Servis Formları',
      subtitle: 'Tamamlanan servis formlarını görüntüleyin, paylaşın ve yönetin.',
      dark: true,
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/manager/service-form-designer'),
          icon: const Icon(Icons.design_services_outlined),
          label: const Text('Form Tasarımcısı'),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FutureBuilder<List<ServiceRequestModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Kayıtlar yüklenemedi: ${snapshot.error}'),
              ),
            );
          }

          final rows = snapshot.data ?? const <ServiceRequestModel>[];
          final totalValue = rows.fold<double>(0, (sum, e) => sum + e.price);
          final thisMonth = rows.where((e) {
            final d = (e.updatedAt ?? e.createdAt ?? DateTime(2000)).toLocal();
            final n = DateTime.now();
            return d.year == n.year && d.month == n.month;
          }).length;
          final withProducts = rows.where((e) => e.items.isNotEmpty || e.plannedProductName.isNotEmpty).length;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth >= 1000 ? (c.maxWidth - 36) / 4 : c.maxWidth >= 620 ? (c.maxWidth - 12) / 2 : c.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _DocumentMetric(width: w, title: 'Toplam Form', value: rows.length.toString(), subtitle: 'Tamamlanan servis', icon: Icons.description_outlined, color: const Color(0xFF22B8CF)),
                      _DocumentMetric(width: w, title: 'Bu Ay', value: thisMonth.toString(), subtitle: 'Oluşturulan form', icon: Icons.calendar_month_outlined, color: const Color(0xFF8A6DF1)),
                      _DocumentMetric(width: w, title: 'Ürünlü Form', value: withProducts.toString(), subtitle: 'Parça veya ürün işlendi', icon: Icons.inventory_2_outlined, color: const Color(0xFFF4B740)),
                      _DocumentMetric(width: w, title: 'Toplam Tutar', value: _money(totalValue), subtitle: 'Formların toplamı', icon: Icons.payments_outlined, color: const Color(0xFF35C978)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF22B8CF).withOpacity(.14), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.folder_copy_outlined, color: Color(0xFF22C7D4))),
                      const SizedBox(width: 12),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Tamamlanan Servis Belgeleri', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        Text('PDF önizleyin, paylaşın veya müşteriye WhatsApp mesajı gönderin.', style: TextStyle(color: Color(0xFF91A4B7), fontSize: 12)),
                      ])),
                      Text('${rows.length} kayıt', style: const TextStyle(color: Color(0xFF22C7D4), fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (rows.isEmpty)
                const _DocumentEmpty()
              else
                ...rows.map((request) => _DocumentCard(
                      request: request,
                      money: _money,
                      onPreview: () => _previewPdf(request),
                      onEdit: () => _editForm(request),
                      onShare: () => _sharePdf(request),
                      onWhatsApp: () => _sendPdfToWhatsApp(request),
                    )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _previewPdf(ServiceRequestModel request) async {
    await Printing.layoutPdf(
      onLayout: (_) => _buildPdf(request),
      name: _fileName(request),
    );
  }

  Future<void> _sharePdf(ServiceRequestModel request) async {
    final bytes = await _buildPdf(request);
    await Printing.sharePdf(bytes: bytes, filename: _fileName(request));
  }

  Future<void> _sendPdfToWhatsApp(ServiceRequestModel request) async {
    final bytes = await _buildPdf(request);
    // Windows/WhatsApp URI şeması doğrudan bir dosyayı belirli kişiye ekleyemez.
    // Bu yüzden önce PDF paylaşım ekranını açıyoruz, ardından müşterinin sohbetini
    // hazır mesajla açıyoruz. Mobilde paylaşım ekranından WhatsApp seçilebilir.
    await Printing.sharePdf(bytes: bytes, filename: _fileName(request));

    var phone = request.customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.startsWith('0')) phone = '90${phone.substring(1)}';
    if (phone.isEmpty) {
      _showMessage('PDF hazırlandı ancak müşterinin telefon numarası bulunamadı.');
      return;
    }
    final settings = await ref.read(companyAppSettingsProvider.future);
    final message = settings.serviceCompletedTemplate
        .replaceAll('{{musteri}}', request.customerName)
        .replaceAll('{{müşteri}}', request.customerName)
        .replaceAll('{{tutar}}', _money(request.price));
    final uri = Uri.https('wa.me', '/$phone', {'text': message});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _showMessage('WhatsApp açılamadı.');
  }

  Future<void> _editForm(ServiceRequestModel request) async {
    ServiceRequestType serviceType = request.serviceType;
    final description = TextEditingController(text: request.description);
    final completionNote = TextEditingController(text: request.completionNote);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Theme(
          data: Theme.of(context).copyWith(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF12B8C4),
              brightness: Brightness.light,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF7F9FC),
              labelStyle: const TextStyle(color: Color(0xFF60758A)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1EA)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD8E1EA)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF12B8C4), width: 1.5),
              ),
            ),
          ),
          child: AlertDialog(
            backgroundColor: const Color(0xFFF5F8FB),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
            contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: const Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFDDF7F8),
                  child: Icon(Icons.edit_document, color: Color(0xFF0AA8B5)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Servis Formunu Düzenle', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF102A43))),
                      SizedBox(height: 3),
                      Text('Form ve PDF içeriğini güncelle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6D8297))),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.sizeOf(context).width < 760 ? MediaQuery.sizeOf(context).width * .82 : 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SERVİS BİLGİLERİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .7, color: Color(0xFF60758A))),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ServiceRequestType>(
                      value: serviceType,
                      decoration: const InputDecoration(labelText: 'Servis Türü', prefixIcon: Icon(Icons.home_repair_service_outlined)),
                      items: ServiceRequestType.values
                          .map((type) => DropdownMenuItem(value: type, child: Text(type.label)))
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) setDialogState(() => serviceType = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: description,
                      maxLines: 4,
                      style: const TextStyle(color: Color(0xFF102A43)),
                      decoration: const InputDecoration(
                        labelText: 'Açıklama / Müşteri Talebi',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(padding: EdgeInsets.only(bottom: 70), child: Icon(Icons.notes_rounded)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: completionNote,
                      maxLines: 4,
                      style: const TextStyle(color: Color(0xFF102A43)),
                      decoration: const InputDecoration(
                        labelText: 'Tamamlama Notu / Yapılan İşlem',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(padding: EdgeInsets.only(bottom: 70), child: Icon(Icons.task_alt_rounded)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF8FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB8E8EC)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF0AA8B5)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kaydettiğiniz servis türü, açıklama ve tamamlama notu hem servis kaydında hem de bundan sonra oluşturulan PDF’de güncel görünür. Ürün/adet/fiyat geçmişi korunur.',
                              style: TextStyle(color: Color(0xFF496779), fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Değişiklikleri Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      try {
        await ref.read(serviceRequestRepositoryProvider).updateServiceRequest(
              request.copyWith(
                serviceType: serviceType,
                description: description.text.trim(),
                completionNote: completionNote.text.trim(),
              ),
            );
        if (mounted) {
          setState(_reload);
          _showMessage('Servis formu güncellendi. PDF yeni bilgilerle üretilecek.');
        }
      } catch (error) {
        if (mounted) _showMessage('Form güncellenemedi: $error');
      }
    }
    description.dispose();
    completionNote.dispose();
  }

  Future<Uint8List> _buildPdf(ServiceRequestModel request) async {
    final settings = await ref.read(companyAppSettingsProvider.future);
    final form = settings.serviceFormConfig;
    bool show(String key, {bool fallback = true}) {
      final value = form[key];
      return value is bool ? value : fallback;
    }

    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );
    final completedAt =
        (request.updatedAt ?? request.createdAt ?? DateTime.now()).toLocal();
    final technician = request.assignedTechnicianName.isNotEmpty
        ? request.assignedTechnicianName
        : request.technicianNameSnapshot;

    final productRows = <List<String>>[];
    if (request.items.isNotEmpty) {
      for (final item in request.items) {
        productRows.add([
          item.productName.isEmpty ? '-' : item.productName,
          item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
          if (show('show_prices')) _money(item.unitPrice),
          if (show('show_prices')) _money(item.lineTotal),
        ]);
      }
    } else if (request.plannedProductName.isNotEmpty) {
      final total = request.plannedQuantity * request.plannedUnitPrice;
      productRows.add([
        request.plannedProductName,
        request.plannedQuantity
            .toStringAsFixed(request.plannedQuantity % 1 == 0 ? 0 : 2),
        if (show('show_prices')) _money(request.plannedUnitPrice),
        if (show('show_prices')) _money(total),
      ]);
    }

    List<String> sectionOrder() {
      final raw = form['section_order'];
      final values = raw is List
          ? raw.map((e) => e.toString()).toList(growable: true)
          : <String>[];
      const defaults = [
        'customer',
        'service',
        'description',
        'products',
        'total',
        'signatures',
      ];
      for (final item in defaults) {
        if (!values.contains(item)) values.add(item);
      }
      return values;
    }

    List<pw.Widget> section(String key) {
      switch (key) {
        case 'customer':
          return [
            _pdfSectionTitle('Müşteri Bilgileri'),
            _pdfInfoRow('Müşteri', request.customerName),
            if (show('show_phone')) _pdfInfoRow('Telefon', request.customerPhone),
            if (show('show_address')) _pdfInfoRow('Adres', request.customerAddress),
            pw.SizedBox(height: 10),
          ];
        case 'service':
          final rows = <pw.Widget>[
            _pdfSectionTitle('Servis Bilgileri'),
            if (show('show_service_type'))
              _pdfInfoRow('Servis Türü', request.serviceType.label),
            if (show('show_technician'))
              _pdfInfoRow('Teknisyen', technician.isEmpty ? '-' : technician),
            if (show('show_completed_at'))
              _pdfInfoRow(
                'Tamamlanma Tarihi',
                DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(completedAt),
              ),
            _pdfInfoRow('Durum', request.status.label),
            pw.SizedBox(height: 10),
          ];
          return rows;
        case 'description':
          if (!show('show_description') && !show('show_completion_note')) {
            return const <pw.Widget>[];
          }
          return [
            _pdfSectionTitle('Açıklama / Notlar'),
            if (show('show_description'))
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  request.description.isEmpty ? '-' : request.description,
                ),
              ),
            if (show('show_completion_note')) ...[
              pw.SizedBox(height: 8),
              pw.Text('Tamamlama Notu',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(request.completionNote.isEmpty ? '-' : request.completionNote),
            ],
            pw.SizedBox(height: 12),
          ];
        case 'products':
          if (!show('show_products') || productRows.isEmpty) {
            return const <pw.Widget>[];
          }
          return [
            _pdfSectionTitle('Kullanılan Ürünler'),
            pw.TableHelper.fromTextArray(
              headers: show('show_prices')
                  ? const ['Ürün', 'Adet', 'Birim Fiyat', 'Toplam']
                  : const ['Ürün', 'Adet'],
              data: productRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColors.grey400),
            ),
            pw.SizedBox(height: 12),
          ];
        case 'total':
          if (!show('show_prices')) return const <pw.Widget>[];
          return [
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Toplam Tutar: ${_money(request.price)}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 16),
          ];
        case 'signatures':
          final customerSignature = show('show_customer_signature');
          final technicianSignature = show('show_technician_signature');
          if (!customerSignature && !technicianSignature) {
            return const <pw.Widget>[];
          }
          return [
            pw.SizedBox(height: 18),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (customerSignature) _pdfSignature('Müşteri İmzası'),
                if (technicianSignature) _pdfSignature('Teknisyen İmzası'),
              ],
            ),
          ];
      }
      return const <pw.Widget>[];
    }

    final customFields = form['custom_fields'] is List
        ? (form['custom_fields'] as List).whereType<Map>().toList()
        : const <Map>[];

    final body = <pw.Widget>[];
    for (final key in sectionOrder()) {
      body.addAll(section(key));
    }
    if (customFields.isNotEmpty) {
      body.add(_pdfSectionTitle('Ek Bilgiler'));
      for (final field in customFields) {
        if (field['enabled'] == false) continue;
        body.add(_pdfInfoRow(field['label']?.toString() ?? 'Alan', ''));
      }
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    settings.serviceFormTitle.trim().isEmpty
                        ? 'ARN SU ARITMA SERVİS FORMU'
                        : settings.serviceFormTitle.trim(),
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Servis Tamamlama Formu'),
                ],
              ),
              pw.Text('Form No: ${request.id ?? '-'}',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 10),
          ...body,
          if (settings.serviceFormFooter.trim().isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Divider(),
            pw.SizedBox(height: 6),
            pw.Text(settings.serviceFormFooter.trim(),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _pdfSectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _pdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  pw.Widget _pdfSignature(String label) {
    return pw.SizedBox(
      width: 180,
      child: pw.Column(
        children: [
          pw.Container(
            height: 45,
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide()),
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  String _fileName(ServiceRequestModel request) {
    final safeName = request.customerName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9çÇğĞıİöÖşŞüÜ]+'), '_');
    return 'servis_formu_${safeName}_${request.id ?? ''}.pdf';
  }

  String _money(num value) {
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(value);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}


class _DocumentMetric extends StatelessWidget {
  const _DocumentMetric({required this.width, required this.title, required this.value, required this.subtitle, required this.icon, required this.color});
  final double width;
  final String title, value, subtitle;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
    const SizedBox(width: 13),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12, fontWeight: FontWeight.w700)),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      Text(subtitle, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ])),
  ]))));
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.request, required this.money, required this.onPreview, required this.onEdit, required this.onShare, required this.onWhatsApp});
  final ServiceRequestModel request;
  final String Function(double) money;
  final VoidCallback onPreview, onEdit, onShare, onWhatsApp;
  @override
  Widget build(BuildContext context) {
    final date = (request.updatedAt ?? request.createdAt ?? DateTime.now()).toLocal();
    final technician = request.assignedTechnicianName.isNotEmpty ? request.assignedTechnicianName : request.technicianNameSnapshot;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF22B8CF).withOpacity(.14), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF22C7D4))),
            const SizedBox(width: 13),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.customerName.isEmpty ? 'Müşteri' : request.customerName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 3),
              Text('${request.serviceType.label} • ${money(request.price)}', style: const TextStyle(color: Color(0xFFC0CED9), fontWeight: FontWeight.w600)),
            ])),
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Teknisyen', style: TextStyle(color: Color(0xFF71879A), fontSize: 11)),
              Text(technician.isEmpty ? '-' : technician, style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tamamlanma', style: TextStyle(color: Color(0xFF71879A), fontSize: 11)),
              Text(DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(date), style: const TextStyle(fontWeight: FontWeight.w700)),
            ])),
            Wrap(spacing: 6, children: [
              FilledButton.icon(onPressed: onPreview, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Önizle')),
              OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Düzenle')),
              OutlinedButton.icon(onPressed: onShare, icon: const Icon(Icons.download_outlined, size: 18), label: const Text('PDF İndir / Paylaş')),
              OutlinedButton.icon(onPressed: onWhatsApp, icon: const Icon(Icons.chat_outlined, size: 18), label: const Text('PDF → WhatsApp')),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DocumentEmpty extends StatelessWidget {
  const _DocumentEmpty();
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 70), child: Column(children: [
    Container(width: 76, height: 76, decoration: BoxDecoration(color: const Color(0xFF22B8CF).withOpacity(.12), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.description_outlined, size: 40, color: Color(0xFF22C7D4))),
    const SizedBox(height: 18),
    const Text('Henüz tamamlanmış servis formu yok', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    const SizedBox(height: 6),
    const Text('Tamamlanan servisler otomatik olarak burada belgelenecek.', style: TextStyle(color: Color(0xFF91A4B7))),
  ])));
}
