import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/finance_providers.dart';

class FinancePaymentsScreen extends ConsumerStatefulWidget {
  const FinancePaymentsScreen({super.key});

  @override
  ConsumerState<FinancePaymentsScreen> createState() =>
      _FinancePaymentsScreenState();
}

class _FinancePaymentsScreenState extends ConsumerState<FinancePaymentsScreen> {
  late DateTime _start;
  late DateTime _end;
  String _method = 'all';
  String _query = '';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 1);
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => ref
      .read(financeRepositoryProvider)
      .payments(start: _start, end: _end);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _start = value);
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _end.subtract(const Duration(days: 1)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _end = value.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).role ?? AppRole.manager;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return ManagementShell(
      role: role,
      title: 'Tahsilatlar',
      subtitle: 'Tahsilatı, ilgili servisi, ürünü ve personeli tek ekrandan takip edin.',
      dark: true,
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Tahsilatlar yüklenemedi: ${snapshot.error}'));
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final visible = rows.where((row) {
            final query = _query.trim().toLowerCase();
            final customer = _customerName(row).toLowerCase();
            final description = row['description']?.toString().toLowerCase() ?? '';
            final service = _service(row);
            final serviceType = _serviceTypeLabel(service['service_type']?.toString()).toLowerCase();
            final matchesQuery = query.isEmpty ||
                customer.contains(query) ||
                description.contains(query) ||
                serviceType.contains(query);
            final matchesMethod = _method == 'all' ||
                row['payment_method']?.toString() == _method;
            return matchesQuery && matchesMethod;
          }).toList(growable: false);

          final total = rows.fold<double>(
            0,
            (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
          );
          final today = DateUtils.dateOnly(DateTime.now());
          final todayTotal = rows.fold<double>(0, (sum, row) {
            final value = DateTime.tryParse(row['payment_date']?.toString() ?? '');
            if (value != null && DateUtils.isSameDay(value.toLocal(), today)) {
              return sum + ((row['amount'] as num?)?.toDouble() ?? 0);
            }
            return sum;
          });
          final cashTotal = rows
              .where((row) => row['payment_method']?.toString() == 'cash')
              .fold<double>(0, (sum, row) =>
                  sum + ((row['amount'] as num?)?.toDouble() ?? 0));
          final cardTotal = rows
              .where((row) => row['payment_method']?.toString() == 'card')
              .fold<double>(0, (sum, row) =>
                  sum + ((row['amount'] as num?)?.toDouble() ?? 0));

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.maxWidth >= 1200
                      ? 4
                      : constraints.maxWidth >= 700
                          ? 2
                          : 1;
                  return GridView.count(
                    crossAxisCount: count,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: count == 1 ? 3.4 : 2.5,
                    children: [
                      _Metric('Bugünkü Tahsilat', money.format(todayTotal),
                          'Bugün', Icons.today_outlined, const Color(0xFF2F80ED)),
                      _Metric('Dönem Tahsilatı', money.format(total),
                          '${rows.length} işlem', Icons.account_balance_wallet_outlined, const Color(0xFF18A66A)),
                      _Metric('Nakit', money.format(cashTotal), 'Seçili dönem',
                          Icons.payments_outlined, const Color(0xFFF5A623)),
                      _Metric('Kart', money.format(cardTotal), 'Seçili dönem',
                          Icons.credit_card_outlined, const Color(0xFF8B5CF6)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width < 600 ? (MediaQuery.sizeOf(context).width - 64).clamp(220.0, 350.0) : 350,
                        child: TextField(
                          onChanged: (value) => setState(() => _query = value),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Müşteri, açıklama veya servis türü ara...',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickStart,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(DateFormat('dd.MM.yyyy').format(_start)),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickEnd,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(DateFormat('dd.MM.yyyy')
                            .format(_end.subtract(const Duration(days: 1)))),
                      ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          value: _method,
                          decoration: const InputDecoration(labelText: 'Ödeme Türü'),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Tümü')),
                            DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                            DropdownMenuItem(value: 'card', child: Text('Kart')),
                            DropdownMenuItem(value: 'transfer', child: Text('Havale / EFT')),
                            DropdownMenuItem(value: 'open_account', child: Text('Açık Hesap')),
                          ],
                          onChanged: (value) => setState(() => _method = value ?? 'all'),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: const Text('Filtrele'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final now = DateTime.now();
                          setState(() {
                            _start = DateTime(now.year, now.month, 1);
                            _end = DateTime(now.year, now.month + 1, 1);
                            _method = 'all';
                            _query = '';
                          });
                          _reload();
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Temizle'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                clipBehavior: Clip.antiAlias,
                child: visible.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: Text('Seçilen filtrelerde tahsilat bulunamadı.')),
                      )
                    : Column(
                        children: [
                          const _PaymentHeader(),
                          ...visible.map((row) => _PaymentRow(
                                row: row,
                                money: money,
                                onTap: () => _showDetail(row, money),
                              )),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Toplam ${visible.length} kayıt'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDetail(
    Map<String, dynamic> row,
    NumberFormat money,
  ) async {
    final service = _service(row);
    final items = service['items'] is List
        ? List<Map<String, dynamic>>.from(service['items'] as List)
        : const <Map<String, dynamic>>[];
    final customer = row['customers'] is Map
        ? Map<String, dynamic>.from(row['customers'] as Map)
        : const <String, dynamic>{};
    final paymentDate = DateTime.tryParse(row['payment_date']?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF123C4A),
                      child: Icon(Icons.receipt_long_outlined, color: Color(0xFF22D3DC)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_customerName(row),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          Text(money.format((row['amount'] as num?)?.toDouble() ?? 0),
                              style: const TextStyle(color: Color(0xFF35C978), fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 26),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 28,
                          runSpacing: 12,
                          children: [
                            _Detail('Tarih', paymentDate == null ? '-' : DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(paymentDate.toLocal())),
                            _Detail('Ödeme', _methodName(row['payment_method']?.toString())),
                            _Detail('Telefon', customer['phone']?.toString() ?? '-'),
                            _Detail('Adres', customer['address']?.toString() ?? '-'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _Section(
                          title: 'Servis Bilgileri',
                          children: [
                            _Line('Servis Türü', _serviceTypeLabel(service['service_type']?.toString())),
                            _Line('Teknisyen', service['technician_name']?.toString() ?? '-'),
                            _Line(
                              'Talebi Açan',
                              _openedByLabel(service),
                            ),
                            _Line('Açıklama', service['description']?.toString() ?? row['description']?.toString() ?? '-'),
                            _Line('Tamamlama Notu', service['completion_note']?.toString() ?? '-'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Section(
                          title: 'Ürünler / Yapılan İşlemler',
                          children: items.isEmpty
                              ? const [Text('Bu tahsilata bağlı ürün detayı bulunamadı.')]
                              : items.map((item) {
                                  final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
                                  final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
                                  return _Line(
                                    item['product_name']?.toString() ?? 'Ürün',
                                    '${_qty(quantity)} × ${money.format(unitPrice)} = ${money.format(quantity * unitPrice)}',
                                  );
                                }).toList(growable: false),
                        ),
                      ],
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

  static Map<String, dynamic> _service(Map<String, dynamic> row) =>
      row['_service'] is Map
          ? Map<String, dynamic>.from(row['_service'] as Map)
          : <String, dynamic>{};

  static String _customerName(Map<String, dynamic> row) {
    final customer = row['customers'] is Map
        ? Map<String, dynamic>.from(row['customers'] as Map)
        : <String, dynamic>{};
    final companyName = customer['company_name']?.toString().trim() ?? '';
    final fullName = customer['full_name']?.toString().trim() ?? '';
    return companyName.isNotEmpty
        ? companyName
        : fullName.isNotEmpty
            ? fullName
            : 'Müşteri belirtilmemiş';
  }

  static String _methodName(String? value) => switch (value) {
        'cash' => 'Nakit',
        'card' => 'Kart',
        'transfer' => 'Havale / EFT',
        'open_account' => 'Açık Hesap',
        _ => value ?? '-',
      };

  static String _serviceTypeLabel(String? value) => switch (value) {
        'new_installation' => 'Cihaz Satışı / Montaj',
        'filter_change' => 'Filtre Değişimi',
        'maintenance' => 'Bakım',
        'fault' => 'Arıza',
        'membrane' => 'Membran Değişimi',
        'external_filter' => 'Dış Filtre',
        'relocation' => 'Taşıma',
        'removal' => 'Söküm',
        _ => value?.isNotEmpty == true ? value! : '-',
      };

  static String _openedByLabel(Map<String, dynamic> service) {
    final name = service['opened_by_name']?.toString().trim() ?? '';
    final role = service['opened_by_role']?.toString() ?? '';
    if (name.isEmpty) return '-';
    final roleLabel = switch (role) {
      'secretary' => 'Sekreter',
      'technician' => 'Teknisyen',
      'admin' => 'Admin',
      'manager' => 'Yönetici',
      _ => role,
    };
    return roleLabel.isEmpty ? name : '$name • $roleLabel';
  }

  static String _qty(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.detail, this.icon, this.color);
  final String label, value, detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(.14),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Color(0xFF91A4B7))),
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                    Text(detail, style: TextStyle(color: color, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PaymentHeader extends StatelessWidget {
  const _PaymentHeader();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text('Tarih / Saat')),
            Expanded(flex: 3, child: Text('Müşteri')),
            Expanded(flex: 2, child: Text('Ödeme Türü')),
            Expanded(flex: 2, child: Text('Tutar')),
            Expanded(flex: 3, child: Text('Servis')),
            SizedBox(width: 76, child: Text('Detay')),
          ],
        ),
      );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.row, required this.money, required this.onTap});
  final Map<String, dynamic> row;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paymentDate = DateTime.tryParse(row['payment_date']?.toString() ?? '');
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final service = _FinancePaymentsScreenState._service(row);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF223241))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(paymentDate == null
                  ? '-'
                  : DateFormat('dd.MM.yyyy\nHH:mm', 'tr_TR').format(paymentDate.toLocal())),
            ),
            Expanded(
              flex: 3,
              child: Text(_FinancePaymentsScreenState._customerName(row),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              flex: 2,
              child: Text(_FinancePaymentsScreenState._methodName(row['payment_method']?.toString())),
            ),
            Expanded(
              flex: 2,
              child: Text(money.format(amount),
                  style: const TextStyle(color: Color(0xFF35C978), fontWeight: FontWeight.w900)),
            ),
            Expanded(
              flex: 3,
              child: Text(_FinancePaymentsScreenState._serviceTypeLabel(service['service_type']?.toString())),
            ),
            SizedBox(
              width: 76,
              child: IconButton(
                tooltip: 'Tahsilat detayını aç',
                onPressed: onTap,
                icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF22D3DC)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 170,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF71879A), fontSize: 11)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE5EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF102033))),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(label, style: const TextStyle(color: Color(0xFF52657A), fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text(value.isEmpty ? '-' : value, style: const TextStyle(color: Color(0xFF102033)))),
          ],
        ),
      );
}
