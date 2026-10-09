import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_101repairshop/core/validation/phone_country_number.dart';
import 'package:flutter_101repairshop/core/validation/phone_number.dart';

void main() {
  void expectNumber(
    String input, {
    String selectedCountry = 'PH',
    required String e164,
    required String country,
    required String national,
  }) {
    final result = PhoneCountryNumber.resolve(
      input,
      countryCode: selectedCountry,
    );
    expect(result, isNotNull, reason: input);
    expect(result!.e164, e164, reason: input);
    expect(result.countryCode, country, reason: input);
    expect(result.nationalNumber, national, reason: input);
    expect(PhoneNumber.normalize(result.e164), result.e164, reason: input);
  }

  test('the default country adds +63 to every supported PH mobile format', () {
    for (final input in [
      '9123456789',
      '09123456789',
      '0912 345 6789',
      '639123456789',
      '+639123456789',
      ' +63 (912) 345-6789 ',
      '00639123456789',
    ]) {
      expectNumber(
        input,
        e164: '+639123456789',
        country: 'PH',
        national: '9123456789',
      );
    }
  });

  test('the selected country supplies the calling code for local inputs', () {
    expectNumber(
      '415 555 2671',
      selectedCountry: 'US',
      e164: '+14155552671',
      country: 'US',
      national: '4155552671',
    );
    expectNumber(
      '8123 4567',
      selectedCountry: 'SG',
      e164: '+6581234567',
      country: 'SG',
      national: '81234567',
    );
    expectNumber(
      '0412 345 678',
      selectedCountry: 'AU',
      e164: '+61412345678',
      country: 'AU',
      national: '412345678',
    );
  });

  test('national trunk prefixes follow the selected country rules', () {
    expectNumber(
      '07700 900123',
      selectedCountry: 'GB',
      e164: '+447700900123',
      country: 'GB',
      national: '7700900123',
    );
    expectNumber(
      '02 1234 5678',
      selectedCountry: 'IT',
      e164: '+390212345678',
      country: 'IT',
      national: '0212345678',
    );
  });

  test(
    'unallocated variable-length locals still remove their trunk prefix',
    () {
      expectNumber(
        '012345678901',
        selectedCountry: 'DE',
        e164: '+4912345678901',
        country: 'DE',
        national: '12345678901',
      );
      expectNumber(
        '0770090012',
        selectedCountry: 'GB',
        e164: '+44770090012',
        country: 'GB',
        national: '770090012',
      );
      expectNumber(
        '02079460018',
        selectedCountry: 'GB',
        e164: '+442079460018',
        country: 'GB',
        national: '2079460018',
      );
    },
  );

  test('carrier and mobile dialing prefixes use the country metadata', () {
    expectNumber(
      '02111961234567',
      selectedCountry: 'BR',
      e164: '+5511961234567',
      country: 'BR',
      national: '11961234567',
    );
    expectNumber(
      '0111523456789',
      selectedCountry: 'AR',
      e164: '+5491123456789',
      country: 'AR',
      national: '91123456789',
    );
    expectNumber(
      '0343155551212',
      selectedCountry: 'AR',
      e164: '+5493435551212',
      country: 'AR',
      national: '93435551212',
    );
  });

  test('pasted trunk prefixes normalize consistently with national entry', () {
    for (final input in [
      '+44 (0)7700 900123',
      '+44 0770090012',
      '+49 012345678901',
      '+39 02 1234 5678',
    ]) {
      final resolved = PhoneCountryNumber.resolve(input);
      expect(resolved, isNotNull, reason: input);
      final national = PhoneCountryNumber.resolve(
        resolved!.nationalNumber,
        countryCode: resolved.countryCode,
      );
      expect(national, isNotNull, reason: input);
      expect(national!.e164, resolved.e164, reason: input);
    }
    expectNumber(
      '+44 (0)7700 900123',
      e164: '+447700900123',
      country: 'GB',
      national: '7700900123',
    );
    expectNumber(
      '+49 012345678901',
      e164: '+4912345678901',
      country: 'DE',
      national: '12345678901',
    );
  });

  test('pasted international numbers override the selected country', () {
    expectNumber(
      '+1 (415) 555-2671',
      e164: '+14155552671',
      country: 'US',
      national: '4155552671',
    );
    expectNumber(
      '0044 7700 900123',
      e164: '+447700900123',
      country: 'GB',
      national: '7700900123',
    );
    expectNumber(
      '+63 912 345 6789',
      selectedCountry: 'GB',
      e164: '+639123456789',
      country: 'PH',
      national: '9123456789',
    );
    expectNumber(
      '+39 02 1234 5678',
      selectedCountry: 'US',
      e164: '+390212345678',
      country: 'IT',
      national: '0212345678',
    );
  });

  test(
    'an existing calling code is not repeated on supported local inputs',
    () {
      expectNumber(
        '14155552671',
        selectedCountry: 'US',
        e164: '+14155552671',
        country: 'US',
        national: '4155552671',
      );
      expectNumber(
        '447700900123',
        selectedCountry: 'GB',
        e164: '+447700900123',
        country: 'GB',
        national: '7700900123',
      );
    },
  );

  test('changing country preserves the entered national digits', () {
    final ph = PhoneCountryNumber.resolve('9123456789');
    final us = PhoneCountryNumber.resolve('9123456789', countryCode: 'US');
    expect(ph!.e164, '+639123456789');
    expect(us!.e164, '+19123456789');
    expect(ph.nationalNumber, us.nationalNumber);
    expect(us.countryCode, 'US');
  });

  test('ISO codes normalize case and surrounding whitespace', () {
    expectNumber(
      '9123456789',
      selectedCountry: ' ph ',
      e164: '+639123456789',
      country: 'PH',
      national: '9123456789',
    );
  });

  test('an unknown selected country does not guess a destination', () {
    for (final country in ['', 'ZZ', 'Philippines', '+63', 'P']) {
      expect(
        PhoneCountryNumber.resolve('9123456789', countryCode: country),
        isNull,
        reason: country,
      );
      expect(
        PhoneCountryNumber.resolve('+639123456789', countryCode: country),
        isNull,
        reason: country,
      );
    }
  });

  test('blank and malformed inputs never become a number from a prefix', () {
    for (final input in [
      '',
      ' ',
      '+',
      '()',
      '+63',
      '0063',
      '0912',
      '08123456789',
      '+6309123456789',
      '+63281234567',
      '+63912345678',
      '+001234567890',
      '++639123456789',
      '912+3456789',
      'call09123456789',
      '+63 912 345 6789 ext 1',
      '+639123456789/0',
      '+999123456789',
      '+1234567890123456',
    ]) {
      expect(PhoneCountryNumber.resolve(input), isNull, reason: input);
    }
    for (final input in [
      '',
      '+',
      '4155552671x1',
      '1234567',
      '123456789012345',
    ]) {
      expect(
        PhoneCountryNumber.resolve(input, countryCode: 'US'),
        isNull,
        reason: input,
      );
    }
  });

  test('E.164 format bounds do not add carrier allocation restrictions', () {
    expectNumber(
      '+492123456789012',
      e164: '+492123456789012',
      country: 'DE',
      national: '2123456789012',
    );
    expectNumber(
      '1111111111',
      selectedCountry: 'US',
      e164: '+11111111111',
      country: 'US',
      national: '1111111111',
    );
  });

  test('calling codes and supported countries use parser metadata', () {
    expect(PhoneCountryNumber.callingCodeFor('PH'), '+63');
    expect(PhoneCountryNumber.callingCodeFor('gb'), '+44');
    expect(PhoneCountryNumber.callingCodeFor('IT'), '+39');
    expect(PhoneCountryNumber.callingCodeFor('US'), '+1');
    expect(PhoneCountryNumber.callingCodeFor('CA'), '+1');
    expect(PhoneCountryNumber.supportsCountry('PH'), isTrue);
    expect(PhoneCountryNumber.supportsCountry('ZZ'), isFalse);
    expect(PhoneCountryNumber.callingCodeFor('+63'), isNull);
  });

  test('contact form normalization remains unchanged for foreign locals', () {
    expect(PhoneNumber.normalize('4155552671'), isNull);
    expect(PhoneNumber.normalize('07700900123'), isNull);
  });
}
