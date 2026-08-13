import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/arn_app_bar.dart';
import '../../../../core/widgets/management_shell.dart';
import '../../../../core/auth/app_role.dart';
import '../../data/models/customer_model.dart';
import '../../../settings/data/company_app_settings.dart';
import '../providers/customer_providers.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, required this.role, this.customerId});

  final AppRole role;
  final String? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final fullNameController = TextEditingController();
  final phoneController = TextEditingController();
  final cityController = TextEditingController();
  final districtController = TextEditingController();
  final neighborhoodController = TextEditingController();
  final addressController = TextEditingController();
  final notesController = TextEditingController();
  final registrationDateController = TextEditingController();

  bool isActive = true;
  DateTime registrationDate = DateTime.now();
  bool _isFormInitialized = false;

  @override
  void initState() {
    super.initState();
    registrationDateController.text = _formatManualDate(registrationDate);

    if (widget.customerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.customerId == null) {
          return;
        }

        ref.read(customerControllerProvider).loadCustomer(widget.customerId!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant CustomerFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.customerId != widget.customerId) {
      _resetFormState();

      if (widget.customerId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.customerId == null) {
            return;
          }

          ref.read(customerControllerProvider).loadCustomer(widget.customerId!);
        });
      }
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    phoneController.dispose();
    cityController.dispose();
    districtController.dispose();
    neighborhoodController.dispose();
    addressController.dispose();
    notesController.dispose();
    registrationDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(customerControllerProvider);
    final state = controller.state;
    final appSettings = ref.watch(companyAppSettingsProvider).asData?.value;
    final phoneRequired = appSettings?.customerRule('phone_required', fallback: true) ?? true;
    final cityRequired = appSettings?.customerRule('city_required', fallback: true) ?? true;
    final districtRequired = appSettings?.customerRule('district_required', fallback: true) ?? true;
    final addressRequired = appSettings?.customerRule('address_required', fallback: true) ?? true;

    final isEditing = widget.customerId != null;

    if (isEditing &&
        state.currentCustomer != null &&
        state.currentCustomer!.id == widget.customerId &&
        !_isFormInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _isFormInitialized ||
            state.currentCustomer == null ||
            state.currentCustomer!.id != widget.customerId) {
          return;
        }

        _populateFields(state.currentCustomer!);
      });
    }

    return ManagementShell(
      role: widget.role,
      title: isEditing ? 'Müşteri Düzenle' : 'Yeni Müşteri',
      subtitle: isEditing
          ? 'Müşteri iletişim ve adres bilgilerini güncelleyin.'
          : 'Yeni müşteriyi hızlı ve eksiksiz şekilde sisteme kaydedin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(_dashboardFallbackRoute()),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Panele Dön'),
        ),
      ],
      child: state.isLoading && isEditing && !_isFormInitialized
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null && isEditing && state.currentCustomer == null
              ? Center(child: Padding(padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 12 : 24), child: Text(state.errorMessage!)))
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FormHero(isEditing: isEditing),
                            const SizedBox(height: 18),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final mobile = constraints.maxWidth < 760;
                                final customerSection = _FormSection(
                                  icon: Icons.person_outline_rounded,
                                  title: 'Müşteri Bilgileri',
                                  subtitle: 'Temel iletişim ve kayıt bilgileri',
                                  child: Column(children: [
                                    if (mobile) ...[
                                      TextFormField(
                                        controller: fullNameController,
                                        textCapitalization: TextCapitalization.words,
                                        decoration: const InputDecoration(labelText: 'Ad Soyad *', prefixIcon: Icon(Icons.person_outline)),
                                        validator: (value) => value == null || value.trim().length < 3 ? 'Geçerli bir ad soyad girin' : null,
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: phoneController,
                                        keyboardType: TextInputType.phone,
                                        decoration: InputDecoration(labelText: phoneRequired ? 'Telefon *' : 'Telefon', hintText: '05XX XXX XX XX', prefixIcon: const Icon(Icons.phone_outlined)),
                                        validator: (value) {
                                          final numbersOnly = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                                          if (numbersOnly.isEmpty && !phoneRequired) return null;
                                          return numbersOnly.length < 10 ? 'Geçerli bir telefon numarası girin' : null;
                                        },
                                      ),
                                    ] else
                                      Row(children: [
                                        Expanded(child: TextFormField(
                                          controller: fullNameController,
                                          textCapitalization: TextCapitalization.words,
                                          decoration: const InputDecoration(labelText: 'Ad Soyad *', prefixIcon: Icon(Icons.person_outline)),
                                          validator: (value) => value == null || value.trim().length < 3 ? 'Geçerli bir ad soyad girin' : null,
                                        )),
                                        const SizedBox(width: 12),
                                        Expanded(child: TextFormField(
                                          controller: phoneController,
                                          keyboardType: TextInputType.phone,
                                          decoration: InputDecoration(labelText: phoneRequired ? 'Telefon *' : 'Telefon', hintText: '05XX XXX XX XX', prefixIcon: const Icon(Icons.phone_outlined)),
                                          validator: (value) {
                                            final numbersOnly = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                                            if (numbersOnly.isEmpty && !phoneRequired) return null;
                                            return numbersOnly.length < 10 ? 'Geçerli bir telefon numarası girin' : null;
                                          },
                                        )),
                                      ]),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: registrationDateController,
                                      enabled: !isEditing,
                                      keyboardType: TextInputType.datetime,
                                      decoration: const InputDecoration(labelText: 'Müşteri Kayıt Tarihi', hintText: '27.7.2026', prefixIcon: Icon(Icons.event_available_outlined)),
                                      validator: (value) => isEditing || _parseManualDate(value ?? '') != null ? null : 'Tarihi gün.ay.yıl şeklinde girin.',
                                    ),
                                  ]),
                                );

                                final statusSection = _FormSection(
                                  icon: Icons.toggle_on_outlined,
                                  title: 'Kayıt Durumu',
                                  subtitle: 'Müşteri görünürlüğü ve kayıt durumu',
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(color: const Color(0xFFF4F8FB), borderRadius: BorderRadius.circular(12)),
                                      child: Row(children: [
                                        CircleAvatar(backgroundColor: isActive ? const Color(0xFFDFF7EA) : const Color(0xFFFFE8E8), child: Icon(isActive ? Icons.check_rounded : Icons.pause_rounded, color: isActive ? const Color(0xFF18A866) : const Color(0xFFE04B4B))),
                                        const SizedBox(width: 12),
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(isActive ? 'Aktif Müşteri' : 'Pasif Müşteri', style: const TextStyle(fontWeight: FontWeight.w800)),
                                          Text(isActive ? 'Servis ve bakım listelerinde görünür.' : 'Pasif olarak saklanır.', style: const TextStyle(color: Color(0xFF718096), fontSize: 12)),
                                        ])),
                                        if (widget.role != AppRole.technician) Switch(value: isActive, onChanged: (v) => setState(() => isActive = v)),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('İpucu', style: TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 5),
                                    const Text('Telefon ve adres bilgilerini eksiksiz girmek, WhatsApp ve harita işlemlerini kolaylaştırır.', style: TextStyle(color: Color(0xFF718096), height: 1.4)),
                                  ]),
                                );

                                if (mobile) {
                                  return Column(children: [
                                    customerSection,
                                    const SizedBox(height: 12),
                                    statusSection,
                                  ]);
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 6, child: customerSection),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 4, child: statusSection),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            _FormSection(
                              icon: Icons.location_on_outlined,
                              title: 'Adres Bilgileri',
                              subtitle: 'Servis ekibinin müşteriye hızlı ulaşabilmesi için',
                              child: Column(children: [
                                LayoutBuilder(builder: (context, constraints) {
                                  final mobile = constraints.maxWidth < 680;
                                  final city = TextFormField(controller: cityController, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: cityRequired ? 'İl *' : 'İl', prefixIcon: const Icon(Icons.location_city_outlined)), validator: (v) => cityRequired && (v == null || v.trim().isEmpty) ? 'İl zorunludur' : null);
                                  final district = TextFormField(controller: districtController, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: districtRequired ? 'İlçe *' : 'İlçe', prefixIcon: const Icon(Icons.location_on_outlined)), validator: (v) => districtRequired && (v == null || v.trim().isEmpty) ? 'İlçe zorunludur' : null);
                                  final neighborhood = TextFormField(controller: neighborhoodController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Mahalle', prefixIcon: Icon(Icons.home_work_outlined)));
                                  if (mobile) {
                                    return Column(children: [city, const SizedBox(height: 12), district, const SizedBox(height: 12), neighborhood]);
                                  }
                                  return Row(children: [
                                    Expanded(child: city),
                                    const SizedBox(width: 12),
                                    Expanded(child: district),
                                    const SizedBox(width: 12),
                                    Expanded(child: neighborhood),
                                  ]);
                                }),
                                const SizedBox(height: 12),
                                TextFormField(controller: addressController, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: addressRequired ? 'Açık Adres *' : 'Açık Adres', hintText: 'Sokak, bina, kat ve daire bilgisi', prefixIcon: const Icon(Icons.home_outlined), alignLabelWithHint: true), validator: (v) => addressRequired && (v == null || v.trim().isEmpty) ? 'Açık adres zorunludur' : null),
                              ]),
                            ),
                            const SizedBox(height: 16),
                            _FormSection(
                              icon: Icons.notes_outlined,
                              title: 'Notlar',
                              subtitle: 'Müşteri veya servis ekibi için ek bilgiler',
                              child: TextFormField(controller: notesController, textCapitalization: TextCapitalization.sentences, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Not', hintText: 'Kapı tarifi, müsait saat veya özel bilgi...', prefixIcon: Icon(Icons.notes_outlined), alignLabelWithHint: true)),
                            ),
                            const SizedBox(height: 18),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              OutlinedButton(onPressed: () => context.go(_dashboardFallbackRoute()), child: const Text('Vazgeç')),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: state.isSaving ? null : () => _saveCustomer(context),
                                icon: state.isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                                label: Text(state.isSaving ? 'Kaydediliyor...' : isEditing ? 'Değişiklikleri Kaydet' : 'Müşteriyi Kaydet'),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }


  DateTime? _parseManualDate(String value) {
    final parts = value.trim().split(RegExp(r'[./-]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    try {
      final date = DateTime(year, month, day);
      if (date.day != day || date.month != month || date.year != year) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  String _formatManualDate(DateTime date) => '${date.day}.${date.month}.${date.year}';

  Future<void> _saveCustomer(BuildContext context) async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final parsedDate = _parseManualDate(registrationDateController.text);
    if (widget.customerId == null && parsedDate == null) return;
    if (parsedDate != null) registrationDate = parsedDate;

    final customerController = ref.read(customerControllerProvider);
    final existingCustomer = customerController.state.currentCustomer;

    /*
     * Ekrandan kaldırılan eski alanlar, mevcut müşteri
     * düzenlenirken yanlışlıkla silinmesin diye korunuyor.
     *
     * Yeni müşteride müşteri türü varsayılan olarak
     * bireysel kaydediliyor.
     */
    final customer = CustomerModel(
      id: widget.customerId,
      customerType: existingCustomer?.customerType ?? CustomerType.individual,
      fullName: fullNameController.text.trim(),
      companyName: existingCustomer?.companyName,
      phone: phoneController.text.trim(),
      alternativePhone: existingCustomer?.alternativePhone,
      email: existingCustomer?.email,
      city: cityController.text.trim(),
      district: districtController.text.trim(),
      neighborhood: neighborhoodController.text.trim(),
      address: addressController.text.trim(),
      latitude: existingCustomer?.latitude,
      longitude: existingCustomer?.longitude,
      mapsUrl: existingCustomer?.mapsUrl,
      notes: notesController.text.trim(),
      isActive: isActive,
      registrationDate: registrationDate,
    );

    final appSettings = ref.read(companyAppSettingsProvider).asData?.value;
    await customerController.saveCustomer(
      customer,
      phoneRequired: appSettings?.customerRule('phone_required', fallback: true) ?? true,
      addressRequired: appSettings?.customerRule('address_required', fallback: true) ?? true,
    );

    if (!mounted || !context.mounted) {
      return;
    }

    final latestState = customerController.state;
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (latestState.errorMessage != null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(latestState.errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (latestState.successMessage != null) {
      messenger?.showSnackBar(
        SnackBar(content: Text(latestState.successMessage!)),
      );

      /*
       * Şimdilik mevcut sistemdeki gibi önceki ekrana dönüyor.
       * Servis talebi ekranını oluşturduğumuzda yeni müşteri
       * kaydından sonra burayı doğrudan servis ekranına bağlayacağız.
       */
      if (context.canPop()) {
        context.pop();
      } else if (widget.customerId != null) {
        context.go('${_customerPrefix()}/customers/${widget.customerId}');
      } else {
        context.go('${_customerPrefix()}/customers');
      }
    }
  }

  void _populateFields(CustomerModel customer) {
    fullNameController.text = customer.fullName;
    phoneController.text = customer.phone;
    cityController.text = customer.city ?? '';
    districtController.text = customer.district ?? '';
    neighborhoodController.text = customer.neighborhood ?? '';
    addressController.text = customer.address;
    notesController.text = customer.notes ?? '';

    setState(() {
      registrationDate = customer.registrationDate ?? customer.createdAt ?? DateTime.now();
    registrationDateController.text = _formatManualDate(registrationDate);
      isActive = customer.isActive;
      _isFormInitialized = true;
    });
  }

  void _resetFormState() {
    _isFormInitialized = false;
    isActive = true;
    registrationDate = DateTime.now();

    fullNameController.clear();
    phoneController.clear();
    cityController.clear();
    districtController.clear();
    neighborhoodController.clear();
    addressController.clear();
    notesController.clear();
  }

  Future<void> _pickRegistrationDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: registrationDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null) {
      setState(() => registrationDate = selected);
    }
  }

  String _customerPrefix() {
    return widget.role == AppRole.secretary
        ? '/secretary'
        : widget.role == AppRole.technician
            ? '/technician'
            : '/manager';
  }

  String _dashboardFallbackRoute() {
    switch (widget.role) {
      case AppRole.admin:
      case AppRole.manager:
        return '/admin-dashboard';
      case AppRole.secretary:
        return '/secretary-dashboard';
      case AppRole.technician:
        return '/technician-dashboard';
    }
  }
}

class _FormHero extends StatelessWidget {
  const _FormHero({required this.isEditing});
  final bool isEditing;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0B3144), Color(0xFF0E8797)]), borderRadius: BorderRadius.circular(18)),
    child: Row(children: [
      const CircleAvatar(radius: 28, backgroundColor: Colors.white24, child: Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 28)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isEditing ? 'Müşteri bilgilerini güncelleyin' : 'Yeni müşteri oluşturun', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(isEditing ? 'Kayıtlı iletişim ve adres bilgilerini düzenleyebilirsiniz.' : 'Zorunlu alanları doldurun; servis talebini daha sonra müşteri kartından açabilirsiniz.', style: const TextStyle(color: Colors.white70))])),
    ]),
  );
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.icon, required this.title, required this.subtitle, required this.child});
  final IconData icon; final String title; final String subtitle; final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE0E8F0)), boxShadow: const [BoxShadow(color: Color(0x0A102030), blurRadius: 18, offset: Offset(0, 5))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFE5F8FA), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF0AAEC0))), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35))), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF7A8A9D)))]))]),
      const SizedBox(height: 16), child,
    ]),
  );
}
