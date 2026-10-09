import 'package:phone_numbers_parser/metadata.dart' as metadata;
import 'package:phone_numbers_parser/phone_numbers_parser.dart' as parser;

import 'phone_number.dart';

/// A country-aware phone input in the form needed for SMS authentication.
final class ResolvedPhoneNumber {
  const ResolvedPhoneNumber({
    required this.e164,
    required this.countryCode,
    required this.nationalNumber,
  });

  final String e164;

  /// The uppercase ISO country code, such as PH or GB.
  final String countryCode;

  /// The international number without its country calling code.
  final String nationalNumber;
}

/// Adds the chosen country's calling code without changing contact form rules.
abstract final class PhoneCountryNumber {
  static final _allowedCharacters = RegExp(r'^[+0-9\s().-]+$');
  static final _formatting = RegExp(r'[\s().-]');
  static final _digitsWithOptionalPlus = RegExp(r'^\+?[0-9]+$');

  static String? callingCodeFor(String countryCode) {
    final country = _countryFor(countryCode);
    if (country == null) return null;
    try {
      return '+${parser.PhoneNumber(isoCode: country, nsn: '').countryCode}';
    } on parser.PhoneNumberException {
      return null;
    }
  }

  static bool supportsCountry(String countryCode) =>
      callingCodeFor(countryCode) != null;

  static ResolvedPhoneNumber? resolve(
    String input, {
    String countryCode = 'PH',
  }) {
    final selectedCountry = _countryFor(countryCode);
    if (selectedCountry == null) return null;

    final trimmed = input.trim();
    if (!_allowedCharacters.hasMatch(trimmed)) return null;
    final number = trimmed.replaceAll(_formatting, '');
    if (!_digitsWithOptionalPlus.hasMatch(number)) return null;

    try {
      // A pasted international number carries its own country information.
      // Validate it before parsing so malformed PH prefixes are not repaired.
      if (number.startsWith('+') || number.startsWith('00')) {
        final canonical = PhoneNumber.normalize(number);
        return canonical == null ? null : _fromInternational(canonical);
      }

      // Keep all established PH mobile formats, including a bare 639 prefix.
      if (selectedCountry == parser.IsoCode.PH) {
        final canonical = PhoneNumber.normalize(number);
        return canonical == null ? null : _fromInternational(canonical);
      }

      final parsed = _fromNational(number, selectedCountry);
      if (parsed == null) return null;
      final canonical = PhoneNumber.normalize(parsed.international);
      if (canonical == null) return null;
      return ResolvedPhoneNumber(
        e164: canonical,
        countryCode: parsed.isoCode.name,
        nationalNumber: parsed.nsn,
      );
    } on parser.PhoneNumberException {
      return null;
    }
  }

  static parser.PhoneNumber? _fromNational(
    String number,
    parser.IsoCode country,
  ) {
    final parsed = parser.PhoneNumber.parse(
      number,
      destinationCountry: country,
    );
    final fromRaw = _normalizeNationalPrefix(
      parser.PhoneNumber(isoCode: country, nsn: number),
    );
    // Parsing restores raw digits when a carrier allocation pattern fails.
    // A national prefix still needs removing for countries with variable lengths.
    if (parsed.nsn == number && fromRaw.nsn != number) return fromRaw;
    if (parsed.isValidLength()) return parsed;
    if (fromRaw.nsn != number) return fromRaw;

    // Remove an already entered calling code only when the national input is
    // otherwise too long, avoiding ambiguity with a valid national area code.
    final callingCode = metadata.metadataByIsoCode[country]?.countryCode;
    if (callingCode != null && number.startsWith(callingCode)) {
      final withoutCallingCode = _normalizeNationalPrefix(
        parser.PhoneNumber(
          isoCode: country,
          nsn: number.substring(callingCode.length),
        ),
      );
      if (withoutCallingCode.isValidLength()) return withoutCallingCode;
    }
    return null;
  }

  static parser.PhoneNumber _normalizeNationalPrefix(
    parser.PhoneNumber number,
  ) {
    final countryMetadata = metadata.metadataByIsoCode[number.isoCode];
    final patterns = metadata.metadataPatternsByIsoCode[number.isoCode];
    final pattern = patterns?.nationalPrefixForParsing;
    var national = number.nsn;
    if (pattern != null) {
      final match = RegExp(pattern).matchAsPrefix(national);
      if (match == null) return number;
      final rule = patterns?.nationalPrefixTransformRule;
      if (rule == null || match.groupCount == 0 || match.group(1) == null) {
        national = national.substring(match.end);
      } else {
        var transformed = rule;
        // Apply capture substitutions from highest to lowest to preserve $10.
        for (var group = match.groupCount; group >= 1; group--) {
          final value = match.group(group);
          if (value != null) {
            transformed = transformed.replaceAll('\$$group', value);
          }
        }
        national = transformed + national.substring(match.end);
      }
    } else {
      final prefix = countryMetadata?.nationalPrefix;
      if (prefix == null || !national.startsWith(prefix)) return number;
      national = national.substring(prefix.length);
    }
    final normalized = parser.PhoneNumber(
      isoCode: number.isoCode,
      nsn: national,
    );
    return normalized.isValidLength() ? normalized : number;
  }

  static parser.IsoCode? _countryFor(String countryCode) {
    final selectedCode = countryCode.trim().toUpperCase();
    for (final candidate in parser.IsoCode.values) {
      if (candidate.name == selectedCode) return candidate;
    }
    return null;
  }

  static ResolvedPhoneNumber? _fromInternational(String canonical) {
    final parsed = parser.PhoneNumber.parse(canonical);
    final national = canonical.substring(1 + parsed.countryCode.length);
    final normalized = _normalizeNationalPrefix(
      parser.PhoneNumber(isoCode: parsed.isoCode, nsn: national),
    );
    if (!normalized.isValidLength()) return null;
    final e164 = PhoneNumber.normalize(normalized.international);
    if (e164 == null) return null;
    return ResolvedPhoneNumber(
      e164: e164,
      countryCode: normalized.isoCode.name,
      nationalNumber: normalized.nsn,
    );
  }
}
