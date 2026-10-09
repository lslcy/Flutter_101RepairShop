import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../shared/models/transaction.dart' as models;
import '../../shared/models/payment_submission.dart';

// Provides the transactions repository
final transactionsRepositoryProvider = Provider(
  (ref) => TransactionsRepository(),
);

// Reads payment transactions for the signed-in customer. Read-only on
// purpose: RLS gives customers SELECT only on `transactions`. Payments are
// recorded by staff in the web admin or through the PayMongo `payment_url`.
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
    return _withCustomerPayments(
      data.map(models.Transaction.fromJson).toList(),
    );
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
    return _withCustomerPayments(
      data.map(models.Transaction.fromJson).toList(),
    );
  }

  Future<List<models.Transaction>> _withCustomerPayments(
    List<models.Transaction> transactions,
  ) async {
    if (transactions.isEmpty) return transactions;
    try {
      final rows = await _supabase
          .from('customer_payment_submissions')
          .select()
          .inFilter(
            'transaction_id',
            transactions.map((transaction) => transaction.id).toList(),
          )
          .neq('status', 'superseded')
          .order('created_at', ascending: false);
      final latest = <int, PaymentSubmission>{};
      for (final row in rows) {
        final submission = PaymentSubmission.fromJson(row);
        latest.putIfAbsent(submission.transactionId, () => submission);
      }
      return transactions
          .map(
            (transaction) =>
                transaction.withCustomerPayment(latest[transaction.id]),
          )
          .toList();
    } on PostgrestException catch (error) {
      // Existing financial records stay readable before the new migration runs.
      if (!const {'42P01', 'PGRST205'}.contains(error.code)) rethrow;
      debugPrint('Customer payment review tables have not been configured.');
      return transactions;
    }
  }
}
