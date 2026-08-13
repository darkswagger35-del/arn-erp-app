import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerService {
  CustomerService._();

  static final _db = Supabase.instance.client;

  // Şimdilik sabit şirket.
  // Sonra giriş yapan kullanıcının company_id'si gelecek.
  static const int companyId = 1;

  static Future<int> createCustomer({
    required String fullName,
    required String phone,
    required String city,
    required String district,
    required String address,
    String? note,
  }) async {
    final result = await _db
        .from('customers')
        .insert({
          'company_id': companyId,
          'full_name': fullName,
          'phone': phone,
          'city': city,
          'district': district,
          'address': address,
          'notes': note,
        })
        .select('id')
        .single();

    return result['id'] as int;
  }
}
