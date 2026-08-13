import 'package:flutter/material.dart';

import '../services/customer_service.dart';
import 'new_device_page.dart';

class NewCustomerPage extends StatefulWidget {
  final String? qrCode;
  final int? qrId;

  const NewCustomerPage({super.key, this.qrCode, this.qrId});

  @override
  State<NewCustomerPage> createState() => _NewCustomerPageState();
}

class _NewCustomerPageState extends State<NewCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _continueToDevice() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final customerId = await CustomerService.createCustomer(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        address: _addressController.text.trim(),
        note: _noteController.text.trim(),
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NewDevicePage(
            qrId: widget.qrId,
            qrCode: widget.qrCode,
            customerId: customerId,
            customerName: _fullNameController.text.trim(),
            customerPhone: _phoneController.text.trim(),
            customerCity: _cityController.text.trim(),
            customerDistrict: _districtController.text.trim(),
            customerAddress: _addressController.text.trim(),
            customerNote: _noteController.text.trim(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Müşteri kaydedilemedi: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Müşteri')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.qrCode != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4F8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF176B87)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.qr_code_rounded,
                          size: 38,
                          color: Color(0xFF176B87),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'QR başarıyla okundu',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.qrCode!,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF153448),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ad soyad zorunludur';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Telefon',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Telefon zorunludur';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cityController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'İl',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _districtController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'İlçe',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressController,
                  maxLines: 3,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Açık Adres',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Adres zorunludur';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Not',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _isSaving ? null : _continueToDevice,
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'DEVAM ET',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
