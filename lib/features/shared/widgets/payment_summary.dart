import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_dates.dart';
import '../models/transaction.dart' as models;

/// Peso amount, or a friendly placeholder when Laravel has not set it.
String formatPeso(double? amount, {String fallback = 'Not available'}) =>
    amount == null ? fallback : '₱${NumberFormat('#,##0.00').format(amount)}';

/// Payment breakdown shared by the transaction history and repair details.
/// Partial payments show the amount paid and the remaining balance; unpaid
/// bills with a PayMongo link get a "Pay online" button.
class PaymentSummary extends StatelessWidget {
  const PaymentSummary({
    super.key,
    required this.transaction,
    this.showBreakdown = true,
  });

  final models.Transaction transaction;

  /// Show parts and labor lines (hidden where repair costs are listed already).
  final bool showBreakdown;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBreakdown) ...[
          PaymentRow(
            icon: Icons.receipt_long_outlined,
            label: 'Parts',
            value: formatPeso(t.partsTotal),
          ),
          PaymentRow(
            icon: Icons.build_outlined,
            label: 'Labor',
            value: formatPeso(t.laborTotal),
          ),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
        ],
        PaymentRow(
          icon: Icons.payments_outlined,
          label: 'Total',
          value: formatPeso(t.totalAmount),
        ),
        if (t.isPartial) ...[
          PaymentRow(
            icon: Icons.price_check_outlined,
            label: 'Amount paid',
            value: formatPeso(t.partialPaymentAmount),
          ),
          PaymentRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Remaining balance',
            value: formatPeso(t.remainingBalance),
            emphasize: true,
          ),
        ] else if (!t.isPaid && t.remainingBalance != null)
          PaymentRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Balance due',
            value: formatPeso(t.remainingBalance),
            emphasize: true,
          ),
        if (t.paymentMethod != null)
          PaymentRow(
            icon: Icons.credit_card_outlined,
            label: 'Payment method',
            value: t.paymentMethod!,
          ),
        if (t.referenceNo != null)
          PaymentRow(
            icon: Icons.tag_outlined,
            label: 'Reference number',
            value: t.referenceNo!,
          ),
        if (t.paidOnLabel != null)
          PaymentRow(
            icon: Icons.calendar_today_outlined,
            label: t.isPartial ? 'Last payment on' : 'Paid on',
            value: t.paidOnLabel!,
          ),
        if (!t.isPaid && t.paymentDue != null)
          PaymentRow(
            icon: Icons.event_outlined,
            label: 'Payment due',
            value: AppDates.formatDate(t.paymentDue!, 'MMM d, y'),
          ),
        if (t.receivedBy != null)
          PaymentRow(
            icon: Icons.person_outline,
            label: 'Received by',
            value: t.receivedBy!,
          ),
        if (t.canPayOnline) ...[
          const SizedBox(height: AppSpacing.xs),
          PayOnlineButton(url: t.paymentUrl!),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Icon + label/value row matching the app's detail sheets.
class PaymentRow extends StatelessWidget {
  const PaymentRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
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
                Text(
                  value,
                  style: emphasize
                      ? theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the PayMongo checkout link in the browser.
class PayOnlineButton extends StatelessWidget {
  const PayOnlineButton({super.key, required this.url});

  final String url;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'We couldn’t open the payment page. Please try again or pay at the shop.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _open(context),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.open_in_new_outlined),
      label: const Text('Pay online'),
    );
  }
}
