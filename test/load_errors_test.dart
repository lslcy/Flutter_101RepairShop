import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/services/customer_account_service.dart';
import 'package:flutter_101repairshop/core/utils/load_errors.dart';

void main() {
  const fallback = 'Please try again in a moment.';

  test('Missing customer accounts preserve the account setup guidance', () {
    final error = CustomerAccountMissingException();

    expect(
      friendlyError(error, fallback: fallback),
      CustomerAccountMissingException.text,
    );
    expect(isConnectionError(error), isFalse);
  });

  test('Database permission errors explain account access', () {
    const error = PostgrestException(
      message: 'permission denied for table appointments',
      code: '42501',
    );

    expect(
      friendlyError(error, fallback: fallback),
      'Your account cannot access this information. Please contact the shop.',
    );
    expect(isConnectionError(error), isFalse);
  });

  test(
    'Missing database columns are unavailable information, not connectivity',
    () {
      const error = PostgrestException(
        message: 'column appointments.date does not exist',
        code: '42703',
      );

      expect(
        friendlyError(error, fallback: fallback),
        'This information is temporarily unavailable. Please contact the shop.',
      );
      expect(isConnectionError(error), isFalse);
    },
  );

  test('Unverified database sessions explain how to sign in again', () {
    const error = PostgrestException(message: 'JWT expired', code: 'PGRST301');

    expect(
      friendlyError(error, fallback: fallback),
      'Your session could not be verified. Sign out and sign in again.',
    );
    expect(isConnectionError(error), isFalse);
  });

  test('Timeouts provide the connection recovery guidance', () {
    final error = TimeoutException('Dashboard request timed out');

    expect(isConnectionError(error), isTrue);
    expect(
      friendlyError(error, fallback: fallback),
      'You appear to be offline or the connection is slow. '
      'Check your internet connection and try again.',
    );
  });

  test('Authentication server outages use the screen fallback', () {
    final error = AuthRetryableFetchException(
      message: 'Service temporarily unavailable',
      statusCode: '503',
    );

    expect(isConnectionError(error), isFalse);
    expect(friendlyError(error, fallback: fallback), fallback);
  });
}
