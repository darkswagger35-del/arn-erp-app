import 'package:flutter/material.dart';

class NewDevicePage extends StatefulWidget {
  final int? qrId;
  final String? qrCode;
  final int customerId;

  final String? customerName;
  final String? customerPhone;
  final String? customerCity;
  final String? customerDistrict;
  final String? customerAddress;
  final String? customerNote;

  const NewDevicePage({
    super.key,
    this.qrId,
    this.qrCode,
    required this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerCity,
    this.customerDistrict,
    this.customerAddress,
    this.customerNote,
  });

  @override
  State<NewDevicePage> createState() => _NewDevicePageState();
}

class _NewDevicePageState extends State<NewDevicePage> {
  final _formKey = GlobalKey<FormState>();

  final brandController = TextEditingController();
  final modelController = TextEditingController();

  String deviceType = 'Bizden Alınan';
  bool isPump = true;
  bool isOpenCase = false;

  @override
  void dispose() {
    brandController.dispose();
    modelController.dispose();
    super.dispose();
  }

  void _continueToFirstService() {
    if (!_formKey.currentState!.validate()) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cihaz bilgileri hazır. İlk servis ekranına geçilecek.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Cihaz')),
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
                                'Cihaza atanacak QR',
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
                        const Icon(
                          Icons.lock_outline,
                          color: Color(0xFF176B87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                DropdownButtonFormField<String>(
                  initialValue: deviceType,
                  decoration: const InputDecoration(
                    labelText: 'Cihaz Türü',
                    prefixIcon: Icon(Icons.water_drop_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Bizden Alınan',
                      child: Text('Bizden Alınan'),
                    ),
                    DropdownMenuItem(
                      value: 'Dış Cihaz',
                      child: Text('Dış Cihaz'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      deviceType = value;
                    });
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: brandController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Marka',
                    prefixIcon: Icon(Icons.factory_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Marka zorunludur';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 16),

                TextFormField(
                  controller: modelController,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    prefixIcon: Icon(Icons.devices_other_outlined),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E6EA)),
                  ),
                  child: SwitchListTile(
                    value: isPump,
                    title: Text(
                      isPump ? 'Pompalı' : 'Pompasız',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Cihazın pompa durumunu seçin'),
                    secondary: const Icon(Icons.settings_input_component),
                    onChanged: (value) {
                      setState(() {
                        isPump = value;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 14),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E6EA)),
                  ),
                  child: SwitchListTile(
                    value: isOpenCase,
                    title: Text(
                      isOpenCase ? 'Açık Kasa' : 'Kapalı Kasa',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text('Cihazın kasa tipini seçin'),
                    secondary: const Icon(Icons.inventory_2_outlined),
                    onChanged: (value) {
                      setState(() {
                        isOpenCase = value;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  height: 55,
                  child: FilledButton.icon(
                    onPressed: _continueToFirstService,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text(
                      'İLK SERVİSE DEVAM ET',
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
