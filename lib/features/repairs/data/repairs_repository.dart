import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../profile/data/transactions_repository.dart';
import '../../shared/models/service_details.dart';
import '../../shared/models/service_report.dart';
import '../../shared/models/transaction.dart' as models;

// Provides the repairs repository
final repairsRepositoryProvider = Provider((ref) => RepairsRepository());

/// Supplementary data shown on the repair details screen. Each part loads
/// independently so one unavailable table never hides the report itself.
class RepairExtras {
  const RepairExtras({
    this.details,
    this.detailsFailed = false,
    this.comments = const [],
    this.transactions = const [],
  });

  /// `service_details` row, or `null` when the repair is not yet assessed.
  final ServiceDetails? details;

  /// True when the cost details could not be loaded (as opposed to missing).
  final bool detailsFailed;
  final List<ServiceProgressComment> comments;
  final List<models.Transaction> transactions;
}

// Handles service report data
class RepairsRepository {
  RepairsRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client,
      _accounts = CustomerAccountService(
        supabase: supabase ?? Supabase.instance.client,
      ),
      _transactions = TransactionsRepository(
        supabase: supabase ?? Supabase.instance.client,
      );

  final SupabaseClient _supabase;
  final CustomerAccountService _accounts;
  final TransactionsRepository _transactions;

  // Get all non-archived repairs for current customer
  Future<List<ServiceReport>> getRepairs() async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) return [];

    final data = await _supabase
        .from('service_reports')
        .select()
        .eq('customer_id', customerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data.map(ServiceReport.fromJson).toList();
  }

  // Get single non-archived repair by ID for the current customer
  Future<ServiceReport?> getRepairById(int id) async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) return null;

    final data = await _supabase
        .from('service_reports')
        .select()
        .eq('id', id)
        .eq('customer_id', customerId)
        .isFilter('deleted_at', null)
        .maybeSingle();

    if (data == null) return null;
    return ServiceReport.fromJson(data);
  }

  /// Cost, technician and complaint details entered in the web admin.
  /// Returns `null` while the repair has not been assessed yet.
  Future<ServiceDetails?> getServiceDetails(int reportId) async {
    final rows = await _supabase
        .from('service_details')
        .select()
        .eq('report_id', reportId)
        .limit(1);
    return rows.isEmpty ? null : ServiceDetails.fromJson(rows.first);
  }

  /// Staff progress notes, oldest first, for the progress timeline.
  Future<List<ServiceProgressComment>> getProgressComments(
    int reportId,
  ) async {
    final rows = await _supabase
        .from('service_progress_comments')
        .select()
        .eq('report_id', reportId)
        .order('created_at', ascending: true);
    return rows.map(ServiceProgressComment.fromJson).toList();
  }

  /// Loads everything shown beside the report. Failures are contained so the
  /// report still renders: missing details show as "Not yet assessed".
  Future<RepairExtras> getRepairExtras(int reportId) async {
    ServiceDetails? details;
    var detailsFailed = false;
    var comments = <ServiceProgressComment>[];
    var transactions = <models.Transaction>[];

    await Future.wait([
      getServiceDetails(reportId)
          .then((value) => details = value)
          .catchError((Object error) {
            detailsFailed = true;
            debugPrint('Service details unavailable: $error');
            return null;
          }),
      getProgressComments(reportId)
          .then((value) => comments = value)
          .catchError((Object error) {
            debugPrint('Progress comments unavailable: $error');
            return <ServiceProgressComment>[];
          }),
      _transactions
          .getTransactionsForReport(reportId)
          .then((value) => transactions = value)
          .catchError((Object error) {
            debugPrint('Report transactions unavailable: $error');
            return <models.Transaction>[];
          }),
    ]);

    return RepairExtras(
      details: details,
      detailsFailed: detailsFailed,
      comments: comments,
      transactions: transactions,
    );
  }
}
