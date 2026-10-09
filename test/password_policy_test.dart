import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_101repairshop/core/validation/password_policy.dart';

void main() {
  test('all four requirements must pass for a new password', () {
    expect(PasswordPolicy.validate('Abcde1!f'), isNull);
    expect(
      PasswordPolicy.validate('Ab1!abc'),
      PasswordPolicy.minimumLengthMessage,
    );
    expect(
      PasswordPolicy.validate('Abcdef12'),
      PasswordPolicy.specialCharacterMessage,
    );
    expect(
      PasswordPolicy.validate('abcdef1!'),
      PasswordPolicy.uppercaseLetterMessage,
    );
    expect(PasswordPolicy.validate('Abcdefg!'), PasswordPolicy.numberMessage);
  });

  test('each checklist requirement is independent', () {
    expect(PasswordPolicy.hasMinimumLength('abcdefgh'), isTrue);
    expect(PasswordPolicy.hasSpecialCharacter('!'), isTrue);
    expect(PasswordPolicy.hasUppercaseLetter('A'), isTrue);
    expect(PasswordPolicy.hasNumber('1'), isTrue);
    expect(PasswordPolicy.hasMinimumLength('Ab1!'), isFalse);
    expect(PasswordPolicy.hasSpecialCharacter('Ab123 '), isFalse);
    expect(PasswordPolicy.hasUppercaseLetter('ab1!'), isFalse);
    expect(PasswordPolicy.hasNumber('Ab!'), isFalse);
  });

  test('blank input is required and never passes a checklist requirement', () {
    for (final password in <String?>[null, '', '   ', '\t\n']) {
      expect(PasswordPolicy.validate(password), 'Enter a password');
    }
    expect(PasswordPolicy.hasMinimumLength(''), isFalse);
    expect(PasswordPolicy.hasSpecialCharacter(''), isFalse);
    expect(PasswordPolicy.hasUppercaseLetter(''), isFalse);
    expect(PasswordPolicy.hasNumber(''), isFalse);
  });

  test('length counts Unicode code points instead of UTF-16 units', () {
    const sevenCharacters = 'Ab1!ab😀';
    expect(sevenCharacters.length, 8);
    expect(sevenCharacters.runes.length, 7);
    expect(PasswordPolicy.hasMinimumLength(sevenCharacters), isFalse);
    expect(
      PasswordPolicy.validate(sevenCharacters),
      PasswordPolicy.minimumLengthMessage,
    );
    expect(PasswordPolicy.validate('${sevenCharacters}c'), isNull);
  });

  test('uppercase letters and special symbols support Unicode', () {
    expect(PasswordPolicy.validate('Ébcdef1€'), isNull);
    expect(PasswordPolicy.hasUppercaseLetter('é'), isFalse);
    expect(PasswordPolicy.hasSpecialCharacter('a\u0301'), isFalse);
    expect(PasswordPolicy.hasSpecialCharacter('\t\u00a0'), isFalse);
    expect(PasswordPolicy.hasNumber('١'), isFalse);
  });

  test('surrounding spaces remain part of a valid password', () {
    const password = ' Ab1!   ';
    expect(password.runes.length, PasswordPolicy.minimumLength);
    expect(PasswordPolicy.validate(password), isNull);
    expect(PasswordPolicy.validate(password.trim()), isNotNull);
  });
}
