import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/sign_in_profile_service.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';

void main() {
  late _ProfileServer server;
  late SupabaseClient client;
  final flows = <AuthFlowController>[];

  AuthFlowController createFlow({SignInProfileService? profiles}) {
    final flow = AuthFlowController(client, profiles: profiles);
    flows.add(flow);
    return flow;
  }

  Future<void> authenticate() => client.auth.verifyOTP(
    phone: '+639171234567',
    token: '123456',
    type: OtpType.sms,
  );

  setUp(() async {
    AuthCallbackTracker.latest = null;
    server = _ProfileServer();
    await server.start();
    client = SupabaseClient(
      server.url,
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(
        retryEnabled: false,
        requestTimeout: Duration(seconds: 3),
      ),
    );
  });

  tearDown(() async {
    for (final flow in flows) {
      flow.dispose();
    }
    flows.clear();
    await client.dispose();
    await server.close();
    AuthCallbackTracker.latest = null;
  });

  for (final provider in ['google', 'phone']) {
    test(
      '$provider first sign-in checks the required name and address',
      () async {
        server.provider = provider;
        server.holdCustomerReads = true;
        final flow = createFlow();
        await authenticate();
        await server.customerRequest(0);

        expect(flow.profileStage, SignInProfileStage.checking);
        expect(flow.requiresSignInProfile, isTrue);
        expect(flow.isLoggedIn, isTrue);
        expect(flow.requiresRecovery, isFalse);

        await server.respondCustomer(0, server.incompleteCustomer);
        await _waitForProfileStage(flow, SignInProfileStage.required);
        expect(flow.requiresSignInProfile, isTrue);
        expect(flow.signInCustomer?.id, 'customer-1');
        expect(flow.profileError, isNull);
      },
    );

    test(
      '$provider returning customers with saved details can enter the app',
      () async {
        server.provider = provider;
        server.customer = server.completeCustomer;
        final flow = createFlow();
        await authenticate();
        await _waitForProfileStage(flow, SignInProfileStage.ready);

        expect(flow.requiresSignInProfile, isFalse);
        expect(flow.signInCustomer?.address, '10 Mabini Street, Davao City');
        expect(server.rpcBodies, isEmpty);
      },
    );

    test(
      'cold restored $provider sessions pass through the profile gate',
      () async {
        server.provider = provider;
        server.holdCustomerReads = true;
        await client.auth.setInitialSession(jsonEncode(server.session));
        final flow = createFlow();
        await server.customerRequest(0);

        expect(flow.profileStage, SignInProfileStage.checking);
        expect(flow.requiresSignInProfile, isTrue);
        await server.respondCustomer(0, null);
        await _waitForProfileStage(flow, SignInProfileStage.required);
        expect(flow.signInCustomer, isNull);
        expect(server.customerRequests, hasLength(1));
        expect(server.verifyBodies, isEmpty);
      },
    );
  }

  for (final field in ['first_name', 'last_name', 'address']) {
    test('a blank $field still requires profile completion', () async {
      server.customer = {...server.completeCustomer, field: '  '};
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);

      expect(flow.requiresSignInProfile, isTrue);
    });
  }

  test('ordinary email users keep the existing sign-in flow', () async {
    server.provider = 'email';
    final flow = createFlow();
    await authenticate();
    await Future<void>.delayed(Duration.zero);

    expect(flow.profileStage, SignInProfileStage.idle);
    expect(flow.requiresSignInProfile, isFalse);
    expect(server.customerRequests, isEmpty);
  });

  test(
    'linked Google identities also require a complete customer profile',
    () async {
      server.provider = 'email';
      server.providers = ['email', 'google'];
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);

      expect(flow.requiresSignInProfile, isTrue);
    },
  );

  test('a dropped profile connection becomes retryable and recovers', () async {
    final flow = createFlow(profiles: _OfflineOnceProfileService(client));
    await authenticate();
    await _waitForProfileStage(flow, SignInProfileStage.failed);

    expect(flow.profileError, isA<SocketException>());
    expect(flow.requiresSignInProfile, isTrue);
    expect(flow.isLoggedIn, isTrue);

    server.customer = server.completeCustomer;
    flow.retrySignInProfile();
    await _waitForProfileStage(flow, SignInProfileStage.ready);
    expect(flow.profileError, isNull);
    expect(flow.requiresSignInProfile, isFalse);
    expect(server.customerRequests, hasLength(1));
  });

  test(
    'profile loads only read the active customer owned by the auth user',
    () async {
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);
      final query = server.customerRequests.single.uri.queryParameters;

      expect(query['auth_id'], 'eq.external-user-1');
      expect(query['deleted_at'], 'is.null');
      expect(query['limit'], '1');
    },
  );

  test(
    'first-time phone customers can complete their profile without an email',
    () async {
      server.provider = 'phone';
      server.customer = null;
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);
      expect(client.auth.currentUser?.email, '');

      await flow.completeSignInProfile(
        firstName: 'Alex',
        lastName: 'Reyes',
        address: 'Davao City',
      );

      expect(flow.profileStage, SignInProfileStage.ready);
      expect(flow.signInCustomer?.email, isNull);
      expect(
        server.rpcBodies.single.keys,
        unorderedEquals(['p_first_name', 'p_last_name', 'p_address']),
      );
    },
  );
  test(
    'completion rejects empty required fields before calling the RPC',
    () async {
      await authenticate();
      final service = SignInProfileService(client);
      for (final values in [
        ['', 'Reyes', 'Davao City'],
        ['Alex', '  ', 'Davao City'],
        ['Alex', 'Reyes', '  '],
      ]) {
        await expectLater(
          service.complete(
            firstName: values[0],
            lastName: values[1],
            address: values[2],
          ),
          throwsArgumentError,
        );
      }
      expect(server.rpcBodies, isEmpty);
    },
  );

  test('signed-out completion cannot call the customer profile RPC', () async {
    await expectLater(
      SignInProfileService(
        client,
      ).complete(firstName: 'Alex', lastName: 'Reyes', address: 'Davao City'),
      throwsA(isA<AuthException>()),
    );
    expect(server.rpcBodies, isEmpty);
  });

  test(
    'completion sends trimmed name/address and relies on server ownership',
    () async {
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);

      await flow.completeSignInProfile(
        firstName: ' Alex ',
        lastName: ' Reyes ',
        address: ' 10 Mabini Street, Davao City ',
      );

      expect(server.rpcBodies.single, {
        'p_first_name': 'Alex',
        'p_last_name': 'Reyes',
        'p_address': '10 Mabini Street, Davao City',
      });
      expect(server.rpcAuthorizations.single, startsWith('Bearer '));
      expect(flow.profileStage, SignInProfileStage.ready);
      expect(flow.requiresSignInProfile, isFalse);
      expect(flow.signInCustomer?.firstName, 'Alex');
      expect(server.customerRequests, hasLength(2));
    },
  );

  test(
    'RPC success only completes sign-in after saved details are reloaded',
    () async {
      server.holdCustomerReads = true;
      final flow = createFlow();
      await authenticate();
      await server.respondCustomer(0, server.incompleteCustomer);
      await _waitForProfileStage(flow, SignInProfileStage.required);

      final saving = flow.completeSignInProfile(
        firstName: 'Alex',
        lastName: 'Reyes',
        address: '10 Mabini Street, Davao City',
      );
      await server.customerRequest(1);
      expect(server.rpcBodies, hasLength(1));
      expect(flow.profileStage, SignInProfileStage.required);
      expect(flow.requiresSignInProfile, isTrue);

      await server.respondCustomer(1, server.customer);
      await saving;
      expect(flow.profileStage, SignInProfileStage.ready);
      expect(flow.requiresSignInProfile, isFalse);
    },
  );

  test(
    'an RPC that does not save required details never completes sign-in',
    () async {
      server.persistRpc = false;
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);

      await expectLater(
        flow.completeSignInProfile(
          firstName: 'Alex',
          lastName: 'Reyes',
          address: 'Davao City',
        ),
        throwsStateError,
      );
      expect(flow.profileStage, SignInProfileStage.required);
      expect(flow.requiresSignInProfile, isTrue);
    },
  );

  test(
    'an RPC failure leaves the required profile available for another attempt',
    () async {
      server.rejectRpc = true;
      final flow = createFlow();
      await authenticate();
      await _waitForProfileStage(flow, SignInProfileStage.required);

      await expectLater(
        flow.completeSignInProfile(
          firstName: 'Alex',
          lastName: 'Reyes',
          address: 'Davao City',
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(flow.profileStage, SignInProfileStage.required);
      expect(flow.requiresSignInProfile, isTrue);
      expect(server.customerRequests, hasLength(1));

      server.rejectRpc = false;
      await flow.completeSignInProfile(
        firstName: 'Alex',
        lastName: 'Reyes',
        address: 'Davao City',
      );
      expect(flow.profileStage, SignInProfileStage.ready);
    },
  );

  test(
    'a late profile response cannot reopen the gate after sign-out',
    () async {
      server.holdCustomerReads = true;
      final profiles = _ObservedProfileService(client);
      final flow = createFlow(profiles: profiles);
      await authenticate();
      await server.customerRequest(0);
      expect(flow.profileStage, SignInProfileStage.checking);

      await client.auth.signOut(scope: SignOutScope.local);
      await _waitForProfileStage(flow, SignInProfileStage.idle);
      await server.respondCustomer(0, server.incompleteCustomer);
      await profiles.loaded.future;
      await Future<void>.delayed(Duration.zero);

      expect(flow.isLoggedIn, isFalse);
      expect(flow.profileStage, SignInProfileStage.idle);
      expect(flow.requiresSignInProfile, isFalse);
      expect(flow.signInCustomer, isNull);
    },
  );

  test(
    'a late completion response cannot make a signed-out account ready',
    () async {
      server.holdCustomerReads = true;
      final flow = createFlow();
      await authenticate();
      await server.respondCustomer(0, server.incompleteCustomer);
      await _waitForProfileStage(flow, SignInProfileStage.required);
      final saving = flow.completeSignInProfile(
        firstName: 'Alex',
        lastName: 'Reyes',
        address: 'Davao City',
      );
      final failure = expectLater(saving, throwsA(isA<AuthException>()));
      await server.customerRequest(1);

      await client.auth.signOut(scope: SignOutScope.local);
      await _waitForProfileStage(flow, SignInProfileStage.idle);
      await server.respondCustomer(1, server.customer);
      await failure;

      expect(flow.profileStage, SignInProfileStage.idle);
      expect(flow.requiresSignInProfile, isFalse);
      expect(flow.isLoggedIn, isFalse);
    },
  );

  test('cold Google callback errors stay out of password recovery', () async {
    expect(
      AuthCallbackTracker.detect(
        Uri.parse(
          'com.repairshop101://auth/login-callback?error=access_denied',
        ),
      ),
      isTrue,
    );
    _emitAuthError(
      client,
      const AuthException('Access denied', code: 'access_denied'),
    );
    final flow = createFlow();
    await _waitForGoogleError(flow);

    expect(flow.isGoogleSignInPending, isFalse);
    expect(flow.requiresRecovery, isFalse);
    expect(flow.stage, PasswordRecoveryStage.idle);
    expect(flow.isLoggedIn, isFalse);
    expect(flow.requiresSignInProfile, isFalse);
  });

  for (final identity in ['phone number', 'email']) {
    for (final coldCallback in [false, true]) {
      test(
        'duplicate $identity on ${coldCallback ? 'cold' : 'pending'} Google callback explains how to use the existing account',
        () async {
          AuthFlowController? flow;
          if (coldCallback) {
            expect(
              AuthCallbackTracker.detect(
                Uri.parse(
                  'com.repairshop101://auth/login-callback?error=hook_error',
                ),
              ),
              isTrue,
            );
          } else {
            flow = createFlow();
            flow.beginGoogleSignIn();
          }
          _emitAuthError(
            client,
            AuthException(
              'This $identity is already associated with a customer account.',
              code: 'hook_error',
            ),
          );
          flow ??= createFlow();
          await _waitForGoogleError(flow);

          expect(
            flow.googleSignInError,
            identity == 'phone number'
                ? 'This phone number is already linked to an account. Sign in to that account or contact the shop.'
                : 'This email is already linked to an account. Sign in or reset your password.',
          );
          expect(flow.isGoogleSignInPending, isFalse);
          expect(AuthCallbackTracker.latest, isNull);
          expect(flow.isLoggedIn, isFalse);
          expect(flow.requiresRecovery, isFalse);
          expect(flow.requiresSignInProfile, isFalse);

          flow.beginGoogleSignIn();
          expect(flow.isGoogleSignInPending, isTrue);
          expect(flow.googleSignInError, isNull);
        },
      );
    }
  }

  for (final error in [
    const AuthException('Google provider disabled', code: 'provider_disabled'),
    const AuthException('Invalid callback code', code: 'validation_failed'),
    const AuthException('Unrecognized callback failure', code: 'unknown'),
    AuthRetryableFetchException(message: 'SocketException: no connection'),
  ]) {
    test(
      'ordinary Google callback error ${error.code ?? error.runtimeType} keeps its fallback',
      () async {
        final flow = createFlow();
        flow.beginGoogleSignIn();
        _emitAuthError(client, error);
        await _waitForGoogleError(flow);
        expect(
          flow.googleSignInError,
          'Google sign-in was not completed. Please try again.',
        );
        expect(flow.isGoogleSignInPending, isFalse);
        expect(flow.requiresRecovery, isFalse);
        expect(flow.isLoggedIn, isFalse);
      },
    );
  }

  test(
    'password recovery errors still open the recovery error screen',
    () async {
      expect(
        AuthCallbackTracker.detect(
          Uri.parse(
            'com.repairshop101://auth/reset-password?error_code=otp_expired',
          ),
        ),
        isTrue,
      );
      _emitAuthError(
        client,
        const AuthException('Expired reset link', code: 'otp_expired'),
      );
      final flow = createFlow();
      await _waitForRecoveryStage(flow, PasswordRecoveryStage.invalid);

      expect(flow.requiresRecovery, isTrue);
      expect(flow.googleSignInError, isNull);
      expect(flow.profileStage, SignInProfileStage.idle);
    },
  );

  test(
    'verified password recovery remains available for external users',
    () async {
      final flow = createFlow();
      await client.auth.verifyOTP(
        tokenHash: 'test-recovery-hash',
        type: OtpType.recovery,
      );
      await _waitForRecoveryStage(flow, PasswordRecoveryStage.ready);

      expect(flow.requiresRecovery, isTrue);
      expect(flow.canResetPassword, isTrue);
      await _waitForProfileStage(flow, SignInProfileStage.required);
      expect(flow.stage, PasswordRecoveryStage.ready);
    },
  );

  test('callback detection recognizes native fragment errors and web PKCE codes', () {
    expect(
      AuthCallbackTracker.detect(
        Uri.parse(
          'com.repairshop101://auth/login-callback#error=access_denied',
        ),
      ),
      isTrue,
    );
    expect(AuthCallbackTracker.latest, AuthCallbackKind.signIn);
    expect(
      AuthCallbackTracker.detect(
        Uri.parse(
          'https://repair.example/app/?code=test-auth-code#/login-callback',
        ),
      ),
      isTrue,
    );
    expect(AuthCallbackTracker.latest, AuthCallbackKind.signIn);
    expect(
      AuthCallbackTracker.detect(
        Uri.parse(
          'https://repair.example/app/?code=test-recovery-code#/reset-password',
        ),
      ),
      isTrue,
    );
    expect(AuthCallbackTracker.latest, AuthCallbackKind.recovery);
  });

  test(
    'web Google errors retain their callback origin when the hash is replaced',
    () async {
      final callback = Uri.parse(
        'https://repair.example/app/?auth_callback=sign_in#error=access_denied&error_description=Cancelled',
      );
      expect(AuthCallbackTracker.detect(callback), isTrue);
      expect(AuthCallbackTracker.latest, AuthCallbackKind.signIn);
      _emitAuthError(
        client,
        const AuthException('Cancelled', code: 'access_denied'),
      );
      final flow = createFlow();
      await _waitForGoogleError(flow);

      expect(flow.requiresRecovery, isFalse);
      expect(flow.stage, PasswordRecoveryStage.idle);
    },
  );

  test(
    'an expired recovery callback takes priority over a pending Google sign-in',
    () async {
      final flow = createFlow();
      flow.beginGoogleSignIn();
      expect(flow.isGoogleSignInPending, isTrue);
      expect(
        AuthCallbackTracker.detect(
          Uri.parse(
            'com.repairshop101://auth/reset-password?error=otp_expired',
          ),
        ),
        isTrue,
      );
      _emitAuthError(
        client,
        const AuthException('Expired reset link', code: 'otp_expired'),
      );
      await _waitForRecoveryStage(flow, PasswordRecoveryStage.invalid);

      expect(flow.requiresRecovery, isTrue);
      expect(flow.isGoogleSignInPending, isFalse);
      expect(flow.googleSignInError, isNull);
    },
  );

  test(
    'Google cancellation clears the origin before a later recovery error',
    () async {
      final flow = createFlow();
      flow.beginGoogleSignIn();
      flow.cancelGoogleSignIn();
      expect(AuthCallbackTracker.latest, isNull);
      _emitAuthError(
        client,
        const AuthException('Expired reset link', code: 'otp_expired'),
      );
      await _waitForRecoveryStage(flow, PasswordRecoveryStage.invalid);

      expect(flow.requiresRecovery, isTrue);
      expect(flow.googleSignInError, isNull);
    },
  );

  test(
    'sign-out clears a pending Google sign-in and its callback origin',
    () async {
      final flow = createFlow();
      flow.beginGoogleSignIn();
      expect(flow.isGoogleSignInPending, isTrue);
      await client.auth.signOut(scope: SignOutScope.local);
      await _waitFor(flow, () => !flow.isGoogleSignInPending);

      expect(AuthCallbackTracker.latest, isNull);
      expect(flow.googleSignInError, isNull);
      expect(flow.requiresSignInProfile, isFalse);
    },
  );

  test(
    'verified recovery clears a previously pending Google sign-in',
    () async {
      final flow = createFlow();
      flow.beginGoogleSignIn();
      await client.auth.verifyOTP(
        tokenHash: 'test-recovery-hash',
        type: OtpType.recovery,
      );
      await _waitForRecoveryStage(flow, PasswordRecoveryStage.ready);

      expect(flow.isGoogleSignInPending, isFalse);
      expect(AuthCallbackTracker.latest, isNull);
      expect(flow.canResetPassword, isTrue);
    },
  );
  test(
    'web redirect markers preserve callback paths without old auth parameters',
    () {
      final base = Uri.parse(
        'https://repair.example:8443/app/?code=old-code#/login',
      );
      final signIn = Uri.parse(AuthRedirects.signIn(webBase: base));
      final recovery = Uri.parse(AuthRedirects.passwordReset(webBase: base));

      expect(signIn.path, '/app/');
      expect(signIn.port, 8443);
      expect(signIn.fragment, '/login-callback');
      expect(signIn.queryParameters, {'auth_callback': 'sign_in'});
      expect(recovery.fragment, '/reset-password');
      expect(recovery.queryParameters, {'auth_callback': 'recovery'});
    },
  );
  test('ordinary app routes and token-free callback routes are ignored', () {
    for (final uri in [
      'com.repairshop101://auth/login-callback',
      'https://repair.example/app/#/login-callback',
      'https://repair.example/app/?code=test-auth-code#/repairs',
      'otherapp://auth/login-callback?code=test-auth-code',
    ]) {
      expect(AuthCallbackTracker.detect(Uri.parse(uri)), isFalse);
    }
    expect(AuthCallbackTracker.latest, isNull);
  });
}

/// Models the SDK's deep-link handler emitting its error onto the auth stream.
void _emitAuthError(SupabaseClient client, AuthException error) {
  // ignore: invalid_use_of_internal_member
  client.auth.notifyException(error);
}

Future<void> _waitForProfileStage(
  AuthFlowController flow,
  SignInProfileStage stage,
) => _waitFor(flow, () => flow.profileStage == stage);

Future<void> _waitForRecoveryStage(
  AuthFlowController flow,
  PasswordRecoveryStage stage,
) => _waitFor(flow, () => flow.stage == stage);

Future<void> _waitForGoogleError(AuthFlowController flow) =>
    _waitFor(flow, () => flow.googleSignInError != null);

Future<void> _waitFor(AuthFlowController flow, bool Function() matches) async {
  if (matches()) return;
  final completer = Completer<void>();
  void check() {
    if (matches() && !completer.isCompleted) completer.complete();
  }

  flow.addListener(check);
  try {
    check();
    await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException(
        'Profile stage: ${flow.profileStage}; error: ${flow.profileError}; recovery: ${flow.stage}',
      ),
    );
  } finally {
    flow.removeListener(check);
  }
}

