import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_provider_settings.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';

void main() {
  late _SettingsServer server;

  AuthProviderSettings settings({
    Duration timeout = const Duration(seconds: 15),
  }) => AuthProviderSettings(
    endpoint: server.endpoint,
    publicKey: 'test-public-anon-key',
    requestTimeout: timeout,
  );

  setUp(() async {
    AuthCallbackTracker.latest = null;
    server = _SettingsServer();
    await server.start();
  });

  tearDown(() async {
    await server.close();
    AuthCallbackTracker.latest = null;
  });

  test(
    'Google preflight reads public settings with only the public key',
    () async {
      await settings().requireGoogleSignIn();

      expect(server.requests.single.method, 'GET');
      expect(server.requests.single.uri.path, '/auth/v1/settings');
      expect(server.apiKeys, ['test-public-anon-key']);
      expect(server.authorizations.single, isNull);
      expect(server.requests.single.uri.queryParameters, isEmpty);
    },
  );

  test(
    'a disabled Google provider returns a clear provider-disabled error',
    () async {
      server.googleEnabled = false;

      await expectLater(
        settings().requireGoogleSignIn(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'provider_disabled',
          ),
        ),
      );
    },
  );

  test(
    'disabled results are never cached when Google is enabled later',
    () async {
      final service = settings();
      server.googleEnabled = false;
      await expectLater(
        service.requireGoogleSignIn(),
        throwsA(isA<AuthException>()),
      );

      server.googleEnabled = true;
      await service.requireGoogleSignIn();
      expect(server.requests, hasLength(2));
    },
  );

  test(
    'enabled results are also refreshed before the next sign-in attempt',
    () async {
      final service = settings();
      await service.requireGoogleSignIn();
      server.googleEnabled = false;

      await expectLater(
        service.requireGoogleSignIn(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'provider_disabled',
          ),
        ),
      );
      expect(server.requests, hasLength(2));
    },
  );

  test('unexpected response status hides the server response body', () async {
    server.statusCode = HttpStatus.serviceUnavailable;
    server.responseBody = '{"private_diagnostic":"must-not-appear"}';

    await expectLater(
      settings().requireGoogleSignIn(),
      throwsA(
        isA<AuthException>()
            .having((error) => error.code, 'code', 'provider_unavailable')
            .having(
              (error) => error.message,
              'safe message',
              isNot(contains('must-not-appear')),
            ),
      ),
    );
  });

  for (final body in [
    'not-json-private-diagnostic',
    '[]',
    '{}',
    '{"external":null}',
    '{"external":{"google":"true"}}',
    '{"external":{"email":true}}',
  ]) {
    test('malformed settings fail safely: $body', () async {
      server.responseBody = body;

      await expectLater(
        settings().requireGoogleSignIn(),
        throwsA(
          isA<AuthException>()
              .having((error) => error.code, 'code', 'provider_unavailable')
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('private-diagnostic')),
              ),
        ),
      );
    });
  }

  test(
    'a stalled preflight times out and the next request can succeed',
    () async {
      server.holdResponses = true;
      final service = settings(timeout: const Duration(milliseconds: 150));

      await expectLater(
        service.requireGoogleSignIn(),
        throwsA(isA<TimeoutException>()),
      );
      server.holdResponses = false;
      await service.requireGoogleSignIn();
      expect(server.requests, hasLength(2));
    },
  );

  test(
    'network errors propagate and injected HTTP clients stay open',
    () async {
      final client = _TrackingClient((request) async {
        throw http.ClientException('Simulated offline connection', request.url);
      });
      addTearDown(client.close);
      final service = AuthProviderSettings(
        endpoint: server.endpoint,
        publicKey: 'test-public-anon-key',
        httpClient: client,
      );

      await expectLater(
        service.requireGoogleSignIn(),
        throwsA(isA<http.ClientException>()),
      );
      expect(client.wasClosed, isFalse);
    },
  );

  test(
    'an injected HTTP client stays open after provider failure and retry',
    () async {
      var enabled = false;
      final client = _TrackingClient(
        (request) async => http.Response(
          jsonEncode({
            'external': {'google': enabled},
          }),
          200,
        ),
      );
      addTearDown(client.close);
      final service = AuthProviderSettings(
        endpoint: server.endpoint,
        publicKey: 'test-public-anon-key',
        httpClient: client,
      );
      await expectLater(
        service.requireGoogleSignIn(),
        throwsA(isA<AuthException>()),
      );
      expect(client.wasClosed, isFalse);

      enabled = true;
      await service.requireGoogleSignIn();
      expect(client.wasClosed, isFalse);
    },
  );

  test(
    'disabled Google never opens the browser or leaves pending sign-in',
    () async {
      server.googleEnabled = false;
      final supabase = SupabaseClient(
        server.baseUrl,
        'test-public-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final flow = AuthFlowController(supabase);
      var browserLaunches = 0;
      final notifier = AuthNotifier(
        supabase: supabase,
        authFlow: flow,
        providerSettings: settings(),
        googleSignInLauncher:
            ({required redirectTo, required launchMode}) async {
              browserLaunches++;
              return true;
            },
      );
      addTearDown(() async {
        notifier.dispose();
        flow.dispose();
        await supabase.dispose();
      });

      await expectLater(
        notifier.signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'provider_disabled',
          ),
        ),
      );
      expect(browserLaunches, 0);
      expect(flow.isGoogleSignInPending, isFalse);
      expect(AuthCallbackTracker.latest, isNull);
      expect(flow.requiresRecovery, isFalse);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.valueOrNull, isNull);
    },
  );

  test(
    'cancelled sign-in never opens Google after a delayed preflight',
    () async {
      server.holdResponses = true;
      final supabase = SupabaseClient(
        server.baseUrl,
        'test-public-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final flow = AuthFlowController(supabase);
      var browserLaunches = 0;
      final notifier = AuthNotifier(
        supabase: supabase,
        authFlow: flow,
        providerSettings: settings(),
        googleSignInLauncher:
            ({required redirectTo, required launchMode}) async {
              browserLaunches++;
              return true;
            },
      );
      addTearDown(() async {
        notifier.dispose();
        flow.dispose();
        await supabase.dispose();
      });

      final signingIn = notifier.signInWithGoogle();
      final request = await server.firstRequest.future.timeout(
        const Duration(seconds: 3),
      );
      expect(flow.isGoogleSignInPending, isTrue);
      flow.cancelGoogleSignIn();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'external': {'google': true},
        }),
      );
      await request.response.close();

      expect(await signingIn, isFalse);
      expect(browserLaunches, 0);
      expect(flow.isGoogleSignInPending, isFalse);
      expect(AuthCallbackTracker.latest, isNull);
      expect(supabase.auth.currentSession, isNull);
    },
  );
  test(
    'enabled Google can launch only after its settings are checked',
    () async {
      final supabase = SupabaseClient(
        server.baseUrl,
        'test-public-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final flow = AuthFlowController(supabase);
      var browserLaunches = 0;
      final notifier = AuthNotifier(
        supabase: supabase,
        authFlow: flow,
        providerSettings: settings(),
        googleSignInLauncher:
            ({required redirectTo, required launchMode}) async {
              expect(server.requests, hasLength(1));
              browserLaunches++;
              return true;
            },
      );
      addTearDown(() async {
        notifier.dispose();
        flow.dispose();
        await supabase.dispose();
      });

      expect(await notifier.signInWithGoogle(), isTrue);
      expect(browserLaunches, 1);
      expect(flow.isGoogleSignInPending, isTrue);
      expect(supabase.auth.currentSession, isNull);
      expect(notifier.state.isLoading, isFalse);
    },
  );
}

class _TrackingClient extends MockClient {
  _TrackingClient(super.handler);
  bool wasClosed = false;

  @override
  void close() {
    wasClosed = true;
    super.close();
  }
}

/// Public auth configuration is served on loopback without external requests.
class _SettingsServer {
  late HttpServer _server;
  bool googleEnabled = true;
  int statusCode = HttpStatus.ok;
  String? responseBody;
  bool holdResponses = false;
  final requests = <HttpRequest>[];
  final firstRequest = Completer<HttpRequest>();
  final apiKeys = <String?>[];
  final authorizations = <String?>[];

  String get baseUrl => 'http://127.0.0.1:${_server.port}';
  Uri get endpoint => Uri.parse('$baseUrl/auth/v1/settings');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    await utf8.decoder.bind(request).join();
    requests.add(request);
    if (!firstRequest.isCompleted) firstRequest.complete(request);
    apiKeys.add(request.headers.value('apikey'));
    authorizations.add(request.headers.value(HttpHeaders.authorizationHeader));
    if (holdResponses) return;
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      responseBody ??
          jsonEncode({
            'external': {'google': googleEnabled},
          }),
    );
    await request.response.close();
  }
}
