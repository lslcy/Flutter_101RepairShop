import '../../../core/utils/app_dates.dart';

// Repair service report
class ServiceReport {
  final int id;
  final String customerId;
  final String? customerName;
  final int? applianceId;
  final DateTime? dateIn;
  final String? status;
  final String? dealer;
  final DateTime? dop;
  final DateTime? datePulledOut;
  final String? findings;
  final String? remarks;
  final List<dynamic>? attachments;
  final Map<String, dynamic>? location;
  final String? usedParts;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ServiceReport({
    required this.id,
    required this.customerId,
    this.customerName,
    this.applianceId,
    this.dateIn,
    this.status,
    this.dealer,
    this.dop,
    this.datePulledOut,
    this.findings,
    this.remarks,
    this.attachments,
    this.location,
    this.usedParts,
    this.createdAt,
    this.updatedAt,
  });

  // Build from Supabase row
  factory ServiceReport.fromJson(Map<String, dynamic> json) {
    final attachments = json['attachments'];
    final location = json['location'];
    final usedParts = json['used_parts'];
    return ServiceReport(
      id: (json['id'] as num).toInt(),
      customerId: json['customer_id']?.toString() ?? '',
      customerName: json['customer_name'] as String?,
      applianceId: (json['appliance_id'] as num?)?.toInt(),
      dateIn: AppDates.parseTimestamp(json['date_in']),
      status: json['status'] as String?,
      dealer: json['dealer'] as String?,
      dop: AppDates.parseTimestamp(json['dop']),
      datePulledOut: AppDates.parseTimestamp(json['date_pulled_out']),
      findings: json['findings'] as String?,
      remarks: json['remarks'] as String?,
      attachments: attachments is List ? attachments : null,
      location: location is Map ? Map<String, dynamic>.from(location) : null,
      usedParts: usedParts?.toString(),
      createdAt: AppDates.parseTimestamp(json['created_at']),
      updatedAt: AppDates.parseTimestamp(json['updated_at']),
    );
  }
}
