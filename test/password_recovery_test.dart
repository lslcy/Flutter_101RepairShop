import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/validation/password_policy.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';

void main() {
  late _RecoveryServer server;
  late SupabaseClient client;
  late AuthNotifier notifier;
  final flows = <AuthFlowController>[];

  AuthFlowController createFlow() {
    final flow = AuthFlowController(client);
    flows.add(flow);
    return flow;
  }

  Future<void> verifyRecovery() async {
    await client.auth.verifyOTP(
      tokenHash: 'test-recovery-token-hash',
      type: OtpType.recovery,
    );
  }

  Future<AuthFlowController> recoverBeforeControllerStarts() async {
    // Reproduces an app opening the email link before the router is built.
    await verifyRecovery();
    final flow = createFlow();
    await _waitForStage(flow, PasswordRecoveryStage.ready);
    return flow;
  }

  setUp(() async {
    server = _RecoveryServer();
    await server.start();
    client = SupabaseClient(
      server.url,
      'test-anon-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
    notifier = AuthNotifier(supabase: client);
  });

  tearDown(() async {
    for (final flow in flows) {
      flow.dispose();
    }
    flows.clear();
    notifier.dispose();
    await client.dispose();
    await server.close();
  });

  test(
    'reset email includes the mobile recovery destination and trimmed email',
    () async {
      await notifier.resetPassword('  customer@example.com  ');

      expect(server.recoverBodies, hasLength(1));
      expect(server.recoverBodies.single['email'], 'customer@example.com');
      expect(
        server.recoverQueries.single['redirect_to'],
        'com.repairshop101://auth/reset-password',
      );
      expect(server.recoverBodies.single['code_challenge'], isNotEmpty);
      expect(server.recoverBodies.single['code_challenge_method'], 's256');
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'a cold-start recovery event is replayed to the recovery controller',
    () async {
      final flow = await recoverBeforeControllerStarts();

      expect(server.verifyBodies.single['type'], 'recovery');
      expect(flow.isLoggedIn, isTrue);
      expect(flow.requiresRecovery, isTrue);
      expect(flow.canResetPassword, isTrue);
      expect(flow.stage, PasswordRecoveryStage.ready);
      expect(server.updateBodies, isEmpty);
    },
  );

  test(
    'an already running controller accepts a newly verified recovery link',
    () async {
      final flow = createFlow();
      expect(flow.canResetPassword, isFalse);

      await verifyRecovery();
      await _waitForStage(flow, PasswordRecoveryStage.ready);

      expect(flow.canResetPassword, isTrue);
      expect(flow.requiresRecovery, isTrue);
    },
  );

  test(
    'seven-character signup is rejected before any signup request',
    () async {
      await expectLater(
        notifier.signUp(
          email: 'customer@example.com',
          password: 'Ab1!abc',
          firstName: 'Alex',
          lastName: 'Reyes',
          address: '10 Mabini Street, Davao City',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(server.signupBodies, isEmpty);
      expect(client.auth.currentSession, isNull);
    },
  );

  for (final invalid in <String, String>{
    'Abcdef12': PasswordPolicy.specialCharacterMessage,
    'abcdef1!': PasswordPolicy.uppercaseLetterMessage,
    'Abcdefg!': PasswordPolicy.numberMessage,
  }.entries) {
    test('signup blocks an unmet requirement: ${invalid.value}', () async {
      await expectLater(
        notifier.signUp(
          email: 'customer@example.com',
          password: invalid.key,
          firstName: 'Alex',
          lastName: 'Reyes',
          address: '10 Mabini Street, Davao City',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            invalid.value,
          ),
        ),
      );
      expect(server.signupBodies, isEmpty);
      expect(client.auth.currentSession, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test('recovery blocks an unmet requirement: ${invalid.value}', () async {
      final flow = await recoverBeforeControllerStarts();
      await expectLater(
        flow.updatePassword(invalid.key),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            invalid.value,
          ),
        ),
      );
      expect(server.updateBodies, isEmpty);
      expect(flow.stage, PasswordRecoveryStage.ready);
      expect(flow.canResetPassword, isTrue);
    });
  }

  test(
    'signup submits the password exactly as entered, including spaces',
    () async {
      const password = ' Ab1!   ';
      await notifier.signUp(
        email: 'customer@example.com',
        password: password,
        firstName: 'Alex',
        lastName: 'Reyes',
        address: '10 Mabini Street, Davao City',
      );
      expect(server.signupBodies.single['password'], password);
    },
  );

  test(
    'recovery submits the password exactly as entered, including spaces',
    () async {
      final flow = await recoverBeforeControllerStarts();
      const password = ' Ab1!   ';
      await flow.updatePassword(password);
      expect(server.updateBodies.single['password'], password);
      expect(flow.stage, PasswordRecoveryStage.complete);
    },
  );
  test('an eight-character signup reaches the service', () async {
    final needsConfirmation = await notifier.signUp(
      email: 'customer@example.com',
      password: 'Abcde1!f',
      firstName: 'Alex',
      lastName: 'Reyes',
      address: '10 Mabini Street, Davao City',
    );

    expect(needsConfirmation, isTrue);
    expect(server.signupBodies, hasLength(1));
    expect(server.signupBodies.single['password'], 'Abcde1!f');
    expect(client.auth.currentSession, isNull);
  });

  test(
    'seven-character recovery password is rejected without updating the user',
    () async {
      final flow = await recoverBeforeControllerStarts();

      await expectLater(
        flow.updatePassword('Ab1!abc'),
        throwsA(isA<ArgumentError>()),
      );

      expect(server.updateBodies, isEmpty);
      expect(flow.stage, PasswordRecoveryStage.ready);
      expect(flow.canResetPassword, isTrue);
    },
  );

  test(
    'ordinary sign-in cannot authorize a recovery password change',
    () async {
      final flow = createFlow();
      await notifier.signIn('customer@example.com', 'oldpass');
      // Let the normal signedIn event arrive before attempting recovery.
      await Future<void>.delayed(Duration.zero);

      expect(client.auth.currentSession, isNotNull);
      expect(flow.stage, PasswordRecoveryStage.idle);
      await expectLater(
        flow.updatePassword('Abcde1!f'),
        throwsA(isA<AuthException>()),
      );
      expect(server.updateBodies, isEmpty);
      expect(flow.canResetPassword, isFalse);
      expect(flow.requiresRecovery, isFalse);
    },
  );

  test(
    'verified recovery saves eight characters and completes before continuing',
    () async {
      final flow = await recoverBeforeControllerStarts();

      await flow.updatePassword('Abcde1!f');

      expect(server.updateBodies, hasLength(1));
      expect(server.updateBodies.single['password'], 'Abcde1!f');
      expect(server.updateAuthorizations.single, startsWith('Bearer '));
      expect(flow.stage, PasswordRecoveryStage.complete);
      expect(flow.requiresRecovery, isTrue);
      expect(flow.canResetPassword, isFalse);

      // A second submit after completion must not repeat the write.
      await expectLater(
        flow.updatePassword('Different-password1!'),
        throwsA(isA<AuthException>()),
      );
      expect(server.updateBodies, hasLength(1));

      flow.finishRecovery();
      expect(flow.stage, PasswordRecoveryStage.idle);
      expect(flow.requiresRecovery, isFalse);
      expect(client.auth.currentSession, isNotNull);
    },
  );

  test(
    'failed password update keeps recovery usable for a successful retry',
    () async {
      final flow = await recoverBeforeControllerStarts();
      server.rejectUpdate = true;

      await expectLater(
        flow.updatePassword('Abcde1!f'),
        throwsA(isA<AuthException>()),
      );
      expect(flow.stage, PasswordRecoveryStage.ready);
      expect(flow.canResetPassword, isTrue);
      expect(server.updateBodies, hasLength(1));

      server.rejectUpdate = false;
      await flow.updatePassword('New-password1!');
      expect(server.updateBodies, hasLength(2));
      expect(server.updateBodies.last['password'], 'New-password1!');
      expect(flow.stage, PasswordRecoveryStage.complete);
    },
  );

  for (final code in ['jwt_expired', 'session_not_found']) {
    test('an expired recovery session requires a fresh link: $code', () async {
      final flow = await recoverBeforeControllerStarts();
      server.rejectUpdate = true;
      server.updateErrorCode = code;
      server.updateErrorStatus = HttpStatus.unauthorized;

      await expectLater(
        flow.updatePassword('Abcde1!f'),
        throwsA(
          isA<AuthException>().having((error) => error.code, 'code', code),
        ),
      );
      expect(flow.stage, PasswordRecoveryStage.invalid);
      expect(flow.canResetPassword, isFalse);
      expect(flow.requiresRecovery, isTrue);
      expect(server.updateBodies, hasLength(1));

      await expectLater(
        flow.updatePassword('Another-password1!'),
        throwsA(isA<AuthException>()),
      );
      expect(server.updateBodies, hasLength(1));

      server.rejectUpdate = false;
      await verifyRecovery();
      await _waitForStage(flow, PasswordRecoveryStage.ready);
      expect(flow.canResetPassword, isTrue);
      await flow.updatePassword('New-password1!');
      expect(server.updateBodies, hasLength(2));
      expect(flow.stage, PasswordRecoveryStage.complete);
    });
  }

  test(
    'a failed remote logout still abandons a locally cleared recovery session',
    () async {
      final flow = await recoverBeforeControllerStarts();
      server.rejectLogout = true;

      await flow.abandonRecovery();
      await Future<void>.delayed(Duration.zero);

      expect(server.logoutQueries.single['scope'], 'local');
      expect(client.auth.currentSession, isNull);
      expect(client.auth.currentUser, isNull);
      expect(flow.stage, PasswordRecoveryStage.idle);
      expect(flow.requiresRecovery, isFalse);
      expect(flow.canResetPassword, isFalse);
      expect(server.updateBodies, isEmpty);
    },
  );
  test(
    'abandoning recovery signs out its session and returns to idle',
    () async {
      final flow = await recoverBeforeControllerStarts();

      await flow.abandonRecovery();
      await Future<void>.delayed(Duration.zero);

      expect(client.auth.currentSession, isNull);
      expect(client.auth.currentUser, isNull);
      expect(server.logoutQueries.single['scope'], 'local');
      expect(flow.stage, PasswordRecoveryStage.idle);
      expect(flow.requiresRecovery, isFalse);
      expect(flow.canResetPassword, isFalse);
      expect(server.updateBodies, isEmpty);
    },
  );

  test(
    'losing the recovery session prevents subsequent password changes',
    () async {
      final flow = await recoverBeforeControllerStarts();

      await client.auth.signOut(scope: SignOutScope.local);
      await _waitForStage(flow, PasswordRecoveryStage.invalid);
      await expectLater(
        flow.updatePassword('Abcde1!f'),
        throwsA(isA<AuthException>()),
      );

      expect(flow.canResetPassword, isFalse);
      expect(server.updateBodies, isEmpty);
    },
  );

  for (final error in <AuthException>[
    const AuthException('Code verifier could not be found in local storage.'),
    const AuthPKCEGrantCodeExchangeError('Unable to exchange recovery code.'),
  ]) {
    test(
      'a recovery link error without a code invalidates recovery: ${error.runtimeType}',
      () async {
        final flow = createFlow();

        // Inject the SDK's documented auth-stream failure at its source.
        // ignore: invalid_use_of_internal_member
        client.auth.notifyException(error);
        await _waitForStage(flow, PasswordRecoveryStage.invalid);

        expect(flow.requiresRecovery, isTrue);
        expect(flow.canResetPassword, isFalse);
        await expectLater(
          flow.updatePassword('Abcde1!f'),
          throwsA(isA<AuthException>()),
        );
        expect(server.updateBodies, isEmpty);
      },
    );
  }

  test(
    'ordinary network stream errors do not force password recovery',
    () async {
      final flow = createFlow();
      await notifier.signIn('customer@example.com', 'oldpass');
      await Future<void>.delayed(Duration.zero);

      // ignore: invalid_use_of_internal_member
      client.auth.notifyException(
        AuthRetryableFetchException(message: 'Connection timed out'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(flow.stage, PasswordRecoveryStage.idle);
      expect(flow.requiresRecovery, isFalse);
      expect(flow.canResetPassword, isFalse);
      expect(client.auth.currentSession, isNotNull);
    },
  );

  test('signup retains its registration flag through temporary sign-in and sign-out', () async {
    final flow = createFlow();
    final registeringNotifier = AuthNotifier(supabase: client, authFlow: flow);
    server.signupCreatesSession = true;
    server.logoutGate = Completer<void>();
    final registeringAtSignIn = <bool>[];
    final subscription = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        registeringAtSignIn.add(flow.isRegistering);
      }
    });
    final pendingSignup = registeringNotifier.signUp(
      email: 'customer@example.com',
      password: 'Abcde1!f',
      firstName: 'Alex',
      lastName: 'Reyes',
      address: '10 Mabini Street, Davao City',
    );

    try {
      await server.logoutStarted.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(registeringAtSignIn, [true]);
      expect(flow.isRegistering, isTrue);

      server.logoutGate!.complete();
      expect(await pendingSignup, isFalse);
      expect(flow.isRegistering, isFalse);
      expect(client.auth.currentSession, isNull);
    } finally {
      if (!server.logoutGate!.isCompleted) server.logoutGate!.complete();
      await pendingSignup;
      await subscription.cancel();
      registeringNotifier.dispose();
    }
  });

  test(
    'web recovery URL marks callback origin and removes stale query values',
    () {
      final destination = AuthRedirects.passwordReset(
        webBase: Uri.parse('https://example.com:8443/app/?token=old#/login'),
      );

      expect(
        destination,
        'https://example.com:8443/app/?auth_callback=recovery#/reset-password',
      );
      expect(Uri.parse(destination).queryParameters, {
        'auth_callback': 'recovery',
      });
    },
  );
  test('web recovery destination preserves its hosting subdirectory', () {
    final result = Uri.parse(
      AuthRedirects.passwordReset(
        webBase: Uri.parse('https://example.com/repair-app/?old=1#/login'),
      ),
    );

    expect(result.origin, 'https://example.com');
    expect(result.path, '/repair-app/');
    expect(result.queryParameters, {'auth_callback': 'recovery'});
    expect(result.fragment, '/reset-password');
  });
}

Future<void> _waitForStage(
  AuthFlowController flow,
  PasswordRecoveryStage expected,
) async {
  if (flow.stage == expected) return;
  final completed = Completer<void>();
  void onChange() {
    if (flow.stage == expected && !completed.isCompleted) completed.complete();
  }

  flow.addListener(onChange);
  try {
    await completed.future.timeout(const Duration(seconds: 3));
  } finally {
    flow.removeListener(onChange);
  }
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

// Exercise the installed Supabase SDK and its auth stream against local HTTP.
class _RecoveryServer {
  late HttpServer _server;
  bool rejectUpdate = false;
  String updateErrorCode = 'weak_password';
  int updateErrorStatus = HttpStatus.unprocessableEntity;
  bool rejectLogout = false;
  bool signupCreatesSession = false;
  Completer<void>? logoutGate;
  final logoutStarted = Completer<void>();
  final recoverBodies = <Map<String, dynamic>>[];
  final recoverQueries = <Map<String, String>>[];
  final verifyBodies = <Map<String, dynamic>>[];
  final signupBodies = <Map<String, dynamic>>[];
  final updateBodies = <Map<String, dynamic>>[];
  final updateAuthorizations = <String?>[];
  final logoutQueries = <Map<String, String>>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  Map<String, dynamic> get user => {
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'customer@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  };

  Map<String, dynamic> get session {
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': 'user-1', 'exp': expiry})))
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user,
    };
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    final body = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('x-supabase-api-version', '2024-01-01');
    switch ('${request.method} ${request.uri.path}') {
      case 'POST /auth/v1/recover':
        recoverBodies.add(body);
        recoverQueries.add(request.uri.queryParameters);
        await _respond(request, <String, dynamic>{});
      case 'POST /auth/v1/verify':
        verifyBodies.add(body);
        await _respond(request, session);
      case 'POST /auth/v1/token':
        await _respond(request, session);
      case 'POST /auth/v1/signup':
        signupBodies.add(body);
        await _respond(request, signupCreatesSession ? session : user);
      case 'PUT /auth/v1/user':
        updateBodies.add(body);
        updateAuthorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        if (rejectUpdate) {
          request.response.statusCode = updateErrorStatus;
          await _respond(request, {
            'code': updateErrorCode,
            'message': 'The password could not be saved. Please try again.',
          });
        } else {
          await _respond(request, user);
        }
      case 'POST /auth/v1/logout':
        logoutQueries.add(request.uri.queryParameters);
        if (!logoutStarted.isCompleted) logoutStarted.complete();
        await logoutGate?.future;
        if (rejectLogout) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await _respond(request, {
            'message': 'Service temporarily unavailable',
          });
        } else {
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
        }
      default:
        request.response.statusCode = HttpStatus.notFound;
        await _respond(request, {'message': 'Unknown test route'});
    }
  }

  Future<void> _respond(HttpRequest request, Object value) async {
    request.response.write(jsonEncode(value));
    await request.response.close();
  }
}