/// Injects a transport failure without depending on platform socket behavior.
/// The next load uses the real authenticated PostgREST query on loopback.
class _OfflineOnceProfileService extends SignInProfileService {
  _OfflineOnceProfileService(super.client);
  bool _firstLoad = true;

  @override
  Future<Customer?> load() async {
    if (_firstLoad) {
      _firstLoad = false;
      throw const SocketException('Simulated disconnected network');
    }
    return super.load();
  }
}

class _ObservedProfileService extends SignInProfileService {
  _ObservedProfileService(super.client);
  final loaded = Completer<void>();

  @override
  Future<Customer?> load() async {
    try {
      return await super.load();
    } finally {
      if (!loaded.isCompleted) loaded.complete();
    }
  }
}

/// Contains fictitious accounts and handles requests on loopback only.
class _ProfileServer {
  late HttpServer _server;
  String provider = 'google';
  List<String>? providers;
  bool holdCustomerReads = false;
  bool persistRpc = true;
  bool rejectRpc = false;
  Map<String, dynamic>? customer;
  final customerRequests = <HttpRequest>[];
  final rpcBodies = <Map<String, dynamic>>[];
  final rpcAuthorizations = <String?>[];
  final verifyBodies = <Map<String, dynamic>>[];
  final _customerArrivals = <int, Completer<HttpRequest>>{};

