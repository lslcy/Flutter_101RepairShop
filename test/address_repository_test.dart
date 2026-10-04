import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';

void main() {
  late _CustomerServer server;
  late SupabaseClient client;
  late CustomerRepository repository;

  setUp(() async {
    server = _CustomerServer();
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
    repository = CustomerRepository(supabase: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test(
    'adding an appliance without a signed-in profile cannot report success',
    () async {
      final signedOut = SupabaseClient(
        server.url,
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(signedOut.dispose);
      await expectLater(
        CustomerRepository(supabase: signedOut)
            .addAppliance({'brand': 'LG', 'product': 'Fan'}),
        throwsA(isA<StateError>()),
      );
    },
  );
  test(
    'registration address persists after sign-in and imports only once',
    () async {
      final customer = await repository.getCurrentCustomer();

      expect(customer?.address, '123 Mabini Street\nBarangay 1, Davao City');
      expect(server.row['address'], customer?.address);
      expect(server.lastPatchQuery, containsPair('address', 'is.null'));
      expect(server.lastPatchQuery, containsPair('auth_id', 'eq.user-1'));
      expect(server.lastPatchQuery, containsPair('id', 'eq.customer-1'));

      await repository.getCurrentCustomer();
      expect(server.patchCount, 1);
    },
  );

  test(
    'an existing address remains authoritative over signup metadata',
    () async {
      server.row['address'] = '456 New Street';

      expect(
        (await repository.getCurrentCustomer())?.address,
        '456 New Street',
      );
      expect(server.patchCount, 0);
    },
  );

  test('a legacy cleared address is never restored from metadata', () async {
    server.row['address'] = '';

    expect((await repository.getCurrentCustomer())?.address, '');
    expect(server.patchCount, 0);
  });

  test('a silently denied registration address write is reported', () async {
    server.silentlyRejectPatch = true;
    await expectLater(
      repository.getCurrentCustomer(),
      throwsA(isA<StateError>()),
    );
    expect(server.row['address'], isNull);
  });

  test('a silently denied profile save does not report success', () async {
    server.silentlyRejectPatch = true;
    await expectLater(
      repository.updateProfile(
        Customer(id: 'customer-1', address: 'New address'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(server.row['address'], isNull);
  });
  test('blank signup metadata causes no database write', () async {
    server.signupAddress = '  ';
    await client.auth.signInWithPassword(
      email: 'customer@example.com',
      password: 'test-password',
    );

    expect((await repository.getCurrentCustomer())?.address, isNull);
    expect(server.patchCount, 0);
  });

  test('a concurrent address clear is preserved and returned', () async {
    server.beforePatch = () => server.row['address'] = '';

    expect((await repository.getCurrentCustomer())?.address, '');
    expect(server.row['address'], '');
    expect(server.patchCount, 1);
    expect(server.readCount, 2);
  });

  test('failed address persistence is surfaced and can be retried', () async {
    server.rejectPatch = true;
    await expectLater(
      repository.getCurrentCustomer(),
      throwsA(isA<PostgrestException>()),
    );
    expect(server.row['address'], isNull);

    server.rejectPatch = false;
    final customer = await repository.getCurrentCustomer();
    expect(customer?.address, '123 Mabini Street\nBarangay 1, Davao City');
  });

  for (final address in <String?>[null, '', '  \n  ']) {
    test('saving a missing or blank address is rejected: $address', () async {
      server.row['address'] = 'Existing saved address';
      await expectLater(
        repository.updateProfile(Customer(id: 'customer-1', address: address)),
        throwsA(isA<ArgumentError>()),
      );
      expect(server.row['address'], 'Existing saved address');
      expect(server.patchCount, 0);
    });
  }
  test(
    'saving a multiline address preserves its lines and trims edges',
    () async {
      await repository.updateProfile(
        Customer(
          id: 'customer-1',
          address: '  10 Rizal Street\nDavao City 8000  ',
        ),
      );

      expect(server.row['address'], '10 Rizal Street\nDavao City 8000');
      expect(
        (await repository.getCurrentCustomer())?.address,
        '10 Rizal Street\nDavao City 8000',
      );
      expect(server.patchCount, 1);
    },
  );
}

// Exercises the real Supabase query builders against a deterministic local API.
class _CustomerServer {
  late HttpServer _server;
  final row = <String, dynamic>{
    'id': 'customer-1',
    'auth_id': 'user-1',
    'first_name': 'Ari',
    'address': null,
  };
  String signupAddress = '  123 Mabini Street\nBarangay 1, Davao City  ';
  bool rejectPatch = false;
  bool silentlyRejectPatch = false;
  void Function()? beforePatch;
  int patchCount = 0;
  int readCount = 0;
  Map<String, String>? lastPatchQuery;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/auth/v1/token') {
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'user-1', 'exp': expiry})))
          .replaceAll('=', '');
      await _respond(request, {
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
          'user_metadata': {'address': signupAddress},
        },
      });
      return;
    }
    if (request.uri.path != '/rest/v1/customers') {
      request.response.statusCode = HttpStatus.notFound;
      await _respond(request, {'message': 'Unknown test route'});
      return;
    }
    if (request.method == 'GET') {
      readCount++;
      await _respond(request, [row]);
      return;
    }
    if (request.method == 'PATCH') {
      patchCount++;
      lastPatchQuery = request.uri.queryParameters;
      if (rejectPatch) {
        request.response.statusCode = HttpStatus.forbidden;
        await _respond(request, {
          'code': '42501',
          'message': 'Write rejected',
          'details': null,
          'hint': null,
        });
        return;
      }
      if (silentlyRejectPatch) {
        await _respond(request, <Object>[]);
        return;
      }
      beforePatch?.call();
      if (request.uri.queryParameters['address'] == 'is.null' &&
          row['address'] != null) {
        await _respond(request, <Object>[]);
        return;
      }
      row.addAll(jsonDecode(body) as Map<String, dynamic>);
      if (request.uri.queryParameters.containsKey('select')) {
        await _respond(request, [row]);
      } else {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      }
      return;
    }
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await _respond(request, {'message': 'Unexpected method'});
  }

  Future<void> _respond(HttpRequest request, Object value) async {
    request.response.write(jsonEncode(value));
    await request.response.close();
  }
}
