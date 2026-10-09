import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/payment_submission.dart';
import '../../shared/models/transaction.dart' as models;

final paymentSubmissionRepositoryProvider = Provider(
  (ref) => PaymentSubmissionRepository(),
);
final receiptPickerProvider = Provider<ReceiptPicker>((ref) => ReceiptPicker());
final paymentUpdatesProvider = StateProvider<int>((ref) => 0);

class ReceiptPicker {
  Future<ReceiptImage?> pick() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    if (await image.length() > ReceiptImage.maxBytes) {
      throw const PaymentFlowException(
        'Choose a receipt image smaller than 5 MB.',
      );
    }
    return ReceiptImage(bytes: await image.readAsBytes());
  }
}

class PaymentSubmissionRepository {
  PaymentSubmissionRepository({
    SupabaseClient? supabase,
    this.requestTimeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(seconds: 45),
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  final Duration requestTimeout;
  final Duration uploadTimeout;

  Future<models.Transaction?> getTransaction(int transactionId) async {
    final data = await _supabase
        .from('transactions')
        .select()
        .eq('id', transactionId)
        .isFilter('deleted_at', null)
        .maybeSingle()
        .timeout(requestTimeout);
    return data == null ? null : models.Transaction.fromJson(data);
  }

  Future<GcashPaymentDetails> getGcashDetails() async {
    final data = await _supabase
        .from('customer_payment_settings')
        .select()
        .eq('id', 1)
        .maybeSingle()
        .timeout(requestTimeout);
    if (data == null) {
      throw const PaymentFlowException(
        'GCash is not available yet. You can choose Pay at the shop.',
      );
    }
    return GcashPaymentDetails.fromJson(data);
  }

  Future<PaymentSubmission?> latestSubmission(int transactionId) async {
    final data = await _supabase
        .from('customer_payment_submissions')
        .select()
        .eq('transaction_id', transactionId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle()
        .timeout(requestTimeout);
    return data == null ? null : PaymentSubmission.fromJson(data);
  }

  Future<PaymentSubmission> choosePayAtShop(int transactionId) =>
      _submit(transactionId, method: 'shop');

  Future<PaymentSubmission> submitGcash(
    int transactionId,
    ReceiptImage receipt,
  ) async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) {
      throw const PaymentFlowException(
        'Sign in again before submitting a payment.',
      );
    }
    final path =
        '$authId/$transactionId/${receipt.requestId}.${receipt.extension}';
    try {
      await _supabase.storage
          .from('payment-receipts')
          .uploadBinary(
            path,
            receipt.bytes,
            fileOptions: FileOptions(
              contentType: receipt.contentType!,
              upsert: false,
            ),
          )
          .timeout(uploadTimeout);
    } on StorageException catch (error) {
      // A retry after a lost response uses the same immutable object and RPC ID.
      final duplicate =
          error.statusCode == '409' ||
          (error.statusCode == '400' &&
              (error.error == 'Duplicate' ||
                  error.error == 'KeyAlreadyExists' ||
                  error.message.toLowerCase().contains('already exists')));
      if (!duplicate) rethrow;
    }
    return _submit(
      transactionId,
      method: 'gcash',
      receiptPath: path,
      requestId: receipt.requestId,
    );
  }

  Future<PaymentSubmission> _submit(
    int transactionId, {
    required String method,
    String? receiptPath,
    String? requestId,
  }) async {
    final data = await _supabase
        .rpc(
          'submit_customer_payment',
          params: {
            'p_transaction_id': transactionId,
            'p_method': method,
            'p_receipt_path': receiptPath,
            'p_request_id': requestId,
          },
        )
        .timeout(requestTimeout);
    return PaymentSubmission.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