  String get url => 'http://127.0.0.1:${_server.port}';

  Map<String, dynamic> get incompleteCustomer => {
    'id': 'customer-1',
    'auth_id': 'external-user-1',
    'first_name': '',
    'last_name': '',
    'address': null,
    'deleted_at': null,
  };

  Map<String, dynamic> get completeCustomer => {
    ...incompleteCustomer,
    'first_name': 'Alex',
    'last_name': 'Reyes',
    'address': '10 Mabini Street, Davao City',
  };

  Map<String, dynamic> get session {
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url
        .encode(
          utf8.encode(jsonEncode({'sub': 'external-user-1', 'exp': expiry})),
        )
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'external-user-1',
        'aud': 'authenticated',
        'email': provider == 'phone' ? '' : 'alex@example.com',
        'phone': provider == 'phone' ? '+639171234567' : '',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {
          'provider': provider,
          'providers': providers ?? [provider],
        },
        'user_metadata': <String, dynamic>{},
      },
    };
  }

  Future<void> start() async {
    customer = incompleteCustomer;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<HttpRequest> customerRequest(int index) {
    if (index < customerRequests.length) {
      return Future.value(customerRequests[index]);
    }
    return (_customerArrivals[index] ??= Completer<HttpRequest>()).future
        .timeout(const Duration(seconds: 5));
  }

  Future<void> respondCustomer(int index, Map<String, dynamic>? row) async {
    final request = await customerRequest(index);
    request.response.write(jsonEncode(row == null ? [] : [row]));
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    final body = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('x-supabase-api-version', '2024-01-01');
    switch ('${request.method} ${request.uri.path}') {
      case 'POST /auth/v1/verify':
        verifyBodies.add(body);
        request.response.write(jsonEncode(session));
      case 'GET /rest/v1/customers':
        final index = customerRequests.length;
        customerRequests.add(request);
        _customerArrivals.remove(index)?.complete(request);

        if (holdCustomerReads) return;
        request.response.write(jsonEncode(customer == null ? [] : [customer]));
      case 'POST /rest/v1/rpc/complete_customer_profile':
        rpcBodies.add(body);
        rpcAuthorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (rejectRpc) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write(
            jsonEncode({'code': '42501', 'message': 'Profile unavailable'}),
          );
        } else {
          if (persistRpc) {
            customer = {
              ...incompleteCustomer,
              'first_name': body['p_first_name'],
              'last_name': body['p_last_name'],
              'address': body['p_address'],
            };
          }
          request.response.write(jsonEncode('customer-1'));
        }
      case 'POST /auth/v1/logout':
        request.response.statusCode = HttpStatus.noContent;
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
    }
    await request.response.close();
  }
}
