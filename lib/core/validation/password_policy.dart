/// Shared requirements for newly created or reset passwords.
abstract final class PasswordPolicy {
  static const minimumLength = 8;
  static const minimumLengthMessage = 'Use at least 8 characters';

  static String? validate(String? password) {
    if (password == null || password.trim().isEmpty) {
      return 'Enter a password';
    }
    if (password.length < minimumLength) return minimumLengthMessage;
    return null;
  }
}
