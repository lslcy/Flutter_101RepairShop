import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/services/customer_account_service.dart';

void main() {
  late _CustomerLookupServer server;
  late SupabaseClient client;

  setUp(() async {
    server = _CustomerLookupServer();
    await server.start();
    client = SupabaseClient(
      server.url,
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'customer@example.com',
      password: 'test-password',
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test('repositories share one in-flight lookup for the same user', () async {
    final firstService = CustomerAccountService(supabase: client);
    final secondService = CustomerAccountService(supabase: client);

    final first = firstService.resolveCurrentCustomer();
    final second = secondService.resolveCurrentCustomer();
    expect(identical(first, second), isTrue);

    final request = await server.customerRequest(0);
    expect(server.customerReads, 1);
    expect(request.uri.queryParameters, containsPair('auth_id', 'eq.user-1'));
    expect(request.uri.queryParameters, containsPair('deleted_at', 'is.null'));
    await server.respondCustomer(request, 'customer-1');

    expect((await first)?['id'], 'customer-1');
    expect((await second)?['id'], 'customer-1');

    // Completed lookups are not cached: a refresh reads the current row.
    final refreshed = firstService.resolveCurrentCustomer();
    final refreshRequest = await server.customerRequest(1);
    await server.respondCustomer(refreshRequest, 'customer-2');
    expect((await refreshed)?['id'], 'customer-2');
    expect(server.customerReads, 2);
  });

  test(
    'a stalled shared lookup expires and the next retry can succeed',
    () async {
      final service = CustomerAccountService(
        supabase: client,
        lookupTimeout: const Duration(milliseconds: 150),
      );
      final initial = service.resolveCurrentCustomer();
      final timeout = expectLater(initial, throwsA(isA<TimeoutException>()));
      final stalledRequest = await server.customerRequest(0);
      await timeout;

      final retryService = CustomerAccountService(
        supabase: client,
        lookupTimeout: const Duration(seconds: 3),
      );
      final retry = retryService.resolveCurrentCustomer();
      final retryRequest = await server.customerRequest(1);
      expect(identical(initial, retry), isFalse);
      expect(server.customerReads, 2);

      await server.respondCustomer(retryRequest, 'fresh-customer');
      expect((await retry)?['id'], 'fresh-customer');
      // Finish the old transport request without changing the retry result.
      await server.respondCustomer(stalledRequest, 'stale-customer');
      expect((await retry)?['id'], 'fresh-customer');
    },
  );

  test('a late old response leaves the new in-flight lookup shared', () async {
    final service = _ObservedCustomerAccountService(
      supabase: client,
      lookupTimeout: const Duration(milliseconds: 150),
    );
    final initial = service.resolveCurrentCustomer();
    final timeout = expectLater(initial, throwsA(isA<TimeoutException>()));
    final stalledRequest = await server.customerRequest(0);
    await timeout;

    final retryService = CustomerAccountService(
      supabase: client,
      lookupTimeout: const Duration(seconds: 3),
    );
    final retry = retryService.resolveCurrentCustomer();
    final retryRequest = await server.customerRequest(1);

    await server.respondCustomer(stalledRequest, 'stale-customer');
    // Wait until the old HTTP response actually reaches its underlying lookup.
    await service.lookupCompleted.future.timeout(const Duration(seconds: 3));
    final anotherRepository = CustomerAccountService(supabase: client);
    final sharedRetry = anotherRepository.resolveCurrentCustomer();
    expect(identical(sharedRetry, retry), isTrue);
    expect(server.customerReads, 2);

    await server.respondCustomer(retryRequest, 'fresh-customer');
    expect((await retry)?['id'], 'fresh-customer');
    expect((await sharedRetry)?['id'], 'fresh-customer');
  });

  test('signed-out lookups do not request a customer row', () async {
    final signedOut = SupabaseClient(
      server.url,
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(signedOut.dispose);

    expect(
      await CustomerAccountService(supabase: signedOut)
          .resolveCurrentCustomer(),
      isNull,
    );
    expect(server.customerReads, 0);
  });
}

/// Observes transport completion without replacing the real query or timeout.
class _ObservedCustomerAccountService extends CustomerAccountService {
  _ObservedCustomerAccountService({
    required super.supabase,
    required super.lookupTimeout,
  });

  final lookupCompleted = Completer<void>();

  @override
  Future<Map<String, dynamic>?> findActiveCustomer(
    String authId, {
    String columns = '*',
  }) async {
    try {
      return await super.findActiveCustomer(authId, columns: columns);
    } finally {
      lookupCompleted.complete();
    }
  }
}

/// Holds real local HTTP responses until each test chooses to release them.
class _CustomerLookupServer {
  late HttpServer _server;
  final _requests = <HttpRequest>[];
  final _arrivals = <int, Completer<HttpRequest>>{};

  String get url => 'http://127.0.0.1:${_server.port}';
  int get customerReads => _requests.length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<HttpRequest> customerRequest(int index) {
    if (index < _requests.length) return Future.value(_requests[index]);
    return (_arrivals[index] ??= Completer<HttpRequest>()).future.timeout(
      const Duration(seconds: 3),
    );
  }

  Future<void> respondCustomer(HttpRequest request, String id) async {
    request.response.write(
      jsonEncode([
        {'id': id, 'auth_id': 'user-1', 'deleted_at': null},
      ]),
    );
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/auth/v1/token') {
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'user-1', 'exp': expiry})))
          .replaceAll('=', '');
      request.response.write(
        jsonEncode({
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'user-1',
            'aud': 'authenticated',
            'email': 'customer@example.com',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
          },
        }),
      );
      await request.response.close();
      return;
    }
    if (request.uri.path == '/rest/v1/customers' && request.method == 'GET') {
      final index = _requests.length;
      _requests.add(request);
      _arrivals.remove(index)?.complete(request);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }
}
