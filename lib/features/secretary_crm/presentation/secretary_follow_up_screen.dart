import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../customers/data/models/customer_model.dart';
import '../../customers/presentation/providers/customer_providers.dart';
import '../data/secretary_crm_provider.dart';
import '../data/secretary_crm_repository.dart';

class SecretaryFollowUpScreen extends ConsumerStatefulWidget {
  const SecretaryFollowUpScreen({super.key, this.mode = 'all'});
  final String mode;

  @override
  ConsumerState<SecretaryFollowUpScreen> createState() => _SecretaryFollowUpScreenState();
}

class _SecretaryFollowUpScreenState extends ConsumerState<SecretaryFollowUpScreen> {
  late Future<List<SecretaryLead>> _future;
  final _searchController = TextEditingController();
  String? _interestFilter;
  String? _outcomeFilter;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SecretaryLead>> _load() =>
      ref.read(secretaryCrmRepositoryProvider).listLeads(mode: widget.mode);

  void _refresh() => setState(() => _future = _load());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
        'closed' => 'Kapandı',
        'tracking' => 'Takiptekiler',
        'unanswered' => 'Cevapsız Çağrılar',
        'today' => 'Bugün Aranacak',
        'overdue' => 'Geciken Takipler',
        'now' => 'Şimdi Aranacak',
        'future' => 'Yarın / Sonraki Gün',
        _ => 'Takip Listesi',
      };

  @override
  Widget build(BuildContext context) {
    return ManagementShell(
      role: AppRole.secretary,
      title: _title,
      subtitle: 'Reklam başvurularını, geri aramaları ve sonuçlarını tek ekrandan yönetin.',
      actions: [
        FilledButton.icon(
          onPressed: _newLead,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Yeni Başvuru'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
      ],
      child: FutureBuilder<List<SecretaryLead>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Takip listesi yüklenemedi.\n${snapshot.error}', textAlign: TextAlign.center));
          }
          final rows = _applyLocalFilters(_defensiveFilter(snapshot.data ?? const <SecretaryLead>[]));
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _bucketRow(context),
              const SizedBox(height: 12),
              _filterPanel(),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE1E8F0)),
                ),
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(70),
                        child: Center(child: Text('Bu grupta kayıt bulunmuyor.')),
                      )
                    : Column(
                        children: rows.map((lead) => _leadTile(lead)).toList(growable: false),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<SecretaryLead> _applyLocalFilters(List<SecretaryLead> input) {
    final q = _searchController.text.trim().toLowerCase();
    return input.where((lead) {
      final haystack = [
        lead.fullName,
        lead.phone,
        lead.source ?? '',
        lead.note ?? '',
        _outcomeLabel(lead.outcomeCode),
        _interestLabel(lead.interestType),
        lead.referenceName ?? '',
        lead.quotedPrice?.toString() ?? '',
      ].join(' ').toLowerCase();
      final searchOk = q.isEmpty || haystack.contains(q);
      final interestOk = _interestFilter == null || lead.interestType == _interestFilter;
      final outcomeOk = _outcomeFilter == null || lead.outcomeCode == _outcomeFilter;
      return searchOk && interestOk && outcomeOk;
    }).toList(growable: false);
  }

  Widget _filterPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'İsim, telefon, not, referans veya fiyat ara',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: _interestFilter,
            decoration: const InputDecoration(labelText: 'Görüşme'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
              DropdownMenuItem(value: 'device_demo', child: Text('Cihaz demosu')),
              DropdownMenuItem(value: 'filter', child: Text('Filtre')),
              DropdownMenuItem(value: 'fault', child: Text('Arıza')),
              DropdownMenuItem(value: 'maintenance', child: Text('Bakım')),
              DropdownMenuItem(value: 'reference', child: Text('Referans')),
              DropdownMenuItem(value: 'other', child: Text('Diğer')),
            ],
            onChanged: (v) => setState(() => _interestFilter = v),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: _outcomeFilter,
            decoration: const InputDecoration(labelText: 'Sonuç'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
              DropdownMenuItem(value: 'unanswered', child: Text('Cevapsız')),
              DropdownMenuItem(value: 'busy', child: Text('Meşgul')),
              DropdownMenuItem(value: 'call_later', child: Text('Daha sonra ara')),
              DropdownMenuItem(value: 'thinking', child: Text('Düşünüyor')),
              DropdownMenuItem(value: 'price_given', child: Text('Fiyat verildi')),
              DropdownMenuItem(value: 'not_interested', child: Text('İstemiyor')),
            ],
            onChanged: (v) => setState(() => _outcomeFilter = v),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Filtreleri temizle',
          onPressed: () {
            _searchController.clear();
            setState(() { _interestFilter = null; _outcomeFilter = null; });
          },
          icon: const Icon(Icons.filter_alt_off_rounded),
        ),
      ]),
    );
  }

  List<SecretaryLead> _defensiveFilter(List<SecretaryLead> input) {
    const closedCodes = {'not_interested', 'other_service', 'wrong_number', 'out_of_area'};
    bool isClosed(SecretaryLead lead) => lead.status == 'closed' || closedCodes.contains(lead.outcomeCode);
    bool isWon(SecretaryLead lead) => lead.status == 'won' || lead.outcomeCode == 'job_won';

    return input.where((lead) {
      switch (widget.mode) {
        case 'closed':
          return isClosed(lead) && !isWon(lead);
        case 'tracking':
        case 'unanswered':
        case 'today':
        case 'overdue':
        case 'now':
        case 'future':
          return !isClosed(lead) && !isWon(lead);
        default:
          // Ana Takip Listesi sadece sekreterin hâlâ aksiyon alacağı kayıtları gösterir.
          return !isClosed(lead) && !isWon(lead);
      }
    }).toList(growable: false);
  }

  Widget _bucketRow(BuildContext context) {
    final items = const [
      ('Takipte', 'tracking', Icons.schedule_rounded, Color(0xFFF59E0B)),
      ('Bugün Ara', 'today', Icons.phone_in_talk_rounded, Color(0xFFEA8A1A)),
      ('Cevapsız', 'unanswered', Icons.phone_missed_rounded, Color(0xFF7C5CE7)),
      ('Geciken', 'overdue', Icons.warning_amber_rounded, Color(0xFFE75454)),
      ('Kapandı', 'closed', Icons.cancel_outlined, Color(0xFF66778A)),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        final selected = widget.mode == item.$2;
        return ChoiceChip(
          selected: selected,
          avatar: Icon(item.$3, size: 18, color: item.$4),
          label: Text(item.$1),
          onSelected: (_) => context.go('/secretary/follow-ups/${item.$2}'),
        );
      }).toList(growable: false),
    );
  }

  Widget _leadTile(SecretaryLead lead) {
    final follow = lead.followUpAt?.toLocal();
    final date = follow == null ? 'Takip tarihi yok' : DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(follow);
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          leading: CircleAvatar(
            backgroundColor: _statusColor(lead).withOpacity(.12),
            child: Icon(_statusIcon(lead), color: _statusColor(lead)),
          ),
          title: Text(lead.fullName, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(_leadSubtitle(lead, date)),
          isThreeLine: true,
          trailing: Wrap(
            spacing: 6,
            children: [
              IconButton(tooltip: 'Ara', onPressed: () => _call(lead.phone), icon: const Icon(Icons.phone_outlined)),
              if (lead.status != 'won')
                FilledButton.tonalIcon(
                  onPressed: () => _setOutcome(lead),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(lead.status == 'closed' ? 'Düzenle / Takibe Al' : 'Sonuç'),
                ),
              if (lead.status != 'won')
                FilledButton.icon(
                  onPressed: () => _convertToJob(lead),
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('İş Aldım'),
                ),
              if (lead.customerId?.isNotEmpty == true)
                IconButton(
                  tooltip: 'Müşteri Kartı',
                  onPressed: () => context.go('/secretary/customers/${lead.customerId}'),
                  icon: const Icon(Icons.badge_outlined),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  String _leadSubtitle(SecretaryLead lead, String date) {
    final parts = <String>[lead.phone, _outcomeLabel(lead.outcomeCode)];
    if (lead.interestType?.trim().isNotEmpty == true) parts.add(_interestLabel(lead.interestType));
    if ((lead.quotedPrice ?? 0) > 0) parts.add('Fiyat: ₺${NumberFormat('#,##0.##', 'tr_TR').format(lead.quotedPrice)}');
    if (lead.referenceName?.trim().isNotEmpty == true) parts.add('Referans: ${lead.referenceName}');
    if (lead.source?.trim().isNotEmpty == true) parts.add('Kaynak: ${lead.source}');
    final line2 = <String>[date];
    if (lead.note?.trim().isNotEmpty == true) line2.add(lead.note!.trim());
    return '${parts.join(' • ')}\n${line2.join(' • ')}';
  }

  String _interestLabel(String? value) => switch (value) {
        'device_demo' => 'Cihaz demosu',
        'filter' => 'Filtre',
        'fault' => 'Arıza',
        'maintenance' => 'Bakım',
        'reference' => 'Referans müşteri',
        'other' => 'Diğer',
        _ => 'Belirtilmedi',
      };

  Future<void> _newLead() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final source = TextEditingController(text: 'WhatsApp Reklam');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Başvuru'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad Soyad *')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon *')),
            const SizedBox(height: 12),
            TextField(controller: source, decoration: const InputDecoration(labelText: 'Kaynak', hintText: 'WhatsApp Reklam')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    if (name.text.trim().length < 2 || phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad soyad ve geçerli telefon girin.')));
      return;
    }
    await ref.read(secretaryCrmRepositoryProvider).createLead(
          fullName: name.text,
          phone: phone.text,
          source: source.text,
        );
    _refresh();
  }

  Future<void> _setOutcome(SecretaryLead lead) async {
    var code = lead.outcomeCode ?? 'unanswered';
    final note = TextEditingController(text: lead.note ?? '');
    final price = TextEditingController(text: lead.quotedPrice == null ? '' : lead.quotedPrice!.toStringAsFixed(0));
    final reference = TextEditingController(text: lead.referenceName ?? '');
    String? interestType = lead.interestType;
    DateTime? follow = lead.followUpAt?.toLocal();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${lead.fullName} • Görüşme Sonucu'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: code,
                decoration: const InputDecoration(labelText: 'Sonuç'),
                items: const [
                  DropdownMenuItem(value: 'unanswered', child: Text('Cevapsız')),
                  DropdownMenuItem(value: 'busy', child: Text('Meşgul')),
                  DropdownMenuItem(value: 'call_later', child: Text('Daha sonra ara')),
                  DropdownMenuItem(value: 'thinking', child: Text('Düşünüyor')),
                  DropdownMenuItem(value: 'price_given', child: Text('Fiyat bilgisi verildi')),
                  DropdownMenuItem(value: 'not_interested', child: Text('İstemiyor')),
                  DropdownMenuItem(value: 'other_service', child: Text('Başka yerde yaptırdı')),
                  DropdownMenuItem(value: 'wrong_number', child: Text('Yanlış numara')),
                  DropdownMenuItem(value: 'out_of_area', child: Text('Bölge dışı')),
                ],
                onChanged: (v) => setDialogState(() => code = v ?? code),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: interestType,
                decoration: const InputDecoration(labelText: 'Görüşme / İlgi Türü'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Belirtilmedi')),
                  DropdownMenuItem(value: 'device_demo', child: Text('Cihaz demosu')),
                  DropdownMenuItem(value: 'filter', child: Text('Filtre')),
                  DropdownMenuItem(value: 'fault', child: Text('Arıza')),
                  DropdownMenuItem(value: 'maintenance', child: Text('Bakım')),
                  DropdownMenuItem(value: 'reference', child: Text('Referans müşteri')),
                  DropdownMenuItem(value: 'other', child: Text('Diğer')),
                ],
                onChanged: (v) => setDialogState(() => interestType = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Verilen Fiyat', prefixText: '₺ '))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: reference, decoration: const InputDecoration(labelText: 'Referans Müşteri / Kaynak'))),
              ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final pickedDate = await showDatePicker(context: context, initialDate: follow ?? now, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 365)));
                  if (pickedDate == null || !context.mounted) return;
                  final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(follow ?? now.add(const Duration(hours: 1))));
                  if (pickedTime == null) return;
                  setDialogState(() => follow = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute));
                },
                icon: const Icon(Icons.schedule_rounded),
                label: Text(follow == null ? 'Geri arama zamanı seç' : DateFormat('dd.MM.yyyy HH:mm').format(follow!)),
              ),
              const SizedBox(height: 12),
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Not')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (result != true) return;
    await ref.read(secretaryCrmRepositoryProvider).setOutcome(
          leadId: lead.id,
          outcomeCode: code,
          note: note.text,
          followUpAt: follow,
          interestType: interestType,
          quotedPrice: double.tryParse(price.text.replaceAll('.', '').replaceAll(',', '.')),
          referenceName: reference.text,
        );
    _refresh();
  }

  Future<void> _convertToJob(SecretaryLead lead) async {
    final city = TextEditingController();
    final district = TextEditingController();
    final address = TextEditingController();
    final note = TextEditingController(text: lead.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İşi Aldım • Müşteriyi Aktifleştir'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${lead.fullName} • ${lead.phone}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(controller: city, decoration: const InputDecoration(labelText: 'Şehir *')),
            const SizedBox(height: 10),
            TextField(controller: district, decoration: const InputDecoration(labelText: 'İlçe *')),
            const SizedBox(height: 10),
            TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Açık Adres *')),
            const SizedBox(height: 10),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Müşteri Notu')),
            const SizedBox(height: 8),
            const Text('Kaydedince müşteri aktif olur ve servis talebi ekranı açılır.', style: TextStyle(color: Color(0xFF718096))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aktif Müşteri Yap')),
        ],
      ),
    );
    if (ok != true) return;
    if (city.text.trim().isEmpty || district.text.trim().isEmpty || address.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Şehir, ilçe ve açık adres zorunlu.')));
      return;
    }
    try {
      final crm = ref.read(secretaryCrmRepositoryProvider);
      String? customerId;
      try {
        final existing = await crm.client
            .from('customers')
            .select('id,is_active')
            .eq('phone', lead.phone.trim())
            .filter('deleted_at', 'is', null)
            .limit(1)
            .maybeSingle();
        customerId = existing?['id']?.toString();
        if (customerId != null && customerId.isNotEmpty && existing?['is_active'] != true) {
          await ref.read(customerRepositoryProvider).toggleActive(customerId, true);
        }
      } catch (_) {}

      if (customerId == null || customerId.isEmpty) {
        final customer = await ref.read(customerRepositoryProvider).createCustomer(
              CustomerModel(
                customerType: CustomerType.individual,
                fullName: lead.fullName,
                phone: lead.phone,
                city: city.text.trim(),
                district: district.text.trim(),
                address: address.text.trim(),
                notes: note.text.trim().isEmpty ? null : note.text.trim(),
                isActive: true,
                registrationDate: DateTime.now(),
              ),
            );
        customerId = customer.id;
      }
      if (customerId == null || customerId.isEmpty) throw StateError('Müşteri kaydı oluşmadı.');
      await crm.markWon(leadId: lead.id, customerId: customerId);
      if (mounted) context.go('/secretary/service-requests/new/$customerId');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İş aktif müşteriye çevrilemedi: $e')));
    }
  }

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    await launchUrl(Uri.parse('tel:$digits'));
  }

  Color _statusColor(SecretaryLead lead) {
    if (lead.status == 'closed') return const Color(0xFFE75454);
    if (lead.status == 'won') return const Color(0xFF18A866);
    if (lead.outcomeCode == 'unanswered') return const Color(0xFF7C5CE7);
    return const Color(0xFFF59E0B);
  }

  IconData _statusIcon(SecretaryLead lead) {
    if (lead.status == 'closed') return Icons.cancel_outlined;
    if (lead.status == 'won') return Icons.check_circle_outline_rounded;
    if (lead.outcomeCode == 'unanswered') return Icons.phone_missed_rounded;
    return Icons.schedule_rounded;
  }

  String _outcomeLabel(String? value) => switch (value) {
        'unanswered' => 'Cevapsız',
        'busy' => 'Meşgul',
        'call_later' => 'Daha sonra ara',
        'thinking' => 'Düşünüyor',
        'price_given' => 'Fiyat verildi',
        'not_interested' => 'İstemiyor',
        'other_service' => 'Başka yerde yaptırdı',
        'wrong_number' => 'Yanlış numara',
        'out_of_area' => 'Bölge dışı',
        'job_won' => 'İş alındı',
        _ => 'Yeni başvuru',
      };
}
