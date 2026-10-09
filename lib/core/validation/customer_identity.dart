import 'phone_number.dart';

/// Shared validation for the identity saved at registration and profile edits.
/// Names are not an account identifier: different customers can share a name.
abstract final class CustomerIdentity {
  static const maxNameLength = 100;
  static final _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');
  static final _nameCharacters = RegExp(
    r"^(?:\p{L}\p{M}*|[ .'\u2018\u2019-])+$",
    unicode: true,
  );
  static final _letter = RegExp(r'\p{L}', unicode: true);

  static String normalizeName(String input) =>
      input.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateName(
    String? input, {
    required String fieldName,
    bool trailingPeriod = false,
  }) {
    final name = normalizeName(input ?? '');
    final end = trailingPeriod ? '.' : '';
    if (name.isEmpty) return 'Enter your $fieldName$end';
    if (name.runes.length > maxNameLength) {
      return 'Use $maxNameLength characters or fewer$end';
    }
    if (_controlCharacters.hasMatch(input!) ||
        !_nameCharacters.hasMatch(name) ||
        !_letter.hasMatch(name)) {
      return 'Use letters, spaces, apostrophes, hyphens or periods$end';
    }
    return null;
  }

  static String normalizeEmail(String input) => input.trim().toLowerCase();

  static String? validateEmail(String? input, {bool required = true}) {
    final email = normalizeEmail(input ?? '');
    if (email.isEmpty) return required ? 'Enter your email address' : null;
    final parts = email.split('@');
    if (email.length > 254 || parts.length != 2) {
      return 'Enter a valid email address';
    }
    final local = parts.first;
    final domain = parts.last;
    final localCharacters = RegExp(r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$");
    final domainLabel = RegExp(
      r'^[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?$',
      unicode: true,
    );
    final labels = domain.split('.');
    if (local.isEmpty ||
        local.length > 64 ||
        !localCharacters.hasMatch(local) ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..') ||
        labels.length < 2 ||
        labels.any(
          (label) => label.length > 63 || !domainLabel.hasMatch(label),
        )) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? normalizeOptionalPhone(String? input) =>
      input?.trim().isNotEmpty == true ? PhoneNumber.normalize(input!) : null;

  static String? validateOptionalPhone(String? input) =>
      input?.trim().isNotEmpty == true ? PhoneNumber.validate(input) : null;
}
