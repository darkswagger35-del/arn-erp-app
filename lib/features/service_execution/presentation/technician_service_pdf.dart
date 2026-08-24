import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/service_execution_repository.dart';

class TechnicianServicePdf {
  const TechnicianServicePdf._();

  static String _money(double value) =>
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺').format(value);

  static String fileName(TechnicianJob job) {
    final safe = job.customerName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9ğüşöçıİĞÜŞÖÇ]+'), '_');
    return 'servis_formu_${safe.isEmpty ? 'musteri' : safe}_${job.id}.pdf';
  }

  static Future<Uint8List> build({
    required TechnicianJob job,
    required String technicianName,
    required String serviceTypeLabel,
    required String description,
    required String completionNote,
    required List<Map<String, dynamic>> items,
    required double serviceAmount,
    required double extraAmount,
    required double totalAmount,
    required String paymentMethodLabel,
  }) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final productRows = items.map((item) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0;
      return <String>[
        item['product_name']?.toString() ?? '-',
        qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2),
        _money(price),
        _money(qty * price),
      ];
    }).toList(growable: false);

    pw.Widget infoRow(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 105,
                child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Expanded(child: pw.Text(value.trim().isEmpty ? '-' : value.trim())),
            ],
          ),
        );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => [
          pw.Text(
            'SERVİS FORMU',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(DateTime.now()),
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          infoRow('Müşteri', job.customerName),
          infoRow('Telefon', job.phone),
          infoRow('Adres', job.locationText),
          infoRow('Servis Türü', serviceTypeLabel),
          infoRow('Tekniker', technicianName),
          if (job.secretaryName.trim().isNotEmpty) infoRow('Sekreter', job.secretaryName),
          if (description.trim().isNotEmpty) infoRow('Talep / Açıklama', description),
          if (completionNote.trim().isNotEmpty) infoRow('Yapılan İşlem', completionNote),
          pw.SizedBox(height: 12),
          pw.Text('Kullanılan Ürünler', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (productRows.isEmpty)
            pw.Text('Ürün kullanılmadı.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Ürün', 'Adet', 'Birim Fiyat', 'Toplam'],
              data: productRows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          pw.SizedBox(height: 14),
          if (serviceAmount > 0) infoRow('Servis Bedeli', _money(serviceAmount)),
          if (extraAmount > 0) infoRow('Ekstra Ücret', _money(extraAmount)),
          infoRow('Genel Toplam', _money(totalAmount)),
          infoRow('Ödeme', paymentMethodLabel),
          pw.SizedBox(height: 28),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Divider(),
                    pw.Text('Müşteri İmzası', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(width: 30),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Divider(),
                    pw.Text('Tekniker İmzası', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> share({
    required TechnicianJob job,
    required String technicianName,
    required String serviceTypeLabel,
    required String description,
    required String completionNote,
    required List<Map<String, dynamic>> items,
    required double serviceAmount,
    required double extraAmount,
    required double totalAmount,
    required String paymentMethodLabel,
  }) async {
    final bytes = await build(
      job: job,
      technicianName: technicianName,
      serviceTypeLabel: serviceTypeLabel,
      description: description,
      completionNote: completionNote,
      items: items,
      serviceAmount: serviceAmount,
      extraAmount: extraAmount,
      totalAmount: totalAmount,
      paymentMethodLabel: paymentMethodLabel,
    );
    await Printing.sharePdf(bytes: bytes, filename: fileName(job));
  }
}
