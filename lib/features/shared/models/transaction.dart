import '../../../core/constants/statuses.dart';
import '../../../core/utils/app_dates.dart';

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim());
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

// Payment transaction for a repair
class Transaction {
  final int id;
  final int? reportId;
  final String customerId;
  final double? partsTotal;
  final double? laborTotal;
  final double? totalAmount;
  final String? paymentStatus;
  final String? paymentMethod;
  final DateTime? paidAt;

  /// Plain `yyyy-MM-dd` date kept in sync with [paidAt] by a DB trigger.
  final DateTime? paymentDate;

  /// Plain `yyyy-MM-dd` due date.
  final DateTime? paymentDue;
  final double? partialPaymentAmount;
  final String? referenceNo;

  /// PayMongo checkout link created by the web admin.
  final String? paymentUrl;
  final String? receivedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Transaction({
    required this.id,
    required this.customerId,
    this.reportId,
    this.partsTotal,
    this.laborTotal,
    this.totalAmount,
    this.paymentStatus,
    this.paymentMethod,
    this.paidAt,
    this.paymentDate,
    this.paymentDue,
    this.partialPaymentAmount,
    this.referenceNo,
    this.paymentUrl,
    this.receivedBy,
    this.createdAt,
    this.updatedAt,
  });

  // Build from Supabase row
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: (json['id'] as num).toInt(),
      customerId: json['customer_id']?.toString() ?? '',
      reportId: (json['report_id'] as num?)?.toInt(),
      partsTotal: _toDouble(json['parts_total']),
      laborTotal: _toDouble(json['labor_total']),
      totalAmount: _toDouble(json['total_amount']),
      paymentStatus: json['payment_status'] as String?,
      paymentMethod: _text(json['payment_method']),
      paidAt: AppDates.parseTimestamp(json['paid_at']),
      paymentDate: AppDates.parseDate(json['payment_date']),
      paymentDue: AppDates.parseDate(json['payment_due']),
      partialPaymentAmount: _toDouble(json['partial_payment_amount']),
      referenceNo: _text(json['reference_no']),
      paymentUrl: _text(json['payment_url']),
      receivedBy: _text(json['received_by']),
      createdAt: AppDates.parseTimestamp(json['created_at']),
      updatedAt: AppDates.parseTimestamp(json['updated_at']),
    );
  }

  /// `Paid`, `Unpaid` or `Partial` (legacy `Pending` reads as Unpaid).
  String get status => PaymentStatus.normalize(paymentStatus);

  bool get isPaid => status == PaymentStatus.paid;
  bool get isPartial => status == PaymentStatus.partial;

  /// Amount already received.
  double? get amountPaid {
    if (isPaid) return totalAmount;
    if (isPartial) return partialPaymentAmount;
    return null;
  }

  /// Outstanding amount, or `null` when the total is unknown.
  double? get remainingBalance {
    if (isPaid) return 0;
    final total = totalAmount;
    if (total == null) return null;
    final paid = isPartial ? (partialPaymentAmount ?? 0) : 0;
    final balance = total - paid;
    return balance < 0 ? 0 : balance;
  }

  /// Show "Pay online" only for an unpaid/partial bill with a checkout link.
  bool get canPayOnline {
    final url = paymentUrl ?? '';
    return !isPaid && url.toLowerCase().startsWith('http');
  }

  /// `paid_at ?? payment_date`, formatted for display. `payment_date` is a
  /// plain DATE, so it is shown without a time.
  String? get paidOnLabel {
    if (paidAt != null) return AppDates.format(paidAt!, 'MMM d, y');
    if (paymentDate != null) {
      return AppDates.formatDate(paymentDate!, 'MMM d, y');
    }
    return null;
  }

  /// Unpaid/partial bill whose `payment_due` is before today in Manila.
  bool get isOverdue =>
      !isPaid && paymentDue != null && AppDates.isPastManilaDate(paymentDue!);

  // Customers have SELECT-only access to `transactions` (RLS). Payments are
  // recorded by staff in the web admin or by PayMongo, so this model has no
  // insert/update payloads on purpose.
}
