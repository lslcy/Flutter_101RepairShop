import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../shared/models/payment_submission.dart';
import '../../shared/models/transaction.dart' as models;
import '../../shared/widgets/payment_summary.dart' show formatPeso;
import '../data/payment_submission_repository.dart';

class CustomerPaymentScreen extends ConsumerStatefulWidget {
  const CustomerPaymentScreen({super.key, required this.transaction});
  final models.Transaction transaction;

  @override
  ConsumerState<CustomerPaymentScreen> createState() =>
      _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends ConsumerState<CustomerPaymentScreen> {
  late models.Transaction _transaction;
  PaymentSubmission? _submission;
  GcashPaymentDetails? _gcash;
  ReceiptImage? _receipt;
  int _step = 0;
  bool _loading = true;
  bool _loaded = false;
  bool _busy = false;
  bool _qrFailed = false;
  bool _qrReady = false;
  bool _receiptReady = false;
  String? _error;
  final _feedbackKey = GlobalKey();

  PaymentSubmissionRepository get _repository =>
      ref.read(paymentSubmissionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _transaction = widget.transaction;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
    });
    try {
      final submission = await _repository.latestSubmission(
        widget.transaction.id,
      );
      // Read the bill after review status so an approval cannot show an old balance.
      final transaction = await _repository.getTransaction(
        widget.transaction.id,
      );
      if (transaction == null) {
        throw const PaymentFlowException(
          'This payment is no longer available. Return to your payment history.',
        );
      }

      if (mounted) {
        setState(() {
          _transaction = transaction;
          _submission = submission;
          _loaded = true;
        });
        ref.read(paymentUpdatesProvider.notifier).state++;
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorText(Object error) {
    if (error is PaymentFlowException) return error.message;
    if (error is TimeoutException) {
      return 'This is taking longer than expected. Refresh payment status before retrying. Your receipt is still selected.';
    }
    if (error is PostgrestException) {
      if (error.code == 'P0001') return error.message;
      if (const {'PGRST202', 'PGRST205', '42P01'}.contains(error.code)) {
        return 'Payment choices are not available yet. Please contact the shop.';
      }
    }
    return 'We could not complete that request. Check your connection and try again.';
  }

  void _showError(Object error) {
    setState(() => _error = _errorText(error));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feedback = _feedbackKey.currentContext;
      if (mounted && feedback != null) {
        Scrollable.ensureVisible(
          feedback,
          alignment: 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        );
      }
    });
  }

  Future<void> _showGcash() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = await _repository.getGcashDetails();
      if (mounted) {
        setState(() {
          _gcash = details;
          _qrFailed = false;
          _qrReady = false;
          _step = 1;
        });
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payAtShop() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final submission = await _repository.choosePayAtShop(
        widget.transaction.id,
      );
      if (mounted) _finish(submission);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickReceipt() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await ref.read(receiptPickerProvider).pick();
      if (mounted && receipt != null) {
        setState(() {
          _receipt = receipt;
          _receiptReady = false;
        });
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmPayment() async {
    if (_busy || _receipt == null || !_receiptReady) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final submission = await _repository.submitGcash(
        widget.transaction.id,
        _receipt!,
      );
      if (mounted) _finish(submission);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish(PaymentSubmission submission) {
    setState(() {
      _submission = submission;
      _step = 0;
      _receipt = null;
    });
    ref.read(paymentUpdatesProvider.notifier).state++;
  }

  Widget _notice(
    IconData icon,
    String title,
    String text, {
    bool error = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: error
                  ? colors.onErrorContainer
                  : colors.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: error
                            ? colors.onErrorContainer
                            : colors.onPrimaryContainer,
                      ),
                    ),
                  if (title.isNotEmpty) const SizedBox(height: 4),
                  Text(
                    text,
                    style: AppTextStyles.body.copyWith(
                      color: error
                          ? colors.onErrorContainer
                          : colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choice(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap,
  ) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(20),
        minimumSize: const Size.fromHeight(72),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_outlined),
        ],
      ),
    );
  }

