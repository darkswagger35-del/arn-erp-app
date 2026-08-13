import 'package:flutter/material.dart';
import 'new_customer_page.dart';
import 'qr_scanner_page.dart';

class NewRegistrationPage extends StatelessWidget {
  const NewRegistrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Servis / Yeni Kayıt')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),

            const Icon(
              Icons.qr_code_scanner,
              size: 100,
              color: Color(0xFF176B87),
            ),

            const SizedBox(height: 24),

            const Text(
              'QR Etiketi Okut',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF153448),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Yeni cihaz kaydına başlamadan önce QR etiketini okutun.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),

            const SizedBox(height: 40),

            SizedBox(
              height: 60,
              child: FilledButton.icon(
                onPressed: () async {
                  final sonuc = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const QrScannerPage()),
                  );

                  if (sonuc != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Okunan QR: $sonuc')),
                    );
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text(
                  'QR OKUT',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              height: 60,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NewCustomerPage()),
                  );
                },
                icon: const Icon(Icons.arrow_forward),
                label: const Text(
                  "QR'SIZ DEVAM ET",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const Spacer(),

            const Text(
              'QR kodu cihazın benzersiz seri numarası olarak kullanılacaktır.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }
}
