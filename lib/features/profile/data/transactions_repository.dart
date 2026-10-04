import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../shared/models/transaction.dart' as models;

// Provides the transactions repository
final transactionsRepositoryProvider = Provider(
  (ref) => TransactionsRepository(),
);

// Handles payment transactions for the signed-in customer
class TransactionsRepository {
  TransactionsRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client,
      _accounts = CustomerAccountService(
        supabase: supabase ?? Supabase.instance.client,
      );

  final SupabaseClient _supabase;
  final CustomerAccountService _accounts;

  bool get isSignedIn => _supabase.auth.currentUser != null;

  /// All non-archived transactions for the current customer, newest first.
  /// Returns `null` when no customer profile is linked to the account.
  Future<List<models.Transaction>?> getTransactions() async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) return null;
    final data = await _supabase
        .from('transactions')
        .select()
        .eq('customer_id', customerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return data.map(models.Transaction.fromJson).toList();
  }

  /// Non-archived transactions for one service report.
  Future<List<models.Transaction>> getTransactionsForReport(
    int reportId,
  ) async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) return [];
    final data = await _supabase
        .from('transactions')
        .select()
        .eq('report_id', reportId)
        .eq('customer_id', customerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return data.map(models.Transaction.fromJson).toList();
  }
}
