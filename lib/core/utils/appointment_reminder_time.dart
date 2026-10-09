import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Appointment slots and reminder deadlines in the shop's Philippine time.
abstract final class AppointmentReminderTime {
  static bool _timeZonesInitialized = false;

  static tz.Location get manila {
    if (!_timeZonesInitialized) {
      tz_data.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return tz.getLocation('Asia/Manila');
  }

  /// [calendarDate] contains the intended booking date, not a UTC timestamp.
  static tz.TZDateTime? appointmentStart(
    DateTime calendarDate,
    String? timeSlot,
  ) {
    if (timeSlot == null) return null;
    final start = timeSlot.split(RegExp(r'\s*[-–—]\s*')).first.trim();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(start);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour < 1 || hour > 12 || minute > 59) return null;
    if (match.group(3)!.toUpperCase() == 'PM' && hour != 12) hour += 12;
    if (match.group(3)!.toUpperCase() == 'AM' && hour == 12) hour = 0;
    return tz.TZDateTime(
      manila,
      calendarDate.year,
      calendarDate.month,
      calendarDate.day,
      hour,
      minute,
    );
  }

  static tz.TZDateTime? reminderTime(
    DateTime calendarDate,
    String? timeSlot,
    int reminderMinutes,
  ) {
    if (reminderMinutes < 1 || reminderMinutes > 10080) return null;
    return appointmentStart(
      calendarDate,
      timeSlot,
    )?.subtract(Duration(minutes: reminderMinutes));
  }
}
