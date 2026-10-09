import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';

void main() {
  late _BookingServer server;
  late SupabaseClient client;
  late AppointmentsRepository repository;

  setUp(() async {
    server = _BookingServer();
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
    repository = AppointmentsRepository(supabase: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  const booking = <String, dynamic>{'title': 'Broken fan', 'status': 'Pending'};

  for (final address in <String?>[null, '', '  \n  ']) {
    test(
      'booking rejects missing or blank persisted address: $address',
      () async {
        server.customer!['address'] = address;

        await expectLater(
          repository.bookAppointment(booking),
          throwsA(isA<AppointmentAddressRequiredException>()),
        );

        expect(server.bookings, isEmpty);
        expect(server.lastCustomerQuery, containsPair('select', 'id,address'));
        expect(server.lastCustomerQuery, containsPair('auth_id', 'eq.user-1'));
      },
    );
  }

  test('booking requires an existing customer profile', () async {
    server.customer = null;

    await expectLater(
      repository.bookAppointment(booking),
      throwsA(isA<StateError>()),
    );
    expect(server.bookings, isEmpty);
  });

  test(
    'booking uses the authenticated customer with a persisted address',
    () async {
      final insertedId = await repository.bookAppointment({
        ...booking,
        'customer_id': 'other-user',
      });

      expect(server.bookings, [
        {...booking, 'customer_id': 'customer-1'},
      ]);
      expect(insertedId, 1);
    },
  );

  for (final minutes in [-1, 0, 10081, 1.5, '15']) {
    test('booking rejects invalid reminder leadtime $minutes', () async {
      await expectLater(
        repository.bookAppointment({
          ...booking,
          'reminder_minutes': minutes,
          'appointment_date': '2099-10-11',
          'time_slot': '8:00 AM - 9:00 AM',
        }),
        throwsA(isA<StateError>()),
      );
      expect(server.bookings, isEmpty);
    });
  }

  test('booking does not default a malformed reminder slot to 8 AM', () async {
    await expectLater(
      repository.bookAppointment({
        ...booking,
        'reminder_minutes': 15,
        'appointment_date': '2099-10-11',
        'time_slot': '13:60 PM',
      }),
      throwsA(isA<StateError>()),
    );
    expect(server.bookings, isEmpty);
  });

  test('booking persists a valid customer-selected reminder', () async {
    final data = {
      ...booking,
      'reminder_minutes': 15,
      'appointment_date': '2099-10-11',
      'time_slot': '8:00 AM - 9:00 AM',
    };
    await repository.bookAppointment(data);
    expect(server.bookings.single['reminder_minutes'], 15);
  });
  test('each booking rechecks the current stored address', () async {
    expect(await repository.bookAppointment(booking), 1);
    server.customer!['address'] = '';

    await expectLater(
      repository.bookAppointment(booking),
      throwsA(isA<AppointmentAddressRequiredException>()),
    );

    expect(server.customerReads, 2);
    expect(server.bookings, hasLength(1));
  });
}

class _BookingServer {
  late HttpServer _server;
  Map<String, dynamic>? customer = {
    'id': 'customer-1',
    'address': '123 Mabini Street, Davao City',
  };
  final bookings = <Map<String, dynamic>>[];
  Map<String, String>? lastCustomerQuery;
  int customerReads = 0;

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
          'user_metadata': <String, dynamic>{},
        },
      });
      return;
    }
    if (request.uri.path == '/rest/v1/customers' && request.method == 'GET') {
      customerReads++;
      lastCustomerQuery = request.uri.queryParameters;
      await _respond(request, [if (customer != null) customer]);
      return;
    }
    if (request.uri.path == '/rest/v1/appointments' &&
        request.method == 'POST') {
      bookings.add(jsonDecode(body) as Map<String, dynamic>);
      request.response.statusCode = HttpStatus.created;
      await _respond(request, [
        {'id': bookings.length},
      ]);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await _respond(request, {'message': 'Unknown test route'});
  }

  Future<void> _respond(HttpRequest request, Object value) async {
    request.response.write(jsonEncode(value));
    await request.response.close();
  }
}
