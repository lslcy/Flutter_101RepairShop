import '../../../core/config/app_config.dart';
import '../../../core/utils/app_dates.dart';

// Customer profile linked to Supabase auth
class Customer {
  final String id;
  final String? authId;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phoneNo;
  final String? address;
  final String? profilePicture;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Customer({
    required this.id,
    this.authId,
    this.firstName,
    this.lastName,
    this.email,
    this.phoneNo,
    this.address,
    this.profilePicture,
    this.createdAt,
    this.updatedAt,
  });

  // Build from Supabase row
  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'].toString(),
      authId: json['auth_id'] as String?,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      email: json['email'] as String?,
      phoneNo: json['phone_no'] as String?,
      address: json['address'] as String?,
      profilePicture: json['profile_picture'] as String?,
      createdAt: AppDates.parseTimestamp(json['created_at']),
      updatedAt: AppDates.parseTimestamp(json['updated_at']),
    );
  }

  // Convert to Supabase row
  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_no': phoneNo,
      'address': address,
      'profile_picture': profilePicture,
    };
  }

  // Full name helper
  String get fullName {
    final first = firstName ?? '';
    final last = lastName ?? '';
    return '$first $last'.trim();
  }

  /// Loadable avatar URL. Supabase Storage URLs are used as-is; relative
  /// paths uploaded from the web admin are resolved against LARAVEL_BASE_URL.
  String? get profilePictureUrl => AppConfig.resolveMediaUrl(profilePicture);
}
