import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/validation/password_policy.dart';

final authFlowProvider = ChangeNotifierProvider<AuthFlowController>((ref) {
  return AuthFlowController(Supabase.instance.client);
});

enum PasswordRecoveryStage { idle, ready, invalid, complete }

/// Keeps recovery links on the password form instead of redirecting to Home.
/// Supabase replays its latest auth event, including links opened at startup.
class AuthFlowController extends ChangeNotifier {
  AuthFlowController(this.client) {
    _subscription = client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError: _onAuthError,
    );
  }

  final SupabaseClient client;
  late final StreamSubscription<AuthState> _subscription;
  PasswordRecoveryStage _stage = PasswordRecoveryStage.idle;
  String? _recoveryUserId;
  bool _disposed = false;
  bool _registering = false;

  bool get isRegistering => _registering;

  void beginRegistration() {
    _registering = true;
    notifyListeners();
  }

  void endRegistration() {
    _registering = false;
    if (!_disposed) notifyListeners();
  }

  PasswordRecoveryStage get stage => _stage;
  bool get isLoggedIn => client.auth.currentUser != null;
  bool get requiresRecovery => _stage != PasswordRecoveryStage.idle;
  bool get canResetPassword =>
      _stage == PasswordRecoveryStage.ready &&
      client.auth.currentSession != null &&
      client.auth.currentUser?.id == _recoveryUserId;

  void _onAuthState(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        _recoveryUserId = state.session?.user.id;
        _stage = state.session == null
            ? PasswordRecoveryStage.invalid
            : PasswordRecoveryStage.ready;
      case AuthChangeEvent.signedOut:
        if (_stage == PasswordRecoveryStage.ready) {
          _stage = PasswordRecoveryStage.invalid;
        }
      case AuthChangeEvent.signedIn:
        _stage = PasswordRecoveryStage.idle;
        _recoveryUserId = null;
      default:
        break;
    }
    if (!_disposed) notifyListeners();
  }

  void _onAuthError(Object error, StackTrace stackTrace) {
    // Connectivity/refresh errors must not send an ordinary user into recovery.
    if (error is AuthException &&
        (error is AuthPKCEGrantCodeExchangeError ||
            error.message ==
                'Code verifier could not be found in local storage.' ||
            const {
              'otp_expired',
              'flow_state_expired',
              'flow_state_not_found',
              'bad_code_verifier',
              'validation_failed',
              'access_denied',
            }.contains(error.code))) {
      _stage = PasswordRecoveryStage.invalid;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> updatePassword(String password) async {
    final validation = PasswordPolicy.validate(password);
    if (validation != null) throw ArgumentError(validation);
    if (!canResetPassword) {
      throw const AuthException(
        'Open a new password reset link to continue.',
        code: 'otp_expired',
      );
    }
    try {
      await client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      if (const {
        'otp_expired',
        'flow_state_expired',
        'flow_state_not_found',
        'session_not_found',
        'refresh_token_not_found',
        'refresh_token_already_used',
        'bad_jwt',
        'jwt_expired',
      }.contains(error.code)) {
        _stage = PasswordRecoveryStage.invalid;
        if (!_disposed) notifyListeners();
      }
      rethrow;
    }
    _stage = PasswordRecoveryStage.complete;
    if (!_disposed) notifyListeners();
  }

  /// The recovery link already signed the user in; continue after saving.
  void finishRecovery() {
    if (_stage != PasswordRecoveryStage.complete) return;
    _stage = PasswordRecoveryStage.idle;
    _recoveryUserId = null;
    notifyListeners();
  }

  Future<void> abandonRecovery() async {
    if (_recoveryUserId != null &&
        client.auth.currentUser?.id == _recoveryUserId) {
      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Local sign-out clears the stored session before contacting the API.
        // A failed remote logout must not trap an already signed-out customer.
        if (client.auth.currentSession != null) rethrow;
      }
    }
    _recoveryUserId = null;
    _stage = PasswordRecoveryStage.idle;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

class AuthRedirects {
  static const mobilePasswordReset = 'com.repairshop101://auth/reset-password';

  static String passwordReset({Uri? webBase}) {
    if (!kIsWeb && webBase == null) return mobilePasswordReset;
    // Preserve deployments hosted below a subdirectory and Flutter hash routes.
    final base = webBase ?? Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
      fragment: '/reset-password',
    ).toString();
  }
}
