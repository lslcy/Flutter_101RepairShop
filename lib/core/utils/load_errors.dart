import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/customer_account_service.dart';

/// Turns a load/save failure into a message a customer can act on.
///
/// * missing customer row -> "Your account is being set up…"
/// * no network / timeout -> connection hint (screens pair it with a retry)
/// * anything else        -> [fallback]
String friendlyError(Object error, {required String fallback}) {
  if (error is CustomerAccountMissingException) return error.message;
  if (error is PostgrestException) {
    if (error.code == '42501') {
      return 'Your account cannot access this information. Please contact the shop.';
    }
    if (const {'42703', '42P01', 'PGRST204', 'PGRST205'}.contains(error.code)) {
      return 'This information is temporarily unavailable. Please contact the shop.';
    }
    if (const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)) {
      return 'Your session could not be verified. Sign out and sign in again.';
    }
  }
  if (isConnectionError(error)) {
    return 'You appear to be offline or the connection is slow. '
        'Check your internet connection and try again.';
  }
  return fallback;
}

/// True for failures caused by no/slow network rather than by the server.
bool isConnectionError(Object error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is AuthRetryableFetchException) {
    final status = int.tryParse(error.statusCode ?? '');
    return status == null || status < 500;
  }
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('clientexception') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('network is unreachable') ||
      text.contains('xmlhttprequest error');
}

/// Safe diagnostic labels for device logs; excludes profile data and tokens.
String loadFailureDiagnostic(Object error) {
  if (error is PostgrestException) {
    return '${error.runtimeType} (code: ${error.code ?? 'unknown'})';
  }
  if (error is AuthException) {
    return '${error.runtimeType} (code: ${error.code ?? 'unknown'})';
  }
  return error.runtimeType.toString();
}
