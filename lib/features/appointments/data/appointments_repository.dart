import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/services/customer_account_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/utils/appointment_reminder_time.dart';
import '../../shared/models/appointment.dart';

// Provides the appointments repository
final appointmentsRepositoryProvider = Provider(
  (ref) => AppointmentsRepository(),
);

// Handles appointment booking data
class AppointmentsRepository {
  AppointmentsRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client,
      _accounts = CustomerAccountService(
        supabase: supabase ?? Supabase.instance.client,
      );

  final SupabaseClient _supabase;
  final CustomerAccountService _accounts;

  // Get all appointments for current customer
  Future<List<Appointment>> getAppointments() async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) return [];

    final data = await _supabase
        .from('appointments')
        .select()
        .eq('customer_id', customerId)
        .order('appointment_date', ascending: false);

    return data.map(Appointment.fromJson).toList();
  }

  // Resolve the current stored address before every booking, including legacy profiles.
  Future<int?> bookAppointment(Map<String, dynamic> appointmentData) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Please sign in again to book an appointment.');
    }

    final date = AppDates.parseDate(appointmentData['appointment_date']);
    if (date != null && date.isBefore(AppDates.manilaToday())) {
      throw StateError('Choose today or a later date for your appointment.');
    }

    final minutes = appointmentData['reminder_minutes'];
    if (minutes != null) {
      if (minutes is! int || minutes < 1 || minutes > 10080 || date == null) {
        throw StateError('Choose a valid reminder and appointment date.');
      }
      final deadline = AppointmentReminderTime.reminderTime(
        date,
        appointmentData['time_slot'] as String?,
        minutes,
      );
      if (deadline == null || !deadline.isAfter(DateTime.now())) {
        throw StateError(
          'Choose a shorter reminder or a later appointment time.',
        );
      }
    }
    // The profile is linked (or created) when the customer signs in and when
    // the booking screen loads it; only an active, linked row may book.
    final customer = await _accounts.findActiveCustomer(
      userId,
      columns: 'id,address',
    );

    if (customer == null) {
      throw StateError(
        'Your customer profile could not be found. Please sign in again before booking.',
      );
    }

    final address = customer['address'] as String?;
    if (address == null || address.trim().isEmpty) {
      throw AppointmentAddressRequiredException();
    }

    final row = <String, dynamic>{};
    appointmentData.forEach((key, value) {
      // Store blank optional fields as null for the web admin.
      row[key] = value is String && value.trim().isEmpty ? null : value;
    });

    final result = await _supabase
        .from('appointments')
        .insert({
          ...row,
          // Staff confirm, complete or cancel bookings from the web admin.
          'status': AppointmentStatus.pending,
          'customer_id': customer['id'],
        })
        .select('id');

    if (result.isNotEmpty) {
      return (result.first['id'] as num).toInt();
    }
    return null;
  }

  // Cancel an appointment (only while it is Pending or Confirmed)
  Future<void> cancelAppointment(int id) async {
    final customerId = await _accounts.currentCustomerId();
    if (customerId == null) {
      throw StateError('Please sign in again to cancel this appointment.');
    }
    final updated = await _supabase
        .from('appointments')
        .update({'status': AppointmentStatus.cancelled})
        .eq('id', id)
        .eq('customer_id', customerId)
        .inFilter('status', const [
          AppointmentStatus.pending,
          AppointmentStatus.confirmed,
          'pending',
          'confirmed',
        ])
        .select('id');
    if (updated.isEmpty) {
      throw AppointmentNotCancellableException();
    }
    // Cancel any scheduled local notification for this appointment.
    await NotificationService.instance.cancelReminder(id);
  }
}

class AppointmentAddressRequiredException extends StateError {
  AppointmentAddressRequiredException()
    : super('Add an address to your profile before booking an appointment.');
}

class AppointmentNotCancellableException extends StateError {
  AppointmentNotCancellableException()
    : super(
        'This appointment can no longer be cancelled. Refresh to see its latest status.',
      );
}
