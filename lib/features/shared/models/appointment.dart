import '../../../core/constants/statuses.dart';
import '../../../core/utils/app_dates.dart';

// Repair appointment booking
class Appointment {
  final int id;
  final String customerId;
  final String title;
  final String? applianceName;
  final DateTime appointmentDate;
  final String? timeSlot;
  final String? status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Appointment({
    required this.id,
    required this.customerId,
    required this.title,
    this.applianceName,
    required this.appointmentDate,
    this.timeSlot,
    this.status,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  // Build from Supabase row
  factory Appointment.fromJson(Map<String, dynamic> json) {
    final createdAt = AppDates.parseTimestamp(json['created_at']);
    return Appointment(
      id: (json['id'] as num).toInt(),
      customerId: json['customer_id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Repair appointment',
      applianceName: json['appliance_name'] as String?,
      appointmentDate:
          AppDates.parseTimestamp(json['appointment_date']) ??
          createdAt ??
          DateTime.now(),
      timeSlot: json['time_slot'] as String?,
      status: json['status'] as String?,
      notes: json['notes'] as String?,
      createdAt: createdAt,
      updatedAt: AppDates.parseTimestamp(json['updated_at']),
    );
  }

  // Convert to Supabase row for insert
  Map<String, dynamic> toJson() {
    return {
      'customer_id': customerId,
      'title': title,
      'appliance_name': applianceName,
      'appointment_date': AppDates.toTimestampString(appointmentDate),
      'time_slot': timeSlot,
      'status': status ?? AppointmentStatus.pending,
      'notes': notes,
    };
  }

  /// `Pending`, `Confirmed`, `Completed` or `Cancelled` as stored by staff.
  String get statusLabel => AppointmentStatus.normalize(status);

  /// Still `Pending` although the booked day (Manila) has already passed.
  bool get isPastAwaitingStaff =>
      statusLabel == AppointmentStatus.pending &&
      AppDates.manilaDateOf(appointmentDate).isBefore(AppDates.manilaToday());

  /// Label for badges: [statusLabel], or "Past — awaiting staff".
  String get displayStatus => isPastAwaitingStaff
      ? AppointmentStatus.pastAwaitingStaff
      : statusLabel;

  bool get isConfirmed => statusLabel == AppointmentStatus.confirmed;

  bool get canCancel =>
      AppointmentStatus.canCancel(status) && !isPastAwaitingStaff;
}
