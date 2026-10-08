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
/// Customer read access to these staff-side tables is granted by RLS on the
/// database side; an empty or denied result simply hides that section.
class RepairExtras {
  const RepairExtras({
    this.details,
    this.detailsFailed = false,
    this.parts = const [],
    this.comments = const [],
    this.transactions = const [],
  });

  /// `service_details` row, or `null` when the repair is not yet assessed.
  final ServiceDetails? details;

  /// True when the cost details could not be loaded (as opposed to missing).
  final bool detailsFailed;

  /// Parts recorded in `part_service_report`.
  final List<PartUsed> parts;
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

  // Get all non-archived repairs for current customer. `service_reports` is
  // SELECT-only for customers: bookings go through `appointments`, and staff
  // turn a confirmed appointment into a report from the admin site.
  Future<List<ServiceReport>> getRepairs() async {
    final customerId = await _accounts.requireCustomerId();

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
    final customerId = await _accounts.requireCustomerId();

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

  /// Parts used on the report. The pivot is keyed by `service_report_id`.
  /// Part names are embedded from `parts`; if the embed is unavailable the
  /// names are fetched separately, and finally fall back to `Part #id`.
  Future<List<PartUsed>> getPartsUsed(int reportId) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await _supabase
          .from('part_service_report')
          .select(
            'id, part_id, quantity, price, is_not_working, created_at, '
            'parts(name)',
          )
          .eq('service_report_id', reportId)
          .order('id', ascending: true);
      return rows.map(PartUsed.fromJson).toList();
    } on PostgrestException catch (error) {
      debugPrint('Parts embed unavailable, loading separately: $error');
    }

    rows = await _supabase
        .from('part_service_report')
        .select()
        .eq('service_report_id', reportId)
        .order('id', ascending: true);
    if (rows.isEmpty) return const [];

    final names = <int, String>{};
    final partIds = rows
        .map((row) => (row['part_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();
    if (partIds.isNotEmpty) {
      try {
        final parts = await _supabase
            .from('parts')
            .select('id, name')
            .inFilter('id', partIds);
        for (final part in parts) {
          final id = (part['id'] as num?)?.toInt();
          final name = part['name']?.toString().trim() ?? '';
          if (id != null && name.isNotEmpty) names[id] = name;
        }
      } catch (error) {
        debugPrint('Part names unavailable: $error');
      }
    }
    return rows
        .map(
          (row) => PartUsed.fromJson(
            row,
            fallbackName: names[(row['part_id'] as num?)?.toInt()],
          ),
        )
        .toList();
  }

  /// Loads everything shown beside the report. Failures are contained so the
  /// report still renders: missing details show as "Awaiting assessment" and
  /// empty or denied lists hide their section.
  Future<RepairExtras> getRepairExtras(int reportId) async {
    ServiceDetails? details;
    var detailsFailed = false;
    var parts = <PartUsed>[];
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
      getPartsUsed(reportId)
          .then((value) => parts = value)
          .catchError((Object error) {
            debugPrint('Parts used unavailable: $error');
            return <PartUsed>[];
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
      parts: parts,
      comments: comments,
      transactions: transactions,
    );
  }
}
