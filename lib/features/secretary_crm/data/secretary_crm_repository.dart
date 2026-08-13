import 'package:supabase_flutter/supabase_flutter.dart';

class SecretaryLead {
  const SecretaryLead({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.createdAt,
    this.source,
    this.outcomeCode,
    this.note,
    this.followUpAt,
    this.lastContactedAt,
    this.customerId,
    this.interestType,
    this.quotedPrice,
    this.referenceName,
  });

  final String id;
  final String fullName;
  final String phone;
  final String status;
  final String? source;
  final String? outcomeCode;
  final String? note;
  final DateTime createdAt;
  final DateTime? followUpAt;
  final DateTime? lastContactedAt;
  final String? customerId;
  final String? interestType;
  final double? quotedPrice;
  final String? referenceName;

  factory SecretaryLead.fromMap(Map<String, dynamic> map) => SecretaryLead(
        id: map['id']?.toString() ?? '',
        fullName: map['full_name']?.toString() ?? '',
        phone: map['phone']?.toString() ?? '',
        status: map['status']?.toString() ?? 'new',
        source: map['source']?.toString(),
        outcomeCode: map['outcome_code']?.toString(),
        note: map['note']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
        followUpAt: DateTime.tryParse(map['follow_up_at']?.toString() ?? ''),
        lastContactedAt: DateTime.tryParse(map['last_contacted_at']?.toString() ?? ''),
        customerId: map['customer_id']?.toString(),
        interestType: map['interest_type']?.toString(),
        quotedPrice: (map['quoted_price'] as num?)?.toDouble(),
        referenceName: map['reference_name']?.toString(),
      );
}

class SecretaryFollowUpCounts {
  const SecretaryFollowUpCounts({
    required this.newCount,
    required this.nowCount,
    required this.todayCount,
    required this.unansweredCount,
    required this.futureCount,
    required this.overdueCount,
    required this.trackingCount,
    required this.closedCount,
    required this.wonToday,
    required this.callsToday,
  });

  final int newCount;
  final int nowCount;
  final int todayCount;
  final int unansweredCount;
  final int futureCount;
  final int overdueCount;
  final int trackingCount;
  final int closedCount;
  final int wonToday;
  final int callsToday;
}

class SecretaryCrmRepository {
  SecretaryCrmRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> _profile() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Oturum bulunamadı.');
    final row = await client
        .from('profiles')
        .select('id, company_id, role, full_name')
        .eq('id', user.id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<SecretaryLead> createLead({
    required String fullName,
    required String phone,
    String? source,
  }) async {
    final p = await _profile();
    final row = await client
        .from('secretary_leads')
        .insert({
          'company_id': p['company_id'],
          'secretary_id': p['id'],
          'full_name': fullName.trim(),
          'phone': phone.trim(),
          'source': source?.trim().isEmpty == true ? null : source?.trim(),
          'status': 'new',
        })
        .select()
        .single();
    return SecretaryLead.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<SecretaryLead>> listLeads({
    String mode = 'all',
    int limit = 300,
  }) async {
    dynamic query = client.from('secretary_leads').select();
    switch (mode) {
      case 'tracking':
        query = query.inFilter('status', const ['new', 'tracking']);
        break;
      case 'closed':
        query = query.eq('status', 'closed');
        break;
      case 'won':
        query = query.eq('status', 'won');
        break;
      case 'unanswered':
        query = query.inFilter('status', const ['new', 'tracking']).eq('outcome_code', 'unanswered');
        break;
      case 'now':
        final now = DateTime.now().toUtc();
        final start = now.subtract(const Duration(minutes: 30));
        final end = now.add(const Duration(minutes: 30));
        query = query.inFilter('status', const ['new', 'tracking']).gte('follow_up_at', start.toIso8601String()).lte('follow_up_at', end.toIso8601String());
        break;
      case 'future':
        final now = DateTime.now();
        final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toUtc();
        query = query.inFilter('status', const ['new', 'tracking']).gte('follow_up_at', tomorrow.toIso8601String());
        break;
      case 'today':
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day).toUtc();
        final end = start.add(const Duration(days: 1));
        query = query
            .inFilter('status', const ['new', 'tracking'])
            .gte('follow_up_at', start.toIso8601String())
            .lt('follow_up_at', end.toIso8601String());
        break;
      case 'overdue':
        query = query
            .inFilter('status', const ['new', 'tracking'])
            .lt('follow_up_at', DateTime.now().toUtc().toIso8601String());
        break;
    }
    final rows = await query.order('updated_at', ascending: false).limit(limit);
    var leads = List<Map<String, dynamic>>.from(rows)
        .map(SecretaryLead.fromMap)
        .toList(growable: false);

    // Eski kayıtlarda status/outcome uyumsuzluğu olabiliyor. Ekranların bir
    // görünüp bir kaybolmaması için sonuç kodunu da son savunma katmanı olarak kullan.
    const closedCodes = {'not_interested', 'other_service', 'wrong_number', 'out_of_area'};
    if (mode == 'all' || mode == 'tracking') {
      leads = leads
          .where((lead) =>
              lead.status != 'won' &&
              lead.status != 'closed' &&
              !closedCodes.contains(lead.outcomeCode))
          .toList(growable: false);
    } else if (mode == 'closed') {
      leads = leads
          .where((lead) => lead.status == 'closed' || closedCodes.contains(lead.outcomeCode))
          .toList(growable: false);
    }
    return leads;
  }

  Future<List<SecretaryLead>> latestLeads({int limit = 6}) async {
    final rows = await client
        .from('secretary_leads')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows)
        .map(SecretaryLead.fromMap)
        .toList(growable: false);
  }

