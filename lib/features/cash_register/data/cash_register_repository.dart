import 'package:supabase_flutter/supabase_flutter.dart';

class CashRegisterRepository {
  CashRegisterRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> summary() async {
    final raw = await client
        .rpc('cash_register_summary_v66')
        .timeout(const Duration(seconds: 6));
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<List<Map<String, dynamic>>> staff() async {
    final raw = await client
        .rpc('cash_expense_staff_v66')
        .timeout(const Duration(seconds: 6));
    return (raw as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> transferToMain({
    required String profileId,
    required double amount,
    String? note,
  }) async {
    await client.rpc('cash_transfer_to_main_v66', params: {
      'p_from_profile_id': profileId,
      'p_amount': amount,
      'p_note': note,
    }).timeout(const Duration(seconds: 6));
  }

  Future<void> addExpense({
    required String category,
    required double amount,
    required String paymentSource,
    String? beneficiaryProfileId,
    String? sourceProfileId,
    String? note,
    String? documentNo,
    DateTime? expenseAt,
  }) async {
    await client.rpc('cash_add_expense_v66', params: {
      'p_category': category,
      'p_amount': amount,
      'p_payment_source': paymentSource,
      'p_beneficiary_profile_id': beneficiaryProfileId,
      'p_source_profile_id': sourceProfileId,
      'p_note': note,
      'p_document_no': documentNo,
      'p_expense_at': (expenseAt ?? DateTime.now()).toUtc().toIso8601String(),
    }).timeout(const Duration(seconds: 6));
  }

  Future<void> updateExpense({
    required String movementId,
    required String category,
    required double amount,
    required String paymentSource,
    String? beneficiaryProfileId,
    String? sourceProfileId,
    String? note,
    String? documentNo,
    DateTime? expenseAt,
  }) async {
    await client.rpc('cash_update_expense_v66', params: {
      'p_movement_id': movementId,
      'p_category': category,
      'p_amount': amount,
      'p_payment_source': paymentSource,
      'p_beneficiary_profile_id': beneficiaryProfileId,
      'p_source_profile_id': sourceProfileId,
      'p_note': note,
      'p_document_no': documentNo,
      'p_expense_at': (expenseAt ?? DateTime.now()).toUtc().toIso8601String(),
    }).timeout(const Duration(seconds: 6));
  }

  Future<void> deleteExpense(String movementId) async {
    await client.rpc('cash_delete_expense_v66', params: {
      'p_movement_id': movementId,
    }).timeout(const Duration(seconds: 6));
  }
}
