import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/service_details.dart';
import '../../shared/models/service_report.dart';
import '../../shared/widgets/payment_summary.dart';
import '../data/repairs_repository.dart';

class RepairDetailScreen extends ConsumerStatefulWidget {
  final int reportId;
  const RepairDetailScreen({super.key, required this.reportId});

  @override
  ConsumerState<RepairDetailScreen> createState() => _RepairDetailScreenState();
}

class _RepairDetailScreenState extends ConsumerState<RepairDetailScreen> {
  ServiceReport? _report;
  RepairExtras _extras = const RepairExtras();
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _isLoading = _report == null;
      _loadError = null;
    });
    try {
      final repository = ref.read(repairsRepositoryProvider);
      final report = await repository
          .getRepairById(widget.reportId)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _report = report;
      if (report != null) {
        // Cost details, payments and staff notes are optional extras; a
        // failure there must not hide the report itself.
        try {
          _extras = await repository
              .getRepairExtras(report.id)
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          _extras = RepairExtras(
            details: _extras.details,
            detailsFailed: _extras.details == null,
            comments: _extras.comments,
            transactions: _extras.transactions,
          );
        }
      }
    } on TimeoutException {
      _loadError = 'Your repair report is taking longer than expected. Check your connection and try again.';
    } catch (_) {
      _loadError = 'We couldn’t load this repair report. Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Repair details')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: RefreshIndicator(
              onRefresh: _loadReport,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_isLoading)
                    const SliverToBoxAdapter(
                      child: ShimmerLoading(label: 'Loading repair details…'),
                    )
                  else if (_report == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildUnavailable(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverToBoxAdapter(child: _buildDetails()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final details = _extras.details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRefreshing) ...[
          Semantics(
            liveRegion: true,
            child: const Text('Refreshing repair details…'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_loadError != null) ...[
          _buildRefreshError(),
          const SizedBox(height: AppSpacing.md),
        ],
        _buildStatusHeader(),
        const SizedBox(height: AppSpacing.md),
        _buildTimeline(),
        const SizedBox(height: AppSpacing.md),
        _buildAssessment(details),
        const SizedBox(height: AppSpacing.md),
        if (details != null) ...[
          _buildCosts(details),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_extras.transactions.isNotEmpty) ...[
          _buildPayments(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_extras.comments.isNotEmpty) ...[
          _buildProgressComments(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_report!.findings?.trim().isNotEmpty ?? false)
          _buildInfoSection(
            'Findings',
            _report!.findings!,
            Icons.search_outlined,
          ),
        if (_report!.remarks?.trim().isNotEmpty ?? false)
          _buildInfoSection(
            'Remarks',
            _report!.remarks!,
            Icons.comment_outlined,
          ),
        if (_report!.usedParts?.trim().isNotEmpty ?? false)
          _buildInfoSection(
            'Parts used',
            _report!.usedParts!,
            Icons.settings_outlined,
          ),
        if (_report!.dealer?.trim().isNotEmpty ?? false)
          _buildInfoSection('Dealer', _report!.dealer!, Icons.store_outlined),
      ],
    );
  }

  Widget _buildRefreshError() {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.errorContainer,
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Showing previously loaded details.',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _loadError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            TextButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    final theme = Theme.of(context);
    final report = _report!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Service report #${report.id}',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(status: RepairStatus.normalize(report.status)),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final received = _buildDetailItem(
                icon: Icons.calendar_today_outlined,
                label: 'Received on',
                value: report.dateIn == null
                    ? 'Not recorded'
                    : AppDates.format(report.dateIn!, 'MMM d, y'),
              );
              final collected = _buildDetailItem(
                icon: Icons.calendar_month_outlined,
                label: 'Collected on',
                value: report.datePulledOut == null
                    ? 'Not recorded'
                    : AppDates.format(report.datePulledOut!, 'MMM d, y'),
              );
              if (constraints.maxWidth < 440 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18) {
                return Column(
                  children: [
                    received,
                    const SizedBox(height: AppSpacing.md),
                    collected,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: received),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: collected),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = RepairStatus.normalize(_report!.status);
    final cancelled = status == RepairStatus.cancelled;
    final completed = status == RepairStatus.completed;
    // Waiting for Parts and Under Repair share the repair stage, so the
    // stepper never claims a step happened when staff skipped it.
    final currentStage = switch (status) {
      RepairStatus.pending => 0,
      RepairStatus.inProgress => 1,
      RepairStatus.waitingForParts || RepairStatus.underRepair => 2,
      RepairStatus.completed => 3,
      _ => null,
    };
    const labels = ['Received', 'Diagnosis', 'Parts & repair', 'Completed'];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Progress', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            cancelled
                ? 'This repair was cancelled. Contact the shop if you have questions.'
                : currentStage == null
                ? 'Current status: $status. The shop will update the repair progress here.'
                : 'Based on the latest repair status.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (currentStage != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ...List.generate(labels.length, (index) {
              final done = index < currentStage || completed;
              final current = index == currentStage && !done;
              final stageLabel = done
                  ? 'Complete'
                  : current
                  ? (index == 2 ? 'Current stage · $status' : 'Current stage')
                  : 'Upcoming';
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == labels.length - 1 ? 0 : AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        done
                            ? Icons.check_circle_outline
                            : current
                            ? Icons.radio_button_checked_outlined
                            : Icons.radio_button_unchecked_outlined,
                        size: 24,
                        color: done || current
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels[index],
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            stageLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
        ),
      ],
    );
  }

  Widget _buildAssessment(ServiceDetails? details) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (details == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader('Repair assessment', Icons.fact_check_outlined),
            const SizedBox(height: AppSpacing.md),
            Text(
              _extras.detailsFailed
                  ? 'Cost details are unavailable'
                  : 'Not yet assessed',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _extras.detailsFailed
                  ? 'We couldn’t load the technician’s assessment right now. Pull down to refresh.'
                  : 'The technician will add the complaint, services and repair cost after checking your appliance.',
              style: muted,
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('Repair assessment', Icons.fact_check_outlined),
          const SizedBox(height: AppSpacing.lg),
          if (details.complaint != null) ...[
            _buildDetailItem(
              icon: Icons.report_problem_outlined,
              label: 'Complaint',
              value: details.complaint!,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _buildDetailItem(
            icon: Icons.handyman_outlined,
            label: 'Services',
            value: details.serviceTypes.isEmpty
                ? 'Not specified yet'
                : details.serviceTypes.join(', '),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildDetailItem(
            icon: Icons.engineering_outlined,
            label: details.technicians.length > 1 ? 'Technicians' : 'Technician',
            value: details.technicians.isEmpty
                ? 'Not assigned yet'
                : details.technicians.join(', '),
          ),
          if (details.dateRepaired != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildDetailItem(
              icon: Icons.build_circle_outlined,
              label: 'Repaired on',
              value: AppDates.format(details.dateRepaired!, 'MMM d, y'),
            ),
          ],
          if (details.dateDelivered != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildDetailItem(
              icon: Icons.local_shipping_outlined,
              label: 'Delivered on',
              value: AppDates.format(details.dateDelivered!, 'MMM d, y'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCosts(ServiceDetails details) {
    final theme = Theme.of(context);
    Widget line(String label, double? amount, {bool total = false}) {
      final style = total
          ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
          : theme.textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: AppSpacing.sm),
            Text(formatPeso(amount, fallback: '—'), style: style),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('Repair cost', Icons.payments_outlined),
          const SizedBox(height: AppSpacing.lg),
          line('Labor', details.labor),
          line('Parts', details.partsTotalCharge),
          line('Miscellaneous', details.miscellaneousCost),
          line('Pull-out / delivery', details.pulloutDelivery),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          line('Total', details.computedTotal, total: true),
        ],
      ),
    );
  }

  Widget _buildPayments() {
    final transactions = _extras.transactions;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('Payment', Icons.receipt_long_outlined),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < transactions.length; i++) ...[
            if (i > 0) ...[
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(status: transactions[i].status),
            ),
            const SizedBox(height: AppSpacing.md),
            PaymentSummary(
              transaction: transactions[i],
              showBreakdown: _extras.details == null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressComments() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final comments = _extras.comments;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('Progress updates', Icons.timeline_outlined),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < comments.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == comments.length - 1 ? 0 : AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      i == comments.length - 1
                          ? Icons.radio_button_checked_outlined
                          : Icons.check_circle_outline,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (comments[i].progressLabel != null) ...[
                          Text(
                            comments[i].progressLabel!,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        if (comments[i].commentText.isNotEmpty)
                          Text(
                            comments[i].commentText,
                            style: theme.textTheme.bodyMedium,
                          ),
                        if (_commentMeta(comments[i]) != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _commentMeta(comments[i])!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _commentMeta(ServiceProgressComment comment) {
    final parts = [
      if (comment.createdByName != null) comment.createdByName!,
      if (comment.createdAt != null)
        AppDates.format(comment.createdAt!, 'MMM d, y · h:mm a'),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _buildInfoSection(String title, String content, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(content, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _loadError == null
                  ? Icons.search_off_outlined
                  : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _loadError == null
                  ? 'Report not found'
                  : 'Repair details unavailable',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _loadError ?? 'This report may have been removed. Refresh to check again.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _loadError == null ? 'Refresh' : 'Try again',
              icon: Icons.refresh_outlined,
              onPressed: _loadReport,
            ),
          ],
        ),
      ),
    );
  }
}
