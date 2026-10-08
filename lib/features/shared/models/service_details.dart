import 'dart:convert';

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

/// `service_details` row written by the Laravel admin (one per report; the
/// row is missing until a technician assesses the repair).
class ServiceDetails {
  final int reportId;
  final List<String> serviceTypes;
  final String? complaint;
  final double? labor;
  final double? partsTotalCharge;
  final double? pulloutDelivery;
  final double? miscellaneousCost;
  final double? totalAmount;
  final List<String> technicians;
  final DateTime? dateRepaired;
  final DateTime? dateDelivered;

  ServiceDetails({
    required this.reportId,
    this.serviceTypes = const [],
    this.complaint,
    this.labor,
    this.partsTotalCharge,
    this.pulloutDelivery,
    this.miscellaneousCost,
    this.totalAmount,
    this.technicians = const [],
    this.dateRepaired,
    this.dateDelivered,
  });

  factory ServiceDetails.fromJson(Map<String, dynamic> json) {
    return ServiceDetails(
      reportId: (json['report_id'] as num?)?.toInt() ?? 0,
      serviceTypes: _parseList(json['service_types']),
      complaint: _text(json['complaint']),
      labor: _toDouble(json['labor']),
      partsTotalCharge: _toDouble(json['parts_total_charge']),
      pulloutDelivery: _toDouble(json['pullout_delivery']),
      miscellaneousCost: _toDouble(json['miscellaneous_cost']),
      totalAmount: _toDouble(json['total_amount']),
      technicians: _splitNames(json['technician']),
      // `timestamp without time zone`, stored as UTC by Laravel.
      dateRepaired: AppDates.parseUtcTimestamp(json['date_repaired']),
      dateDelivered: AppDates.parseUtcTimestamp(json['date_delivered']),
    );
  }

  /// Sum of the cost lines when Laravel has not stored a total yet.
  double? get computedTotal {
    if (totalAmount != null) return totalAmount;
    final parts = [labor, partsTotalCharge, pulloutDelivery, miscellaneousCost]
        .whereType<double>();
    return parts.isEmpty ? null : parts.fold<double>(0, (a, b) => a + b);
  }

  // `service_types` is json: usually a list, sometimes a JSON-encoded string.
  static List<String> _parseList(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map(_text).whereType<String>().toList();
    }
    final text = value.toString().trim();
    if (text.isEmpty) return const [];
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) return _parseList(decoded);
      } on FormatException {
        // Fall through to comma splitting.
      }
    }
    return _splitNames(text);
  }

  static List<String> _splitNames(Object? value) {
    final text = value?.toString() ?? '';
    return text
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }
}

/// `service_progress_comments` row written by staff in the Laravel admin.
class ServiceProgressComment {
  final int? id;
  final int reportId;
  final String? progressKey;
  final String commentText;
  final String? createdByName;
  final DateTime? createdAt;

  ServiceProgressComment({
    this.id,
    required this.reportId,
    this.progressKey,
    required this.commentText,
    this.createdByName,
    this.createdAt,
  });

  factory ServiceProgressComment.fromJson(Map<String, dynamic> json) {
    return ServiceProgressComment(
      id: (json['id'] as num?)?.toInt(),
      reportId: (json['report_id'] as num?)?.toInt() ?? 0,
      progressKey: _text(json['progress_key']),
      commentText: _text(json['comment_text']) ?? '',
      createdByName: _text(json['created_by_name']),
      createdAt: AppDates.parseUtcTimestamp(json['created_at']),
    );
  }

  /// `waiting_for_parts` -> `Waiting for parts`.
  String? get progressLabel {
    final key = progressKey?.replaceAll(RegExp(r'[_-]+'), ' ').trim() ?? '';
    if (key.isEmpty) return null;
    return key[0].toUpperCase() + key.substring(1).toLowerCase();
  }
}

/// A part recorded against a report in `part_service_report` (pivot keyed
/// by `service_report_id`), with the name joined from `parts`.
class PartUsed {
  final int? id;
  final int? partId;
  final String name;
  final int quantity;

  /// Unit price at the time of repair.
  final double? price;
  final bool isNotWorking;
  final DateTime? createdAt;

  PartUsed({
    this.id,
    this.partId,
    required this.name,
    this.quantity = 1,
    this.price,
    this.isNotWorking = false,
    this.createdAt,
  });

  factory PartUsed.fromJson(Map<String, dynamic> json, {String? fallbackName}) {
    final part = json['parts'];
    final joinedName = part is Map ? _text(part['name']) : null;
    final partId = (json['part_id'] as num?)?.toInt();
    final isNotWorking = json['is_not_working'];
    return PartUsed(
      id: (json['id'] as num?)?.toInt(),
      partId: partId,
      name:
          joinedName ??
          fallbackName ??
          (partId == null ? 'Part' : 'Part #$partId'),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      price: _toDouble(json['price']),
      isNotWorking:
          isNotWorking == true ||
          isNotWorking == 1 ||
          isNotWorking?.toString().toLowerCase() == 'true',
      // `timestamp without time zone`, stored as UTC by Laravel.
      createdAt: AppDates.parseUtcTimestamp(json['created_at']),
    );
  }

  /// `price × quantity`, or `null` when no price was recorded.
  double? get lineTotal => price == null ? null : price! * quantity;
}
