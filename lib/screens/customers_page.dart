import 'package:flutter/material.dart';
import 'new_registration_page.dart';

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Müşteriler')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Telefon veya isim ile ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Center(
                child: Text(
                  'Henüz müşteri yok',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Color(0xFF176B87),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('YENİ SERVİS / YENİ KAYIT'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewRegistrationPage()),
          );
        },
      ),
    );
  }
}
