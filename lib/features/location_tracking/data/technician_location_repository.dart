import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TechnicianLocationSnapshot {
  const TechnicianLocationSnapshot({
    required this.technicianId,
    required this.technicianName,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.recordedAt,
    this.source,
    this.isSharing = false,
  });

  final String technicianId;
  final String technicianName;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final DateTime? recordedAt;
  final String? source;
  final bool isSharing;

  bool get hasLocation => latitude != null && longitude != null;

  bool get isFresh {
    if (!isSharing) return false;
    final value = recordedAt;
    if (value == null) return false;
    return DateTime.now().difference(value.toLocal()).abs() <
        const Duration(minutes: 5);
  }
}

class TechnicianLocationHistoryPoint {
  const TechnicianLocationHistoryPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyM,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? accuracyM;
}

class TechnicianLocationRepository {
  TechnicianLocationRepository(this._client);

  final SupabaseClient _client;

  Future<void> pushPosition(Position position, {String source = 'web'}) async {
    await _client.rpc(
      'technician_push_location_v1',
      params: <String, dynamic>{
        'p_latitude': position.latitude,
        'p_longitude': position.longitude,
        'p_accuracy_m': position.accuracy,
        'p_speed_mps': position.speed.isFinite && position.speed >= 0
            ? position.speed
            : null,
        'p_heading_deg': position.heading.isFinite && position.heading >= 0
            ? position.heading
            : null,
        'p_source': source,
      },
    );
  }

  Future<void> setSharing(bool active) async {
    await _client.rpc(
      'technician_set_location_sharing_v1',
      params: <String, dynamic>{'p_active': active},
    );
  }

  Future<List<TechnicianLocationSnapshot>> getCurrentTechnicians() async {
    final user = _client.auth.currentUser;
    if (user == null) return const <TechnicianLocationSnapshot>[];
    final viewer = await _client
        .from('profiles')
        .select('company_id')
        .eq('id', user.id)
        .maybeSingle();
    final companyId = viewer?['company_id']?.toString() ?? '';
    if (companyId.isEmpty) return const <TechnicianLocationSnapshot>[];

    final profileRows = List<Map<String, dynamic>>.from(
      await _client
          .from('profiles')
          .select('id, full_name, is_active, role')
          .eq('company_id', companyId)
          .eq('role', 'technician')
          .eq('is_active', true)
          .order('full_name'),
    );

    List<Map<String, dynamic>> locationRows = const <Map<String, dynamic>>[];
    try {
      locationRows = List<Map<String, dynamic>>.from(
        await _client
            .from('technician_current_locations')
            .select(
              'technician_id, latitude, longitude, accuracy_m, recorded_at, source, is_sharing',
            ),
      );
    } on PostgrestException catch (error) {
      if (error.code == '42P01' ||
          error.message.toLowerCase().contains('technician_current_locations')) {
        throw const TechnicianLocationSchemaMissingException();
      }
      rethrow;
    }

    final byTechnician = <String, Map<String, dynamic>>{
      for (final row in locationRows)
        row['technician_id']?.toString() ?? '': row,
    }..remove('');

    return profileRows.map((profile) {
      final id = profile['id']?.toString() ?? '';
      final row = byTechnician[id];
      return TechnicianLocationSnapshot(
        technicianId: id,
        technicianName: profile['full_name']?.toString().trim().isNotEmpty == true
            ? profile['full_name'].toString().trim()
            : 'Tekniker',
        latitude: _asDouble(row?['latitude']),
        longitude: _asDouble(row?['longitude']),
        accuracyM: _asDouble(row?['accuracy_m']),
        recordedAt: _asDateTime(row?['recorded_at']),
        source: row?['source']?.toString(),
        isSharing: row?['is_sharing'] == true,
      );
    }).toList(growable: false);
  }

  Future<List<TechnicianLocationHistoryPoint>> getHistory({
    required String technicianId,
    required DateTime day,
  }) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('technician_location_history')
          .select('latitude, longitude, accuracy_m, recorded_at')
          .eq('technician_id', technicianId)
          .gte('recorded_at', start.toUtc().toIso8601String())
          .lt('recorded_at', end.toUtc().toIso8601String())
          .order('recorded_at', ascending: false)
          .limit(600),
    );

    return rows
        .map((row) {
          final lat = _asDouble(row['latitude']);
          final lon = _asDouble(row['longitude']);
          final at = _asDateTime(row['recorded_at']);
          if (lat == null || lon == null || at == null) return null;
          return TechnicianLocationHistoryPoint(
            latitude: lat,
            longitude: lon,
            recordedAt: at,
            accuracyM: _asDouble(row['accuracy_m']),
          );
        })
        .whereType<TechnicianLocationHistoryPoint>()
        .toList(growable: false);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}

class TechnicianLocationSchemaMissingException implements Exception {
  const TechnicianLocationSchemaMissingException();

  @override
  String toString() => 'Tekniker konum veritabanı henüz kurulmadı.';
}

final technicianLocationRepositoryProvider = Provider<TechnicianLocationRepository>((ref) {
  return TechnicianLocationRepository(Supabase.instance.client);
});
