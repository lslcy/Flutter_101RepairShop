import 'package:supabase_flutter/supabase_flutter.dart';

import 'load_errors.dart';

/// Account errors never expose database identifiers or another customer's data.
String friendlyAccountError(
  Object error, {
  String fallback = 'We could not save your account. Please try again.',
}) {
  if (error is ArgumentError && error.message is String) {
    return error.message as String;
  }
  if (error is PostgrestException) {
    final diagnostic = '${error.message} ${error.details} ${error.hint}'
        .toLowerCase();
    if (error.code == '23505') {
      if (diagnostic.contains('phone')) {
        return 'This phone number is already linked to an account. Sign in to that account or contact the shop.';
      }
      if (diagnostic.contains('email')) {
        return 'This email is already linked to an account. Sign in or reset your password.';
      }
      return 'Your account already has a customer profile. Sign in to your existing account or contact the shop.';
    }
    if (error.code == '23514') {
      if (diagnostic.contains('name')) {
        return 'Enter a valid first and last name using letters, spaces, apostrophes, hyphens or periods.';
      }
      if (diagnostic.contains('phone')) {
        return 'Enter a valid phone number.';
      }
      if (diagnostic.contains('email')) {
        return 'Enter a valid email address.';
      }
    }
  }
  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (const {
          'account_already_exists',
          'email_exists',
          'user_already_exists',
          'identity_already_exists',
        }.contains(error.code) ||
        message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with this email already exists. Sign in or reset your password.';
    }
    if (error.code == 'phone_exists' ||
        message.contains(
          'this phone number is already associated with a customer account.',
        )) {
      return 'This phone number is already linked to an account. Sign in to that account or contact the shop.';
    }
    if (message.contains(
      'this email is already associated with a customer account.',
    )) {
      return 'This email is already linked to an account. Sign in or reset your password.';
    }
    if (error.code == 'already_signed_in') {
      return 'You are already signed in. Use your existing account.';
    }
    if (error.code == 'unexpected_failure' ||
        message.contains('database error saving new user')) {
      return 'Your account could not be created. Use your existing account or contact the shop.';
    }
  }
  return friendlyError(error, fallback: fallback);
}
