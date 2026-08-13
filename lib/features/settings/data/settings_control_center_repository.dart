import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyBackupRecord {
  const CompanyBackupRecord({
    required this.id,
    required this.createdAt,
    required this.counts,
    required this.snapshot,
    this.label,
    this.createdBy,
  });

  final String id;
  final DateTime createdAt;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> snapshot;
  final String? label;
  final String? createdBy;

  factory CompanyBackupRecord.fromMap(Map<String, dynamic> map) {
    return CompanyBackupRecord(
      id: map['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      counts: _map(map['counts']),
      snapshot: _map(map['snapshot']),
      label: map['label']?.toString(),
      createdBy: map['created_by']?.toString(),
    );
  }
}

class SettingsAuditEntry {
  const SettingsAuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.userId,
    this.userName,
    this.metadata = const {},
  });

  final int id;
  final String action;
  final String entityType;
  final String? entityId;
  final String? userId;
  final String? userName;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;
}

class SettingsControlCenterRepository {
  SettingsControlCenterRepository(this._client);

  final SupabaseClient _client;

  Future<List<CompanyBackupRecord>> listBackups({int limit = 20}) async {
    final rows = await _client
        .from('company_data_backups')
        .select('id, created_at, label, created_by, counts')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((row) => CompanyBackupRecord.fromMap(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);
  }

  Future<CompanyBackupRecord> loadBackup(String backupId) async {
    final row = await _client
        .from('company_data_backups')
        .select('id, created_at, label, created_by, counts, snapshot')
        .eq('id', backupId)
        .single();
    return CompanyBackupRecord.fromMap(Map<String, dynamic>.from(row));
  }

  Future<CompanyBackupRecord> importBackup({
    required Map<String, dynamic> snapshot,
    Map<String, dynamic> counts = const <String, dynamic>{},
    String? label,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Oturum bulunamadı.');
    final profile = await _client
        .from('profiles')
        .select('company_id, role')
        .eq('id', user.id)
        .single();
    final companyId = profile['company_id']?.toString() ?? '';
    final role = profile['role']?.toString() ?? '';
    if (companyId.isEmpty || (role != 'admin' && role != 'manager')) {
      throw StateError('Yedek içeri aktarmak için yönetici yetkisi gerekir.');
    }
    final row = await _client
        .from('company_data_backups')
        .insert({
          'company_id': companyId,
          'created_by': user.id,
          'label': label ?? 'Dosyadan içe aktarılan yedek',
          'counts': counts,
          'snapshot': snapshot,
        })
        .select('id, created_at, label, created_by, counts, snapshot')
        .single();
    return CompanyBackupRecord.fromMap(Map<String, dynamic>.from(row));
  }

  Future<CompanyBackupRecord> createBackup({String? label}) async {
    final result = await _client.rpc(
      'create_company_backup_v1',
      params: {'p_label': label},
    );
    final id = result?.toString() ?? '';
    if (id.isEmpty) {
      throw StateError('Yedek kimliği alınamadı.');
    }
    final row = await _client
        .from('company_data_backups')
        .select('id, created_at, label, created_by, counts, snapshot')
        .eq('id', id)
        .single();
    return CompanyBackupRecord.fromMap(Map<String, dynamic>.from(row));
  }

  Future<Map<String, dynamic>> restoreBackup(String backupId) async {
    final result = await _client.rpc(
      'restore_company_backup_v1',
      params: {'p_backup_id': backupId},
    );
    return _map(result);
  }

  Future<void> deleteBackup(String backupId) async {
    await _client.from('company_data_backups').delete().eq('id', backupId);
  }

  Future<List<SettingsAuditEntry>> loadAudit({int limit = 50}) async {
    final rows = await _client
        .from('audit_logs')
        .select('id, user_id, action, entity_type, entity_id, metadata, created_at')
        .order('created_at', ascending: false)
        .limit(limit);

    final maps = (rows as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final ids = maps
        .map((e) => e['user_id']?.toString())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final names = <String, String>{};
    if (ids.isNotEmpty) {
      try {
        final profiles = await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', ids);
        for (final raw in (profiles as List).whereType<Map>()) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            names[id] = row['full_name']?.toString() ?? 'Kullanıcı';
          }
        }
      } catch (_) {
        // İsim bilgisi alınamazsa log yine gösterilir.
      }
    }

    return maps.map((row) {
      final userId = row['user_id']?.toString();
      return SettingsAuditEntry(
        id: int.tryParse(row['id']?.toString() ?? '') ?? 0,
        action: row['action']?.toString() ?? 'işlem',
        entityType: row['entity_type']?.toString() ?? 'kayıt',
        entityId: row['entity_id']?.toString(),
        userId: userId,
        userName: userId == null ? 'Sistem' : names[userId],
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        metadata: _map(row['metadata']),
      );
    }).toList(growable: false);
  }
}

final settingsControlCenterRepositoryProvider =
    Provider<SettingsControlCenterRepository>((ref) {
  return SettingsControlCenterRepository(Supabase.instance.client);
});

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}
