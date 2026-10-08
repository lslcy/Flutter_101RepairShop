import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_dates.dart';

// Customer appliance registered for repair
class Appliance {
  final int id;
  final String customerId;
  final String? brand;
  final String? product;
  final String? modelNo;
  final String? serialNo;
  final DateTime? dateIn;
  final DateTime? warrantyEnd;
  final String? category;
  final String? status;
  final String? applianceSize;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Appliance({
    required this.id,
    required this.customerId,
    this.brand,
    this.product,
    this.modelNo,
    this.serialNo,
    this.dateIn,
    this.warrantyEnd,
    this.category,
    this.status,
    this.applianceSize,
    this.createdAt,
    this.updatedAt,
  });

  // Build from Supabase row
  factory Appliance.fromJson(Map<String, dynamic> json) {
    return Appliance(
      id: (json['id'] as num).toInt(),
      customerId: json['customer_id']?.toString() ?? '',
      brand: json['brand'] as String?,
      product: json['product'] as String?,
      modelNo: json['model_no'] as String?,
      serialNo: json['serial_no'] as String?,
      dateIn: AppDates.parseTimestamp(json['date_in']),
      warrantyEnd: AppDates.parseTimestamp(json['warranty_end']),
      category: json['category'] as String?,
      status: json['status'] as String?,
      applianceSize: json['appliance_size'] as String?,
      createdAt: AppDates.parseTimestamp(json['created_at']),
      updatedAt: AppDates.parseTimestamp(json['updated_at']),
    );
  }

  // Convert to Supabase row for insert
  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'brand': brand,
      'product': product,
      'model_no': modelNo,
      'serial_no': serialNo,
      'date_in': dateIn == null ? null : AppDates.toTimestampString(dateIn!),
      'warranty_end': warrantyEnd == null
          ? null
          : AppDates.toTimestampString(warrantyEnd!),
      'category': category,
      'status': status ?? defaultStatus,
      'appliance_size': normalizeSize(applianceSize),
    };
  }

  /// Status given to appliances the customer registers in the app.
  static const defaultStatus = 'Active';

  /// `appliance_size` must be Small, Medium, Large or null.
  static String? normalizeSize(String? value) {
    final size = value?.trim().toLowerCase() ?? '';
    for (final allowed in AppConstants.applianceSizes) {
      if (allowed.toLowerCase() == size) return allowed;
    }
    return null;
  }

  // Check if under warranty
  bool get isUnderWarranty {
    if (warrantyEnd == null) return false;
    return warrantyEnd!.isAfter(DateTime.now());
  }

  /// "Warranty active until …", "Expired" or "No warranty".
  String get warrantyLabel {
    if (warrantyEnd == null) return 'No warranty';
    if (isUnderWarranty) {
      return 'Warranty active until ${AppDates.format(warrantyEnd!, 'MMM d, y')}';
    }
    return 'Expired';
  }

  // Display name
  String get displayName => [brand, product]
      .map((part) => part?.trim() ?? '')
      .where((part) => part.isNotEmpty)
      .join(' ');

  /// Name shown in pickers; falls back to the category or ID.
  String get label {
    if (displayName.isNotEmpty) return displayName;
    final cat = category?.trim() ?? '';
    return cat.isNotEmpty ? cat : 'Appliance #$id';
  }

  /// Text stored in `appointments.appliance_name` when booking with this
  /// appliance, e.g. "Samsung Aircon (Model AR12, S/N 12345)". The table has
  /// no appliance FK, so model and serial are included for staff.
  String get bookingLabel {
    final details = <String>[
      if (modelNo?.trim().isNotEmpty ?? false) 'Model ${modelNo!.trim()}',
      if (serialNo?.trim().isNotEmpty ?? false) 'S/N ${serialNo!.trim()}',
    ];
    return details.isEmpty ? label : '$label (${details.join(', ')})';
  }
}
