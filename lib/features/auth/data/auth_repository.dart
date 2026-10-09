import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/customer_account_service.dart';
import '../../../core/utils/load_errors.dart';
import '../../../core/validation/password_policy.dart';
import '../../../core/validation/customer_identity.dart';
import 'auth_flow_controller.dart';
import 'auth_provider_settings.dart';

typedef GoogleSignInLauncher = Future<bool> Function({
  required String redirectTo,
  required LaunchMode launchMode,
});

// Auth state - tracks current user session
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
      return AuthNotifier(
        authFlow: ref.read(authFlowProvider),
        providerSettings: AuthProviderSettings(
          endpoint: Uri.parse('${AppConfig.supabaseUrl}/auth/v1/settings'),
          publicKey: Supabase.instance.client.auth.headers['apikey']!,
        ),
      );
    });

// Notifier that manages auth operations
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthNotifier({
    SupabaseClient? supabase,
    this.authFlow,
    this.googleSignInLauncher,
    this.providerSettings,
    this.authRequestTimeout = const Duration(seconds: 15),
  }) : _supabase = supabase ?? Supabase.instance.client,
       super(const AsyncValue.loading()) {
    _init();
  }

  final SupabaseClient _supabase;
  final AuthFlowController? authFlow;
  final GoogleSignInLauncher? googleSignInLauncher;
  final AuthProviderSettings? providerSettings;
  final Duration authRequestTimeout;
  StreamSubscription<AuthState>? _subscription;

  // Listen to auth state changes
  void _init() {
    final currentUser = _supabase.auth.currentUser;
    state = AsyncValue.data(currentUser);

    _subscription = _supabase.auth.onAuthStateChange.listen(
      (data) {
        state = AsyncValue.data(data.session?.user);
      },
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
  }

  // Sign in with email and password
  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: CustomerIdentity.normalizeEmail(email),
        password: password,
      );
      if (mounted) state = AsyncValue.data(res.user);
      await _linkCustomerProfile();
    } catch (error, stackTrace) {
      if (mounted) state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  /// Opens Google's account picker in the browser. Launching it does not mean
  /// the user has signed in: the returned callback updates the auth stream.
  Future<bool> signInWithGoogle() async {
    authFlow?.beginGoogleSignIn();
    try {
      await providerSettings?.requireGoogleSignIn();
      if (authFlow != null && !authFlow!.isGoogleSignInPending) return false;
      final redirectTo = AuthRedirects.signIn();
      final launchMode = kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication;
      final launcher = googleSignInLauncher;
      final launched =
          await (launcher == null
                  ? _supabase.auth.signInWithOAuth(
                      OAuthProvider.google,
                      redirectTo: redirectTo,
                      authScreenLaunchMode: launchMode,
                    )
                  : launcher(redirectTo: redirectTo, launchMode: launchMode))
              .timeout(authRequestTimeout);
      if (!launched) authFlow?.cancelGoogleSignIn();
      return launched;
    } catch (_) {
      authFlow?.cancelGoogleSignIn();
      rethrow;
    }
  }

  /// A phone code request never starts a session. Only successful verification
  /// below can authenticate the user, including first-time customers.
  Future<void> sendPhoneCode(String phone) async {
    final normalizedPhone = _requirePhoneNumber(phone);
    await _supabase.auth
        .signInWithOtp(
          phone: normalizedPhone,
          shouldCreateUser: true,
          channel: OtpChannel.sms,
        )
        .timeout(authRequestTimeout);
  }

  Future<void> verifyPhoneCode({
    required String phone,
    required String code,
  }) async {
    final normalizedPhone = _requirePhoneNumber(phone);
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{6,10}$').hasMatch(normalizedCode)) {
      throw ArgumentError('Enter the verification code from your SMS.');
    }
    state = const AsyncValue.loading();
    try {
      final response = await _supabase.auth
          .verifyOTP(
            phone: normalizedPhone,
            token: normalizedCode,
            type: OtpType.sms,
          )
          .timeout(authRequestTimeout);
      if (response.session == null || response.user == null) {
        throw const AuthException(
          'We could not verify your sign-in. Request a new code and try again.',
        );
      }
      if (mounted) state = AsyncValue.data(response.user);
      await _linkCustomerProfile();
    } catch (error, stackTrace) {
      if (mounted) {
        state = AsyncValue.error(
          error is AuthException ? error.message : error,
          stackTrace,
        );
      }
      rethrow;
    }
  }

  String _requirePhoneNumber(String phone) {
    final normalized = phone.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      throw ArgumentError('Enter a phone number with its country code.');
    }
    return normalized;
  }

  // Warm up the lookup of the `customers` row the sign-up trigger created.
  // The app never inserts or links customer rows itself (RLS has no INSERT
  // policy). Screens retry on load, so a failure must never block sign-in.
  Future<void> _linkCustomerProfile() async {
    try {
      await CustomerAccountService(supabase: _supabase)
          .resolveCurrentCustomer()
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint(
        'Customer profile lookup deferred: ${loadFailureDiagnostic(error)}',
      );
    }
  }

  // Registration validates locally; the database enforces uniqueness atomically.
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNo,
    required String address,
  }) async {
    final validation = PasswordPolicy.validate(password);
    if (validation != null) throw ArgumentError(validation);
    if (address.trim().isEmpty) {
      throw ArgumentError('An address is required to create an account.');
    }
    final identityError =
        CustomerIdentity.validateName(firstName, fieldName: 'first name') ??
        CustomerIdentity.validateName(lastName, fieldName: 'last name') ??
        CustomerIdentity.validateEmail(email) ??
        CustomerIdentity.validateOptionalPhone(phoneNo);
    if (identityError != null) throw ArgumentError(identityError);
    // Creating another account must never replace a restored/signed-in session.
    if (_supabase.auth.currentSession != null) {
      throw const AuthException(
        'You are already signed in. Use your existing account.',
        code: 'already_signed_in',
      );
    }
    state = const AsyncValue.loading();
    authFlow?.beginRegistration();
    try {
      final response = await _supabase.auth.signUp(
        email: CustomerIdentity.normalizeEmail(email),
        password: password,
        // The server creates an owned customer profile and checks normalized
        // email/phone identifiers. Names alone never identify a customer.
        data: {
          'first_name': CustomerIdentity.normalizeName(firstName),
          'last_name': CustomerIdentity.normalizeName(lastName),
          'phone_no': CustomerIdentity.normalizeOptionalPhone(phoneNo),
          'address': address.trim(),
        },
      );
      final registeredUser = response.user;
      // With confirmation enabled Supabase can conceal an existing account by
      // returning a user with no identities. That is not a new registration.
      if (registeredUser?.identities?.isEmpty == true) {
        throw const AuthException(
          'An account with this email already exists. Sign in or reset your password.',
          code: 'account_already_exists',
        );
      }
      if (registeredUser == null) {
        throw const AuthException(
          'Your account could not be created. Please try again.',
        );
      }
      // With email confirmation disabled signup briefly creates a session.
      // Only sign out a session created by this registration attempt.
      if (response.session != null) {
        await _linkCustomerProfile();
        if (_supabase.auth.currentUser?.id == registeredUser.id) {
          await _supabase.auth.signOut();
        }
      }
      if (mounted) state = AsyncValue.data(_supabase.auth.currentUser);
      return response.session == null;
    } catch (error, stackTrace) {
      if (mounted) state = AsyncValue.error(error, stackTrace);
      rethrow;
    } finally {
      authFlow?.endRegistration();
    }
  }

  // Send password reset email
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      CustomerIdentity.normalizeEmail(email),
      redirectTo: AuthRedirects.passwordReset(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    state = const AsyncValue.data(null);
  }
}
