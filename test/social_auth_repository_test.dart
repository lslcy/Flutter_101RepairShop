import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';

void main() {
  late _PhoneAuthServer server;
  late SupabaseClient client;
  late AuthNotifier notifier;
  final flows = <AuthFlowController>[];

  AuthFlowController createFlow() {
    final flow = AuthFlowController(client);
    flows.add(flow);
    return flow;
  }

  void useGoogleLauncher(
    GoogleSignInLauncher launcher, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    notifier.dispose();
    notifier = AuthNotifier(
      supabase: client,
      authFlow: createFlow(),
      googleSignInLauncher: launcher,
      authRequestTimeout: timeout,
    );
  }

  setUp(() async {
    server = _PhoneAuthServer();
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
    notifier.dispose();
    for (final flow in flows) {
      flow.dispose();
    }
    flows.clear();
    await client.dispose();
    await server.close();
  });

  test('requesting an SMS code does not authenticate the customer', () async {
    await notifier.sendPhoneCode('  +639171234567  ');

    expect(server.otpBodies.single['phone'], '+639171234567');
    expect(server.otpBodies.single['create_user'], isTrue);
    expect(server.otpBodies.single['channel'], 'sms');
    expect(client.auth.currentSession, isNull);
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.valueOrNull, isNull);
    expect(server.customerReads, 0);
  });

  test(
    'phone numbers without an international prefix never reach auth',
    () async {
      for (final phone in [
        '09171234567',
        '+012345678',
        '+63917',
        '+63917abc4567',
      ]) {
        await expectLater(notifier.sendPhoneCode(phone), throwsArgumentError);
      }
      expect(server.otpBodies, isEmpty);
      expect(notifier.state.isLoading, isFalse);
    },
  );

  test(
    'malformed codes never reach verification or change auth state',
    () async {
      for (final code in ['12345', '12a456', '12345678901']) {
        await expectLater(
          notifier.verifyPhoneCode(phone: '+639171234567', code: code),
          throwsArgumentError,
        );
      }
      expect(server.verifyBodies, isEmpty);
      expect(notifier.state.isLoading, isFalse);
    },
  );

  test(
    'SMS verification starts the session and warms the customer lookup',
    () async {
      await notifier.verifyPhoneCode(
        phone: ' +639171234567 ',
        code: ' 123456 ',
      );

      expect(server.verifyBodies.single['phone'], '+639171234567');
      expect(server.verifyBodies.single['token'], '123456');
      expect(server.verifyBodies.single['type'], 'sms');
      expect(client.auth.currentUser?.id, 'phone-user-1');
      expect(notifier.state.valueOrNull?.id, 'phone-user-1');
      expect(notifier.state.isLoading, isFalse);
      expect(server.customerReads, 1);
    },
  );

  test('the server may configure an eight-digit verification code', () async {
    await notifier.verifyPhoneCode(phone: '+639171234567', code: '12345678');

    expect(server.verifyBodies.single['token'], '12345678');
    expect(client.auth.currentSession, isNotNull);
  });

  test('an expired code stops loading and can be retried', () async {
    server.verifyErrorCode = 'otp_expired';
    await expectLater(
      notifier.verifyPhoneCode(phone: '+639171234567', code: '123456'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'otp_expired',
        ),
      ),
    );
    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.hasError, isTrue);
    expect(client.auth.currentSession, isNull);
    expect(server.customerReads, 0);

    server.verifyErrorCode = null;
    await notifier.verifyPhoneCode(phone: '+639171234567', code: '654321');
    expect(notifier.state.valueOrNull?.id, 'phone-user-1');
    expect(notifier.state.hasError, isFalse);
  });

  test(
    'a stalled verification stops loading after its request timeout',
    () async {
      notifier.dispose();
      notifier = AuthNotifier(
        supabase: client,
        authRequestTimeout: const Duration(milliseconds: 150),
      );
      server.stallVerification = true;

      await expectLater(
        notifier.verifyPhoneCode(phone: '+639171234567', code: '123456'),
        throwsA(isA<TimeoutException>()),
      );
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.hasError, isTrue);
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'phone provider setup errors stay signed out without a loading state',
    () async {
      server.otpErrorCode = 'phone_provider_disabled';

      await expectLater(
        notifier.sendPhoneCode('+639171234567'),
        throwsA(isA<AuthException>()),
      );
      expect(notifier.state.isLoading, isFalse);
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'restored phone sessions are available immediately on a new app launch',
    () async {
      await notifier.verifyPhoneCode(phone: '+639171234567', code: '123456');
      final savedSession = jsonEncode(client.auth.currentSession!.toJson());
      final restartedClient = SupabaseClient(
        server.url,
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(restartedClient.dispose);
      await restartedClient.auth.setInitialSession(savedSession);
      final restartedNotifier = AuthNotifier(supabase: restartedClient);
      addTearDown(restartedNotifier.dispose);

      expect(restartedNotifier.state.valueOrNull?.id, 'phone-user-1');
      expect(restartedNotifier.state.isLoading, isFalse);
      // Loading an existing session never sends another SMS or verifies a code.
      expect(server.otpBodies, isEmpty);
      expect(server.verifyBodies, hasLength(1));
    },
  );

  test(
    'Google launch waits for an auth callback without claiming success',
    () async {
      String? actualRedirect;
      LaunchMode? actualMode;
      useGoogleLauncher(({required redirectTo, required launchMode}) async {
        actualRedirect = redirectTo;
        actualMode = launchMode;
        return true;
      });

      expect(await notifier.signInWithGoogle(), isTrue);
      expect(actualRedirect, 'com.repairshop101://auth/login-callback');
      expect(actualMode, LaunchMode.externalApplication);
      expect(notifier.authFlow!.isGoogleSignInPending, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(client.auth.currentSession, isNull);

      // Any successful sign-in event completes the pending browser flow.
      await notifier.verifyPhoneCode(phone: '+639171234567', code: '123456');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.authFlow!.isGoogleSignInPending, isFalse);
    },
  );

  test('a failed Google browser launch cancels the pending flow', () async {
    useGoogleLauncher(
      ({required redirectTo, required launchMode}) async => false,
    );

    expect(await notifier.signInWithGoogle(), isFalse);
    expect(notifier.authFlow!.isGoogleSignInPending, isFalse);
    expect(notifier.authFlow!.requiresRecovery, isFalse);
    expect(notifier.state.isLoading, isFalse);
  });

  test(
    'Google launch errors cancel the pending flow and remain retryable',
    () async {
      useGoogleLauncher(({required redirectTo, required launchMode}) async {
        throw const AuthException('Google provider disabled');
      });

      await expectLater(
        notifier.signInWithGoogle(),
        throwsA(isA<AuthException>()),
      );
      expect(notifier.authFlow!.isGoogleSignInPending, isFalse);
      expect(notifier.authFlow!.requiresRecovery, isFalse);
      expect(notifier.state.isLoading, isFalse);
    },
  );

  test(
    'a stalled Google launch expires without blocking other sign-in options',
    () async {
      useGoogleLauncher(
        ({required redirectTo, required launchMode}) =>
            Completer<bool>().future,
        timeout: const Duration(milliseconds: 150),
      );

      await expectLater(
        notifier.signInWithGoogle(),
        throwsA(isA<TimeoutException>()),
      );
      expect(notifier.authFlow!.isGoogleSignInPending, isFalse);
      expect(notifier.state.isLoading, isFalse);
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'the SDK Google URL uses PKCE and the separate sign-in callback',
    () async {
      final response = await client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: AuthRedirects.signIn(),
      );
      final uri = Uri.parse(response.url);

      expect(uri.path, '/auth/v1/authorize');
      expect(uri.queryParameters['provider'], 'google');
      expect(
        uri.queryParameters['redirect_to'],
        'com.repairshop101://auth/login-callback',
      );
      expect(uri.queryParameters['code_challenge'], isNotEmpty);
      expect(uri.queryParameters['code_challenge_method'], 's256');
      expect(server.otpBodies, isEmpty);
      expect(server.verifyBodies, isEmpty);
    },
  );
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

/// Auth requests go only to a loopback server: tests never send a real SMS.
class _PhoneAuthServer {
  late HttpServer _server;
  final otpBodies = <Map<String, dynamic>>[];
  final verifyBodies = <Map<String, dynamic>>[];
  int customerReads = 0;
  String? otpErrorCode;
  String? verifyErrorCode;
  bool stallVerification = false;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final rawBody = await utf8.decoder.bind(request).join();
    final body = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('x-supabase-api-version', '2024-01-01');
    if (request.uri.path == '/auth/v1/otp') {
      otpBodies.add(body);
      if (otpErrorCode != null) {
        _writeError(request, otpErrorCode!);
      } else {
        request.response.write('{}');
      }
    } else if (request.uri.path == '/auth/v1/verify') {
      verifyBodies.add(body);
      if (stallVerification) return;
      if (verifyErrorCode != null) {
        _writeError(request, verifyErrorCode!);
      } else {
        request.response.write(jsonEncode(_session()));
      }
    } else if (request.uri.path == '/rest/v1/customers') {
      customerReads++;
      request.response.write(
        jsonEncode([
          {'id': 'customer-1', 'auth_id': 'phone-user-1', 'deleted_at': null},
        ]),
      );
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('{}');
    }
    await request.response.close();
  }

  void _writeError(HttpRequest request, String code) {
    request.response.statusCode = HttpStatus.badRequest;
    request.response.write(
      jsonEncode({
        'code': code,
        'msg': code == 'otp_expired'
            ? 'Token has expired or is invalid'
            : 'Phone provider disabled',
      }),
    );
  }

  Map<String, dynamic> _session() {
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': 'phone-user-1', 'exp': expiry})))
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'phone-user-1',
        'aud': 'authenticated',
        'phone': '+639171234567',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {
          'provider': 'phone',
          'providers': ['phone'],
        },
        'user_metadata': <String, dynamic>{},
      },
    };
  }
}
