import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/account_errors.dart';
import '../../../core/utils/load_errors.dart';
import '../../../core/validation/password_policy.dart';
import '../../shared/models/customer.dart';
import 'sign_in_profile_service.dart';

final authFlowProvider = ChangeNotifierProvider<AuthFlowController>((ref) {
  return AuthFlowController(Supabase.instance.client);
});

enum PasswordRecoveryStage { idle, ready, invalid, complete }

enum SignInProfileStage { idle, checking, required, ready, failed }

/// Routes recovery links and required profile details before opening Home.
/// Supabase replays its latest auth event, including links opened at startup.
class AuthFlowController extends ChangeNotifier {
  AuthFlowController(this.client, {SignInProfileService? profiles})
    : profiles = profiles ?? SignInProfileService(client) {
    _subscription = client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError: _onAuthError,
    );
    _checkExternalProfile(client.auth.currentUser);
  }

  final SupabaseClient client;
  final SignInProfileService profiles;
  late final StreamSubscription<AuthState> _subscription;
  PasswordRecoveryStage _stage = PasswordRecoveryStage.idle;
  String? _recoveryUserId;
  bool _disposed = false;
  bool _registering = false;

  bool _googlePending = false;
  String? _googleError;
  SignInProfileStage _profileStage = SignInProfileStage.idle;
  Customer? _signInCustomer;
  String? _profileUserId;
  Object? _profileError;
  int _profileRequest = 0;

  bool get isGoogleSignInPending => _googlePending;
  String? get googleSignInError => _googleError;
  SignInProfileStage get profileStage => _profileStage;
  Customer? get signInCustomer => _signInCustomer;
  Object? get profileError => _profileError;
  bool get requiresSignInProfile =>
      isLoggedIn &&
      _profileStage != SignInProfileStage.idle &&
      _profileStage != SignInProfileStage.ready;

  void beginGoogleSignIn() {
    _googlePending = true;
    _googleError = null;
    AuthCallbackTracker.latest = AuthCallbackKind.signIn;
    notifyListeners();
  }

  void cancelGoogleSignIn() {
    _googlePending = false;
    _googleError = null;
    if (AuthCallbackTracker.latest == AuthCallbackKind.signIn) {
      AuthCallbackTracker.latest = null;
    }
    if (!_disposed) notifyListeners();
  }

  void _checkExternalProfile(User? user, {bool force = false}) {
    if (!SignInProfileService.isExternalUser(user)) {
      _profileRequest++;
      _profileUserId = null;
      _profileStage = SignInProfileStage.idle;
      _signInCustomer = null;
      _profileError = null;
      return;
    }
    if (!force && _profileUserId == user!.id) return;
    _profileUserId = user!.id;
    _profileStage = SignInProfileStage.checking;
    _profileError = null;
    final request = ++_profileRequest;
    unawaited(_loadSignInProfile(request, user.id));
  }

  Future<void> _loadSignInProfile(int request, String userId) async {
    try {
      final customer = await profiles.load().timeout(
        const Duration(seconds: 15),
      );
      if (_disposed ||
          request != _profileRequest ||
          client.auth.currentUser?.id != userId) {
        return;
      }
      _signInCustomer = customer;
      _profileStage = SignInProfileService.isComplete(customer)
          ? SignInProfileStage.ready
          : SignInProfileStage.required;
    } catch (error) {
      if (_disposed ||
          request != _profileRequest ||
          client.auth.currentUser?.id != userId) {
        return;
      }
      _profileError = error;
      _profileStage = SignInProfileStage.failed;
    }
    if (!_disposed) notifyListeners();
  }

  void retrySignInProfile() {
    _checkExternalProfile(client.auth.currentUser, force: true);
    if (!_disposed) notifyListeners();
  }

  Future<void> completeSignInProfile({
    required String firstName,
    required String lastName,
    required String address,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('Sign in again to continue.');
    final request = _profileRequest;
    await profiles.complete(
      firstName: firstName,
      lastName: lastName,
      address: address,
    );
    final customer = await profiles.load().timeout(const Duration(seconds: 15));
    if (_disposed ||
        request != _profileRequest ||
        client.auth.currentUser?.id != userId) {
      throw const AuthException('Your sign-in changed. Please try again.');
    }
    if (!SignInProfileService.isComplete(customer)) {
      throw StateError('Your details could not be saved. Please try again.');
    }
    _signInCustomer = customer;
    _profileStage = SignInProfileStage.ready;
    _profileError = null;
    notifyListeners();
  }

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
        _googlePending = false;
        _googleError = null;
        AuthCallbackTracker.latest = null;
        _recoveryUserId = state.session?.user.id;
        _stage = state.session == null
            ? PasswordRecoveryStage.invalid
            : PasswordRecoveryStage.ready;
      case AuthChangeEvent.signedOut:
        _googlePending = false;
        _googleError = null;
        AuthCallbackTracker.latest = null;
        if (_stage == PasswordRecoveryStage.ready) {
          _stage = PasswordRecoveryStage.invalid;
        }
      case AuthChangeEvent.signedIn:
        _googlePending = false;
        _googleError = null;
        AuthCallbackTracker.latest = null;
        _stage = PasswordRecoveryStage.idle;
        _recoveryUserId = null;
      default:
        break;
    }
    _checkExternalProfile(state.session?.user);
    if (!_disposed) notifyListeners();
  }

  void _onAuthError(Object error, StackTrace stackTrace) {
    // Browser OAuth and password recovery share an SDK error stream.
    // Remember the callback path even when the error arrives before startup.
    if (AuthCallbackTracker.latest == AuthCallbackKind.signIn ||
        (_googlePending &&
            AuthCallbackTracker.latest != AuthCallbackKind.recovery)) {
      _googlePending = false;
      const fallback = 'Google sign-in was not completed. Please try again.';
      _googleError = isConnectionError(error)
          ? fallback
          : friendlyAccountError(error, fallback: fallback);
      AuthCallbackTracker.latest = null;
      if (!_disposed) notifyListeners();
      return;
    }
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
      _googlePending = false;
      AuthCallbackTracker.latest = null;
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
  static const mobileSignIn = 'com.repairshop101://auth/login-callback';

  static String signIn({Uri? webBase}) {
    if (!kIsWeb && webBase == null) return mobileSignIn;
    final base = webBase ?? Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
      queryParameters: const {'auth_callback': 'sign_in'},
      fragment: '/login-callback',
    ).toString();
  }

  static String passwordReset({Uri? webBase}) {
    if (!kIsWeb && webBase == null) return mobilePasswordReset;
    // Preserve deployments hosted below a subdirectory and Flutter hash routes.
    final base = webBase ?? Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: base.path,
      queryParameters: const {'auth_callback': 'recovery'},
      fragment: '/reset-password',
    ).toString();
  }
}

enum AuthCallbackKind { recovery, signIn }

/// Captures callback origin without retaining tokens or URLs.
class AuthCallbackTracker {
  static AuthCallbackKind? latest;

  static bool detect(Uri uri) {
    final native = uri.scheme == 'com.repairshop101' && uri.host == 'auth';
    final web = uri.scheme == 'http' || uri.scheme == 'https';
    if (!native && !web) return false;
    final marker = uri.queryParameters['auth_callback'];
    final route = native
        ? uri.path
        : marker == 'sign_in'
        ? '/login-callback'
        : marker == 'recovery'
        ? '/reset-password'
        : uri.fragment.split('?').first;
    final kind = route == '/login-callback'
        ? AuthCallbackKind.signIn
        : route == '/reset-password'
        ? AuthCallbackKind.recovery
        : null;
    if (kind == null) return false;
    final fragment = Uri.splitQueryString(uri.fragment);
    const keys = {
      'code',
      'access_token',
      'error',
      'error_code',
      'error_description',
    };
    if (!keys.any(
      (key) =>
          uri.queryParameters.containsKey(key) || fragment.containsKey(key),
    )) {
      return false;
    }
    latest = kind;
    return true;
  }
}
