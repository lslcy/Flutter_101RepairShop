import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/transaction.dart' as models;
import '../../shared/widgets/payment_summary.dart';
import '../data/transactions_repository.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  List<models.Transaction> _transactions = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _needsSignIn = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (_isRefreshing) return;
    setState(() {
      _isLoading = _transactions.isEmpty;
      _isRefreshing = true;
      _loadError = null;
      _needsSignIn = false;
    });
    try {
      final repository = ref.read(transactionsRepositoryProvider);
      if (!repository.isSignedIn) {
        _transactions = [];
        _needsSignIn = true;
        _loadError = 'Sign in again to view your transaction history.';
        return;
      }
      final transactions = await repository.getTransactions().timeout(
        const Duration(seconds: 20),
      );
      if (!mounted) return;
      if (transactions == null) {
        _loadError = 'Your customer profile could not be found. Try again, or contact the shop if this continues.';
        return;
      }
      _transactions = transactions;
    } on TimeoutException {
      _loadError = 'Your transactions are taking longer than expected. Check your connection and try again.';
    } catch (_) {
      _loadError =
          'We couldn’t load your transaction history. Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  String _formatPeso(double? amount) => formatPeso(amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _loadTransactions,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_isLoading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: AppSpacing.md),
                        child: ShimmerListLoading(
                          label: 'Loading transaction history…',
                        ),
                      ),
                    )
                  else if (_transactions.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyOrErrorState(),
                    )
                  else ...[
                    if (_isRefreshing)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Semantics(
                            liveRegion: true,
                            child: Text('Refreshing transaction history…'),
                          ),
                        ),
                      ),
                    if (_loadError != null)
                      SliverToBoxAdapter(child: _buildRefreshError()),
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverList.separated(
                        itemCount: _transactions.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _buildTransactionCard(_transactions[index]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshError() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: AppCard(
        color: theme.colorScheme.errorContainer,
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Showing previously loaded transactions.',
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
                onPressed: _loadTransactions,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(models.Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: () => _showTransactionDetail(transaction),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.receipt_long_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Transaction #${transaction.id}',
                      style: theme.textTheme.titleSmall,
                    ),
                    StatusBadge(status: transaction.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formatPeso(transaction.totalAmount),
                  style: theme.textTheme.titleLarge,
                ),
                if (transaction.reportId != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Repair SR-${transaction.reportId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!transaction.isPaid &&
                    transaction.remainingBalance != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    transaction.isPartial
                        ? 'Paid ${_formatPeso(transaction.partialPaymentAmount)} · Balance ${_formatPeso(transaction.remainingBalance)}'
                        : 'Balance due ${_formatPeso(transaction.remainingBalance)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (transaction.createdAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppDates.format(transaction.createdAt!, 'MMM d, y'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (transaction.canPayOnline) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PayOnlineButton(url: transaction.paymentUrl!),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  void _showTransactionDetail(models.Transaction transaction) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Transaction #${transaction.id}',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(status: transaction.status),
                ),
                const SizedBox(height: AppSpacing.lg),
                PaymentSummary(transaction: transaction),
                const SizedBox(height: AppSpacing.sm),
                AppButton(
                  label: 'Close details',
                  isOutlined: true,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyOrErrorState() {
    final theme = Theme.of(context);
    final hasError = _loadError != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.receipt_long_outlined,
              size: 48,
              color: hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasError
                  ? 'Transaction history unavailable'
                  : 'No transactions yet',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: hasError,
              child: Text(
                _loadError ?? 'Your repair charges and payments will appear here. Pull down to refresh.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _needsSignIn ? 'Sign in' : 'Try again',
                icon: _needsSignIn
                    ? Icons.login_outlined
                    : Icons.refresh_outlined,
                onPressed: _needsSignIn
                    ? () => context.go('/login')
                    : _loadTransactions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
