/// Formats supported mobile inputs without guessing an international country.
abstract final class PhoneNumber {
  static String? normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !RegExp(r'^[+0-9\s().-]+$').hasMatch(trimmed)) {
      return null;
    }
    var number = trimmed.replaceAll(RegExp(r'[\s().-]'), '');
    if (number.startsWith('00')) number = '+${number.substring(2)}';
    if (RegExp(r'^09\d{9}$').hasMatch(number)) {
      number = '+63${number.substring(1)}';
    } else if (RegExp(r'^9\d{9}$').hasMatch(number)) {
      number = '+63$number';
    } else if (RegExp(r'^639\d{9}$').hasMatch(number)) {
      number = '+$number';
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number)) return null;
    // Philippine local numbers are entered as mobile numbers for SMS delivery.
    if (number.startsWith('+63') && !RegExp(r'^\+639\d{9}$').hasMatch(number)) {
      return null;
    }
    return number;
  }

  static String? validate(String? input) {
    if (input == null || input.trim().isEmpty) return 'Enter your phone number';
    if (normalize(input) == null) {
      return 'Enter a valid phone number';
    }
    return null;
  }
}