  List<Widget> _content() {
    final transaction = _transaction;
    if (!_loaded) return const <Widget>[];
    if (transaction.isPaid) {
      return [
        _notice(
          Icons.check_circle_outline,
          'Paid',
          'This payment has been confirmed by the shop.',
        ),
      ];
    }
    if (_submission?.isPending ?? false) {
      return [
        _notice(
          Icons.hourglass_top_outlined,
          'Pending',
          'Your GCash receipt was submitted. The admin will verify it before marking this payment as paid.',
        ),
        const SizedBox(height: 24),
        AppButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Refresh payment status'),
        ),
      ];
    }
    if (transaction.remainingBalance == null ||
        transaction.remainingBalance! <= 0) {
      return [
        _notice(
          Icons.info_outline,
          'Balance not available',
          'The shop needs to set your balance before you can choose a payment method.',
        ),
      ];
    }
    if (_step == 1 && _gcash != null) {
      final qrUrl = _gcash!.qrImageUrl;
      return [
        const Text('Pay with GCash', style: AppTextStyles.heading2),
        const SizedBox(height: 8),
        Text(
          'Send ${formatPeso(transaction.remainingBalance)} to ${_gcash!.recipient}.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.network(
              qrUrl,
              frameBuilder: (_, child, frame, _) {
                if (frame != null && !_qrReady) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        !_qrReady &&
                        _step == 1 &&
                        _gcash?.qrImageUrl == qrUrl) {
                      setState(() => _qrReady = true);
                    }
                  });
                }
                return child;
              },
              fit: BoxFit.contain,
              semanticLabel: 'GCash payment QR code for ${_gcash!.recipient}',
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) {
                if (!_qrFailed) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _step == 1 && _gcash?.qrImageUrl == qrUrl) {
                      setState(() {
                        _qrFailed = true;
                        _qrReady = false;
                      });
                    }
                  });
                }
                return const Center(
                  child: Text(
                    'We could not load the QR code.',
                    style: TextStyle(color: Colors.black87),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Check the recipient in GCash before paying. After payment, tap Next and upload your receipt.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Next',
          onPressed: !_qrReady || _qrFailed
              ? null
              : () => setState(() {
                  _step = 2;
                  _error = null;
                }),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: const Text('Change payment method'),
        ),
      ];
    }
    if (_step == 2) {
      final receipt = _receipt;
      return [
        const Text('Upload your receipt', style: AppTextStyles.heading2),
        const SizedBox(height: 8),
        const Text(
          'Use a screenshot that clearly shows the amount, recipient, and reference number.',
          style: AppTextStyles.body,
        ),
        const SizedBox(height: 20),
        if (_receipt != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              receipt!.bytes,
              height: 240,
              frameBuilder: (_, child, frame, _) {
                if (frame != null && !_receiptReady) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        !_receiptReady &&
                        _step == 2 &&
                        identical(_receipt, receipt)) {
                      setState(() => _receiptReady = true);
                    }
                  });
                }
                return child;
              },
              fit: BoxFit.contain,
              semanticLabel: 'Selected GCash receipt',
              errorBuilder: (_, _, _) {
                if (_receiptReady) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && identical(_receipt, receipt)) {
                      setState(() => _receiptReady = false);
                    }
                  });
                }
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'This receipt image could not be previewed. Choose another image.',
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickReceipt,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(
            _receipt == null ? 'Choose receipt screenshot' : 'Change receipt',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'JPG, PNG, or WebP · Up to 5 MB',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 24),
        AppButton(
          label: 'Confirm payment',
          loadingLabel: 'Submitting receipt...',
          onPressed: _receipt == null || !_receiptReady
              ? null
              : _confirmPayment,
          isLoading: _busy,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your payment will remain pending until the admin validates the receipt.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 1),
          child: const Text('Back to QR code'),
        ),
      ];
    }
    return [
      if (_submission?.isPayAtShop ?? false) ...[
        _notice(
          Icons.storefront_outlined,
          'Pay at the shop selected',
          'Your balance is still unpaid. The shop will confirm payment when you pay in person.',
        ),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Refresh payment status'),
        ),
        const SizedBox(height: 24),
      ],
      if (_submission?.isRejected ?? false) ...[
        _notice(
          Icons.info_outline,
          'Receipt needs attention',
          _submission!.reviewNote ?? 'The admin could not verify the receipt. Please submit a new one.',
          error: true,
        ),
        const SizedBox(height: 24),
      ],
      const Text('Choose payment method', style: AppTextStyles.heading2),
      const SizedBox(height: 16),
      _choice(
        Icons.qr_code_2_outlined,
        'GCash',
        'Pay by QR code and submit your receipt.',
        _busy ? null : _showGcash,
      ),
      const SizedBox(height: 12),
      _choice(
        Icons.storefront_outlined,
        'Pay at the shop',
        'Pay in person when you visit.',
        _busy ? null : _payAtShop,
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Payment'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            KeyedSubtree(
                              key: _feedbackKey,
                              child: _notice(
                                Icons.error_outline,
                                '',
                                _error!,
                                error: true,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('Refresh payment status'),
                            ),
                          ],
                          Text(
                            'Transaction #${transaction.id}',
                            style: AppTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatPeso(transaction.remainingBalance),
                            style: AppTextStyles.heading1,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Balance due',
                            style: AppTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 24),
                          ..._content(),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
