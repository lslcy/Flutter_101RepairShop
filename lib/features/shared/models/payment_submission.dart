import 'dart:math';
import 'dart:typed_data';

class PaymentSubmission {
  const PaymentSubmission({
    required this.id,
    required this.transactionId,
    required this.method,
    required this.status,
    required this.amount,
    this.receiptPath,
    this.reviewNote,
  });

  final String id;
  final int transactionId;
  final String method;
  final String status;
  final double amount;
  final String? receiptPath;
  final String? reviewNote;

  bool get isPending => status == 'pending';
  bool get isPayAtShop => status == 'pay_at_shop';
  bool get isRejected => status == 'rejected';

  factory PaymentSubmission.fromJson(Map<String, dynamic> json) =>
      PaymentSubmission(
        id: json['id'].toString(),
        transactionId: (json['transaction_id'] as num).toInt(),
        method: json['method'] as String,
        status: json['status'] as String,
        amount: (json['amount'] as num).toDouble(),
        receiptPath: json['receipt_path'] as String?,
        reviewNote: json['review_note'] as String?,
      );
}

class GcashPaymentDetails {
  const GcashPaymentDetails({
    required this.qrImageUrl,
    required this.recipient,
  });

  final String qrImageUrl;
  final String recipient;

  factory GcashPaymentDetails.fromJson(Map<String, dynamic> json) {
    final image = (json['gcash_qr_image_url'] as String?)?.trim() ?? '';
    final recipient = (json['gcash_recipient_name'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(image);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        recipient.isEmpty) {
      throw const PaymentFlowException(
        'GCash is not available yet. You can choose Pay at the shop.',
      );
    }
    return GcashPaymentDetails(qrImageUrl: image, recipient: recipient);
  }
}

class PaymentFlowException implements Exception {
  const PaymentFlowException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The original screenshot stays unchanged so its reference remains readable.
class ReceiptImage {
  ReceiptImage({required Uint8List bytes, String? requestId})
    : bytes = Uint8List.fromList(bytes),
      requestId = requestId ?? _uuid() {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const PaymentFlowException(
        'Choose a receipt image smaller than 5 MB.',
      );
    }
    if (contentType == null) {
      throw const PaymentFlowException(
        'Choose a JPG, PNG, or WebP receipt image.',
      );
    }
  }

  static const maxBytes = 5 * 1024 * 1024;
  final Uint8List bytes;
  final String requestId;

  String? get contentType {
    if (_startsWith([0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (_startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        _startsWith([0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  String get extension => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw const PaymentFlowException('Choose a supported receipt image.'),
  };

  bool _startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
