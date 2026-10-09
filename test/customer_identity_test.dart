import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_101repairshop/core/validation/customer_identity.dart';

void main() {
  group('Customer names', () {
    for (final name in [
      'José',
      'Muñoz',
      'Jose\u0301',
      '王小明',
      '김민준',
      'नमस्ते',
      'محمد',
      "O'Connor",
      'O’Connor',
      'Jean-Luc',
      'J. P.',
      'De la Cruz',
    ]) {
      test('accepts $name', () {
        expect(
          CustomerIdentity.validateName(name, fieldName: 'first name'),
          isNull,
        );
      });
    }

    test('rejects numbers, emoji, markup, controls and punctuation alone', () {
      for (final name in [
        'Alex123',
        'Reyes😀',
        '<Alex>',
        'Alex\nReyes',
        'Al\u0000ex',
        ' .--’ ',
        '\u0301Alex',
      ]) {
        expect(
          CustomerIdentity.validateName(name, fieldName: 'first name'),
          isNotNull,
          reason: name,
        );
      }
    });

    test('requires names and bounds Unicode codepoints', () {
      expect(
        CustomerIdentity.validateName(null, fieldName: 'first name'),
        'Enter your first name',
      );
      expect(
        CustomerIdentity.validateName(
          '   ',
          fieldName: 'last name',
          trailingPeriod: true,
        ),
        'Enter your last name.',
      );
      expect(
        CustomerIdentity.validateName('𐐀' * 100, fieldName: 'first name'),
        isNull,
      );
      expect(
        CustomerIdentity.validateName('𐐀' * 101, fieldName: 'first name'),
        'Use 100 characters or fewer',
      );
    });

    test('normalizes surrounding and repeated whitespace', () {
      expect(
        CustomerIdentity.normalizeName('  María   de la  Cruz  '),
        'María de la Cruz',
      );
      // The validator remains stateless: shared names do not prove one identity.
      for (var i = 0; i < 2; i++) {
        expect(
          CustomerIdentity.validateName('Alex Reyes', fieldName: 'first name'),
          isNull,
        );
      }
    });
  });

  group('Customer contacts', () {
    test('normalizes email case without changing dots or aliases', () {
      expect(
        CustomerIdentity.normalizeEmail('  A.Lex+Shop@GMAIL.COM  '),
        'a.lex+shop@gmail.com',
      );
      expect(CustomerIdentity.validateEmail(' A.Lex+Shop@GMAIL.COM '), isNull);
      expect(CustomerIdentity.validateEmail('alex@example.technology'), isNull);
      expect(
        CustomerIdentity.validateEmail('alex@xn--bcher-kva.example'),
        isNull,
      );
    });

    test('invalid and required emails are rejected', () {
      expect(CustomerIdentity.validateEmail(' '), 'Enter your email address');
      expect(CustomerIdentity.validateEmail('', required: false), isNull);
      for (final email in [
        'alex',
        'alex@example',
        'alex@@example.com',
        'alex@example..com',
        '.alex@example.com',
        'al..ex@example.com',
        'alex@-example.com',
        '<alex>@example.com',
        'alex name@example.com',
      ]) {
        expect(CustomerIdentity.validateEmail(email), isNotNull, reason: email);
      }
    });

    test('optional phone numbers must be valid when provided', () {
      expect(CustomerIdentity.validateOptionalPhone(' '), isNull);
      expect(CustomerIdentity.normalizeOptionalPhone(' '), isNull);
      expect(CustomerIdentity.validateOptionalPhone('0917 123 4567'), isNull);
      expect(
        CustomerIdentity.normalizeOptionalPhone('0917 123 4567'),
        '+639171234567',
      );
      expect(
        CustomerIdentity.normalizeOptionalPhone('+63 (917) 123-4567'),
        '+639171234567',
      );
      expect(
        CustomerIdentity.validateOptionalPhone('0917'),
        'Enter a valid phone number',
      );
      expect(
        CustomerIdentity.validateOptionalPhone('call me'),
        'Enter a valid phone number',
      );
    });
  });
}
