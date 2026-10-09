import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_101repairshop/core/utils/appointment_reminder_time.dart';

void main() {
  final date = DateTime(2026, 10, 11);
  for (final slot in <String?>[
    null,
    '',
    'bad slot',
    '13:00 AM',
    '0:30 PM',
    '9:60 AM',
    'junk 8:00 AM',
    '8:00 AM junk',
  ]) {
    test('invalid slot does not silently become 8 AM: $slot', () {
      expect(AppointmentReminderTime.appointmentStart(date, slot), isNull);
    });
  }
  for (final (slot, hour) in [
    ('12:00 AM', 0),
    ('12:00 PM', 12),
    ('8:00 AM - 9:00 AM', 8),
    ('1:30 PM – 2:30 PM', 13),
    (' 4:05 pm — 5:05 pm ', 16),
  ]) {
    test('parses $slot in Manila time', () {
      final start = AppointmentReminderTime.appointmentStart(date, slot)!;
      expect(start.hour, hour);
      expect(start.timeZoneOffset, const Duration(hours: 8));
      expect(start.day, 11);
    });
  }
  test('one-day leadtime crosses the calendar boundary in Manila', () {
    final time = AppointmentReminderTime.reminderTime(date, '8:00 AM', 1440)!;
    expect(time.toUtc(), DateTime.utc(2026, 10, 10));
    expect(time.day, 10);
  });
  test('five-minute reminder preserves the minute and timezone', () {
    expect(
      AppointmentReminderTime.reminderTime(date, '1:30 PM', 5)!.toUtc(),
      DateTime.utc(2026, 10, 11, 5, 25),
    );
  });
  for (final offset in [-1, 0, 10081]) {
    test('rejects invalid leadtime $offset', () {
      expect(
        AppointmentReminderTime.reminderTime(date, '8:00 AM', offset),
        isNull,
      );
    });
  }
}
