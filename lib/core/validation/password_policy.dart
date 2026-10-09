/// Shared requirements for newly created or reset passwords.
///
/// Passwords are checked as entered. Spaces are never trimmed before saving.
abstract final class PasswordPolicy {
  static const minimumLength = 8;
  static const minimumLengthMessage = 'Use at least 8 characters';
  static const specialCharacterMessage = 'Add at least 1 special character';
  static const uppercaseLetterMessage = 'Add at least 1 uppercase letter';
  static const numberMessage = 'Add at least 1 number';
  static const requirementsMessage =
      'Use at least 8 characters, 1 special character, 1 uppercase letter and 1 number.';

  static final _specialCharacter = RegExp(r'[\p{P}\p{S}]', unicode: true);
  static final _uppercaseLetter = RegExp(r'\p{Lu}', unicode: true);
  static final _number = RegExp(r'[0-9]');

  static bool hasMinimumLength(String password) =>
      password.runes.length >= minimumLength;

  /// Punctuation and symbols qualify; spaces and combining marks do not.
  static bool hasSpecialCharacter(String password) =>
      _specialCharacter.hasMatch(password);

  static bool hasUppercaseLetter(String password) =>
      _uppercaseLetter.hasMatch(password);

  static bool hasNumber(String password) => _number.hasMatch(password);

  static String? validate(String? password) {
    if (password == null || password.trim().isEmpty) {
      return 'Enter a password';
    }
    if (!hasMinimumLength(password)) return minimumLengthMessage;
    if (!hasSpecialCharacter(password)) return specialCharacterMessage;
    if (!hasUppercaseLetter(password)) return uppercaseLetterMessage;
    if (!hasNumber(password)) return numberMessage;
    return null;
  }
}
