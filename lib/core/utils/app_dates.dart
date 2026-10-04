import 'package:intl/intl.dart';

// Date helpers shared by every screen.
//
// Database timestamps are `timestamptz`; they are parsed with `.toLocal()` and
// always *displayed* in shop time (Asia/Manila, UTC+8, no daylight saving) so
// customers and staff see the same dates regardless of the device timezone.
// `payment_date` and `payment_due` are plain `yyyy-MM-dd` dates and are never
// shifted between timezones.
class AppDates {
  AppDates._();

  static const manilaOffset = Duration(hours: 8);
  static final _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _isoDate = DateFormat('yyyy-MM-dd');

  /// Parses a `timestamptz` value and returns it in device-local time.
  /// Date-only strings are treated as Manila calendar dates.
  static DateTime? parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    if (_dateOnly.hasMatch(text)) {
      final date = DateTime.tryParse(text);
      if (date == null) return null;
      return DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).subtract(manilaOffset).toLocal();
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  /// Parses a plain `yyyy-MM-dd` date (time and timezone are ignored).
  static DateTime? parseDate(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.length < 10) return null;
    final date = DateTime.tryParse(text.substring(0, 10));
    return date == null ? null : DateTime(date.year, date.month, date.day);
  }

  /// The same instant expressed as Manila wall-clock time. The result is a
  /// UTC [DateTime] whose fields read as Manila time, ready for [DateFormat].
  static DateTime toManila(DateTime value) => value.toUtc().add(manilaOffset);

  /// Formats a timestamp in Manila time, e.g. `format(dt, 'MMM d, y')`.
  static String format(DateTime value, String pattern) =>
      DateFormat(pattern).format(toManila(value));

  /// Formats a plain calendar date without any timezone conversion.
  static String formatDate(DateTime date, String pattern) =>
      DateFormat(pattern).format(date);

  /// Calendar date (midnight, local fields) of a timestamp in Manila.
  static DateTime manilaDateOf(DateTime value) {
    final manila = toManila(value);
    return DateTime(manila.year, manila.month, manila.day);
  }

  /// Today's calendar date in Manila.
  static DateTime manilaToday() => manilaDateOf(DateTime.now());

  /// `yyyy-MM-dd`, for `payment_date` / `payment_due` style columns.
  static String toDateString(DateTime date) => _isoDate.format(date);

  /// `yyyy-MM-dd` of the Manila calendar date for [value].
  static String toManilaDateString(DateTime value) =>
      _isoDate.format(manilaDateOf(value));

  /// ISO-8601 UTC timestamp for `timestamptz` columns such as `paid_at`.
  static String toTimestampString(DateTime value) =>
      value.toUtc().toIso8601String();
}
