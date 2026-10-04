import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../../core/validation/password_policy.dart';
import 'auth_flow_controller.dart';

// Auth state - tracks current user session
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<User?>>((ref) {
      return AuthNotifier(authFlow: ref.read(authFlowProvider));
    });

// Notifier that manages auth operations
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  AuthNotifier({SupabaseClient? supabase, this.authFlow})
    : _supabase = supabase ?? Supabase.instance.client,
      super(const AsyncValue.loading()) {
    _init();
  }

  final SupabaseClient _supabase;
  final AuthFlowController? authFlow;
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
        email: email,
        password: password,
      );
      state = AsyncValue.data(res.user);
      await _linkCustomerProfile();
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
      rethrow;
    }
  }

  // Link the auth user to its `customers` row (claiming a counter-created
  // row by email, or creating one). Screens retry this on load, so a failure
  // here must never block signing in.
  Future<void> _linkCustomerProfile() async {
    try {
      await CustomerAccountService(
        supabase: _supabase,
      ).resolveCurrentCustomer().timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Customer profile linking deferred: $error');
    }
  }

  // Register new account
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
    state = const AsyncValue.loading();
    try {
      authFlow?.beginRegistration();
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone_no': phoneNo,
          'address': address.trim(),
        },
      );
      // With email confirmation disabled the user already has a session, so
      // link the customer row now; otherwise it is linked on first sign-in.
      if (response.session != null) await _linkCustomerProfile();
      // Ensure user is signed out so they are not automatically logged in
      await _supabase.auth.signOut();
      state = const AsyncValue.data(null);
      return response.session == null;
    } on AuthException catch (e) {
      state = AsyncValue.error(e.message, StackTrace.current);
      rethrow;
    } finally {
      authFlow?.endRegistration();
    }
  }

  // Send password reset email
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email.trim(),
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
