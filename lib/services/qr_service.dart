import 'package:supabase_flutter/supabase_flutter.dart';

class QrResult {
  final int qrId;
  final String code;
  final String status;
  final int? deviceId;

  const QrResult({
    required this.qrId,
    required this.code,
    required this.status,
    required this.deviceId,
  });

  bool get isUsed => status == 'used' || deviceId != null;
}

class QrService {
  QrService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<QrResult?> lookupQr(String qrCode) async {
    final temizKod = qrCode.trim().toUpperCase();

    if (temizKod.isEmpty) {
      throw Exception('QR kodu boş olamaz.');
    }

    final response = await _supabase.rpc(
      'lookup_qr',
      params: {'p_code': temizKod},
    );

    if (response is! List || response.isEmpty) {
      return null;
    }

    final row = Map<String, dynamic>.from(response.first as Map);

    return QrResult(
      qrId: (row['qr_id'] as num).toInt(),
      code: row['code'].toString(),
      status: row['status'].toString(),
      deviceId: row['device_id'] == null
          ? null
          : (row['device_id'] as num).toInt(),
    );
  }
}
