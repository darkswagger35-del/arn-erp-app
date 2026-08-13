import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../../core/services/supabase_client_provider.dart';
import '../data/maintenance_repository.dart';

class HistoricalCustomerScreen extends ConsumerStatefulWidget {
  const HistoricalCustomerScreen({required this.role, super.key});
  final AppRole role;
  @override
  ConsumerState<HistoricalCustomerScreen> createState() => _HistoricalCustomerScreenState();
}

class _HistoricalCustomerScreenState extends ConsumerState<HistoricalCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _address = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _amount = TextEditingController(text: '0');
  DateTime _recordDate = DateTime.now();
  DateTime? _dueDate;
  List<MaintenanceProduct> _products = const [];
  List<MaintenanceUser> _staff = const [];
  String? _productId;
  String? _secretaryId;
  String? _technicianId;
  String _paymentStatus = 'paid';
  bool _loading = true;
  bool _saving = false;

  MaintenanceRepository get _repo => MaintenanceRepository(ref.read(supabaseClientProvider));

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  @override
  void dispose() { for (final c in [_name,_phone,_city,_district,_address,_quantity,_amount]) { c.dispose(); } super.dispose(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_repo.getProducts(), _repo.getHistoricalStaff()]);
      final products = results[0] as List<MaintenanceProduct>;
      final staff = results[1] as List<MaintenanceUser>;
      if (!mounted) return;
      setState(() {
        _products = products;
        _staff = staff;
        _productId = products.isEmpty ? null : products.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ürünler yüklenemedi: $e')));
    }
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
    context: context, initialDate: initial, firstDate: DateTime(2000), lastDate: DateTime(2100),
    locale: const Locale('tr', 'TR'),
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _productId == null) return;
    if (_paymentStatus == 'debt' && _dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Borçlu müşteri için ödeme tarihi seçin.')));
      return;
    }
    final product = _products.firstWhere((p) => p.id == _productId);
    setState(() => _saving = true);
    try {
      final customerId = await _repo.createHistoricalCustomerV17(
        fullName: _name.text, phone: _phone.text, city: _city.text, district: _district.text,
        address: _address.text, recordDate: _recordDate, productId: product.id,
        quantity: double.parse(_quantity.text.replaceAll(',', '.')),
        amount: double.parse(_amount.text.replaceAll(',', '.')),
        paymentStatus: _paymentStatus, paymentDueDate: _dueDate,
        maintenanceMonths: product.maintenanceMonths,
        secretaryId: _secretaryId,
        technicianId: _technicianId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eski müşteri, ürün ve bakım kaydı oluşturuldu.')));
      context.go('${widget.role == AppRole.secretary ? '/secretary' : '/manager'}/customers/$customerId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayıt oluşturulamadı: $e')));
    }
  }

  String? _required(String? v) => v == null || v.trim().isEmpty ? 'Zorunlu alan' : null;
  String? _positive(String? v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? '0’dan büyük girin' : null;

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd.MM.yyyy', 'tr_TR');
    return ManagementShell(
      role: widget.role,
      title: 'Geçmiş Müşteri Kaydı',
      subtitle: 'Unutulan eski müşteri ve işlemleri gerçek işlem tarihiyle sisteme ekleyin.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF33266E), Color(0xFF6F4ED6)]), borderRadius: BorderRadius.circular(18)),
                        child: const Row(children: [CircleAvatar(radius: 27, backgroundColor: Colors.white24, child: Icon(Icons.history_rounded, color: Colors.white, size: 28)), SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Eski işi bugünkü tarihe değil, gerçek tarihine kaydedin', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('Bu kayıt güncel servis kuyruğuna düşmez; müşteri geçmişi ve raporlar seçtiğiniz tarihe göre oluşur.', style: TextStyle(color: Colors.white70))]))]),
                      ),
                      const SizedBox(height: 18),
                      _HistorySection(icon: Icons.person_outline, title: 'Müşteri Bilgileri', child: Column(children: [
                        Row(children: [Expanded(child: TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Ad Soyad *', prefixIcon: Icon(Icons.person_outline)), validator: _required)), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon *', prefixIcon: Icon(Icons.phone_outlined)), validator: _required))]),
                        const SizedBox(height: 12),
                        Row(children: [Expanded(child: TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'İl *'), validator: _required)), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _district, decoration: const InputDecoration(labelText: 'İlçe *'), validator: _required))]),
                        const SizedBox(height: 12),
                        TextFormField(controller: _address, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Açık Adres *', prefixIcon: Icon(Icons.home_outlined), alignLabelWithHint: true), validator: _required),
                      ])),
                      const SizedBox(height: 16),
                      _HistorySection(icon: Icons.build_circle_outlined, title: 'Geçmiş İşlem Bilgileri', child: Column(children: [
                        InkWell(onTap: () async { final d = await _pick(_recordDate); if (d != null) setState(() => _recordDate = d); }, borderRadius: BorderRadius.circular(12), child: InputDecorator(decoration: const InputDecoration(labelText: 'Kayıt / İşlem Tarihi *', prefixIcon: Icon(Icons.calendar_month_outlined)), child: Text(f.format(_recordDate), style: const TextStyle(fontWeight: FontWeight.w800)))),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(value: _productId, decoration: const InputDecoration(labelText: 'Ürün / Yapılan İşlem *', prefixIcon: Icon(Icons.inventory_2_outlined)), items: _products.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} • ${p.maintenanceMonths == 0 ? 'bakım takibi yok' : '${p.maintenanceMonths} ay'}'))).toList(), onChanged: (v) => setState(() => _productId = v), validator: (v) => v == null ? 'Ürün seçin' : null),
                        const SizedBox(height: 12),
                        Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _secretaryId, decoration: const InputDecoration(labelText: 'Kaydı Açan Sekreter', prefixIcon: Icon(Icons.support_agent_outlined)), items: _staff.where((u) => u.role == 'secretary').map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName))).toList(), onChanged: (v) => setState(() => _secretaryId = v))), const SizedBox(width: 12), Expanded(child: DropdownButtonFormField<String>(value: _technicianId, decoration: const InputDecoration(labelText: 'Geçmişte Giden Teknisyen', prefixIcon: Icon(Icons.engineering_outlined)), items: _staff.where((u) => u.role == 'technician').map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName))).toList(), onChanged: (v) => setState(() => _technicianId = v)))]),
                      ])),
                      const SizedBox(height: 16),
                      _HistorySection(icon: Icons.payments_outlined, title: 'Adet ve Ödeme', child: Column(children: [
                        Row(children: [Expanded(child: TextFormField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Adet *', prefixIcon: Icon(Icons.numbers_rounded)), validator: _positive)), const SizedBox(width: 12), Expanded(child: TextFormField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Toplam Tutar (₺)', prefixIcon: Icon(Icons.currency_lira_rounded))))]),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(value: _paymentStatus, decoration: const InputDecoration(labelText: 'Ödeme Durumu', prefixIcon: Icon(Icons.account_balance_wallet_outlined)), items: const [DropdownMenuItem(value: 'paid', child: Text('Ödendi')), DropdownMenuItem(value: 'debt', child: Text('Borçlu'))], onChanged: (v) => setState(() => _paymentStatus = v ?? 'paid')),
                        if (_paymentStatus == 'debt') ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async { final d = await _pick(_dueDate ?? DateTime.now()); if (d != null) setState(() => _dueDate = d); }, icon: const Icon(Icons.event), label: Text(_dueDate == null ? 'Ödeme tarihi seç' : 'Ödeme tarihi: ${f.format(_dueDate!)}'))],
                      ])),
                      const SizedBox(height: 18),
                      Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Kaydediliyor...' : 'Geçmiş Kaydı Oluştur'))),
                    ]),
                  ),
                ),
              ),
            ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.icon, required this.title, required this.child});
  final IconData icon; final String title; final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE0E8F0)), boxShadow: const [BoxShadow(color: Color(0x0A102030), blurRadius: 18, offset: Offset(0, 5))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFF0EBFF), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: const Color(0xFF6F4ED6))), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35)))]), const SizedBox(height: 16), child]),
  );
}