  Future<SecretaryFollowUpCounts> counts() async {
    final rows = await _pagedLeadRows();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    var newCount = 0;
    var nowCount = 0;
    var todayCount = 0;
    var unansweredCount = 0;
    var futureCount = 0;
    var overdueCount = 0;
    var trackingCount = 0;
    var closedCount = 0;
    var wonToday = 0;

    for (final row in rows) {
      final status = row['status']?.toString() ?? 'new';
      final outcome = row['outcome_code']?.toString();
      final follow = DateTime.tryParse(row['follow_up_at']?.toString() ?? '')?.toLocal();
      final updated = DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal();
      if (status == 'new') newCount++;
      if (status == 'new' || status == 'tracking') {
        trackingCount++;
        if (outcome == 'unanswered') unansweredCount++;
        if (follow != null) {
          if (follow.isBefore(now)) overdueCount++;
          if (!follow.isBefore(todayStart) && follow.isBefore(todayEnd)) todayCount++;
          if (follow.isAfter(todayEnd)) futureCount++;
          final delta = follow.difference(now).inMinutes.abs();
          if (delta <= 30) nowCount++;
        }
      }
      if (status == 'closed') closedCount++;
      if (status == 'won' && updated != null && !updated.isBefore(todayStart) && updated.isBefore(todayEnd)) {
        wonToday++;
      }
    }

    var callsToday = 0;
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        final startUtc = todayStart.toUtc();
        final endUtc = todayEnd.toUtc();
        final activityRows = List<Map<String, dynamic>>.from(
          await client.from('secretary_lead_activities').select('id').eq('secretary_id', user.id).gte('created_at', startUtc.toIso8601String()).lt('created_at', endUtc.toIso8601String()),
        );
        callsToday = activityRows.length;
      }
    } catch (_) {}

    return SecretaryFollowUpCounts(
      newCount: newCount,
      nowCount: nowCount,
      todayCount: todayCount,
      unansweredCount: unansweredCount,
      futureCount: futureCount,
      overdueCount: overdueCount,
      trackingCount: trackingCount,
      closedCount: closedCount,
      wonToday: wonToday,
      callsToday: callsToday,
    );
  }

  Future<List<Map<String, dynamic>>> _pagedLeadRows() async {
    const pageSize = 1000;
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final rows = List<Map<String, dynamic>>.from(
        await client
            .from('secretary_leads')
            .select('id,status,outcome_code,follow_up_at,updated_at')
            .range(offset, offset + pageSize - 1),
      );
      all.addAll(rows);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return all;
  }

  Future<void> setOutcome({
    required String leadId,
    required String outcomeCode,
    String? note,
    DateTime? followUpAt,
    String? interestType,
    double? quotedPrice,
    String? referenceName,
  }) async {
    final closedCodes = {'not_interested', 'other_service', 'wrong_number', 'out_of_area'};
    final status = closedCodes.contains(outcomeCode) ? 'closed' : 'tracking';
    await client.from('secretary_leads').update({
      'status': status,
      'outcome_code': outcomeCode,
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'follow_up_at': followUpAt?.toUtc().toIso8601String(),
      'interest_type': interestType?.trim().isEmpty == true ? null : interestType?.trim(),
      'quoted_price': quotedPrice,
      'reference_name': referenceName?.trim().isEmpty == true ? null : referenceName?.trim(),
      'last_contacted_at': DateTime.now().toUtc().toIso8601String(),
      'closed_at': status == 'closed' ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', leadId);
    try {
      final p = await _profile();
      await client.from('secretary_lead_activities').insert({
        'company_id': p['company_id'],
        'lead_id': leadId,
        'secretary_id': p['id'],
        'outcome_code': outcomeCode,
        'note': note?.trim().isEmpty == true ? null : note?.trim(),
        'follow_up_at': followUpAt?.toUtc().toIso8601String(),
      });
    } catch (_) {
      // Aktivite geçmişi eski veritabanında henüz kurulmadıysa ana takip kaydı yine korunur.
    }
  }

  Future<void> markWon({required String leadId, required String customerId}) async {
    await client.from('secretary_leads').update({
      'status': 'won',
      'outcome_code': 'job_won',
      'customer_id': customerId,
      'follow_up_at': null,
      'last_contacted_at': DateTime.now().toUtc().toIso8601String(),
      'converted_at': DateTime.now().toUtc().toIso8601String(),
      'closed_at': null,
    }).eq('id', leadId);
  }

  Future<Map<String, num>> todayServicePerformance() async {
    final user = client.auth.currentUser;
    if (user == null) return const {'completed': 0, 'revenue': 0};
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toUtc();
    final end = start.add(const Duration(days: 1));
    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('service_requests')
          .select('id,status,price,planned_date,completed_at')
          .eq('created_by', user.id)
          .gte('planned_date', start.toIso8601String())
          .lt('planned_date', end.toIso8601String()),
    );
    var completed = 0;
    var revenue = 0.0;
    for (final row in rows) {
      if (row['status']?.toString() == 'completed') {
        completed++;
        revenue += (row['price'] as num?)?.toDouble() ?? 0;
      }
    }
    return {'completed': completed, 'revenue': revenue};
  }
}
