import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/utils/account_errors.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';
import 'package:flutter_101repairshop/features/auth/data/sign_in_profile_service.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';

void main() {
  late _IdentityServer server;
  late SupabaseClient client;
  late _PkceStorage storage;
  late AuthFlowController flow;
  late AuthNotifier notifier;

  Future<bool> register({
    String email = 'alex@example.com',
    String firstName = 'Alex',
    String lastName = 'Reyes',
    String? phoneNo,
  }) => notifier.signUp(
    email: email,
    password: 'Abcde1!f',
    firstName: firstName,
    lastName: lastName,
    phoneNo: phoneNo,
    address: '  10 Mabini Street\nDavao City  ',
  );

  Future<void> authenticate() => notifier.signIn('alex@example.com', 'oldpass');

  Customer customer({
    String? email,
    String? phone,
    String firstName = 'Alex',
  }) => Customer(
    id: 'customer-1',
    firstName: firstName,
    lastName: 'Reyes',
    email: email,
    phoneNo: phone,
    address: '  10 Mabini Street\nDavao City  ',
  );

  setUp(() async {
    server = _IdentityServer();
    await server.start();
    storage = _PkceStorage();
    client = SupabaseClient(
      server.url,
      'test-anon-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
      ),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    flow = AuthFlowController(client);
    notifier = AuthNotifier(supabase: client, authFlow: flow);
  });

  tearDown(() async {
    notifier.dispose();
    flow.dispose();
    await client.dispose();
    await server.close();
  });

  test('signup normalizes names, email and phone before the request', () async {
    expect(
      await register(
        email: '  ALEX@Example.COM  ',
        firstName: '  Alex   Maria  ',
        lastName: "  O'Reyes-Santos  ",
        phoneNo: '0917 123 4567',
      ),
      isTrue,
    );
    final body = server.signupBodies.single;
    expect(body['email'], 'alex@example.com');
    expect(body['data'], {
      'first_name': 'Alex Maria',
      'last_name': "O'Reyes-Santos",
      'phone_no': '+639171234567',
      'address': '10 Mabini Street\nDavao City',
    });
    expect(client.auth.currentSession, isNull);
    expect(server.customerReads, 0);
    expect(flow.isRegistering, isFalse);
  });

  test('a blank optional phone is saved as null', () async {
    await register(phoneNo: '   ');
    expect(server.signupBodies.single['data']['phone_no'], isNull);
  });

  for (final entry in <String, String>{
    'numeric name': 'Alex123',
    'markup name': '<script>',
    'emoji name': 'Alex😀',
    'control characters': 'Alex\nMaria',
  }.entries) {
    test('${entry.key} is rejected before signup or auth loading', () async {
      await expectLater(register(firstName: entry.value), throwsArgumentError);
      expect(server.signupBodies, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      expect(flow.isRegistering, isFalse);
    });
  }

  test('malformed contacts are rejected before signup', () async {
    await expectLater(
      register(email: 'alex@@example.com'),
      throwsArgumentError,
    );
    await expectLater(register(phoneNo: '0917-nope'), throwsArgumentError);
    expect(server.signupBodies, isEmpty);
    expect(notifier.state.isLoading, isFalse);
  });

  test(
    'the concealed duplicate signup response is treated as a failure',
    () async {
      server.duplicateSignup = true;
      await expectLater(
        register(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.code,
            'code',
            'account_already_exists',
          ),
        ),
      );
      expect(notifier.state.hasError, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(flow.isRegistering, isFalse);
      expect(client.auth.currentSession, isNull);
      expect(server.logoutCalls, 0);
      expect(server.customerReads, 0);
    },
  );

  test('signup cannot replace or sign out an existing account', () async {
    await authenticate();
    final previous = client.auth.currentSession!.accessToken;
    await expectLater(register(), throwsA(isA<AuthException>()));
    expect(client.auth.currentSession!.accessToken, previous);
    expect(client.auth.currentUser?.id, 'user-1');
    expect(server.signupBodies, isEmpty);
    expect(server.logoutCalls, 0);
    expect(notifier.state.valueOrNull?.id, 'user-1');
  });

  test('a successful unconfirmed signup never calls sign-out', () async {
    expect(await register(), isTrue);
    expect(server.logoutCalls, 0);
    expect(notifier.state.isLoading, isFalse);
  });

  test(
    'a signup-created session is signed out after its profile lookup',
    () async {
      server.signupCreatesSession = true;
      expect(await register(), isFalse);
      expect(server.customerReads, 1);
      expect(server.logoutCalls, 1);
      expect(client.auth.currentSession, isNull);
      expect(flow.isRegistering, isFalse);
    },
  );

  test(
    'generic storage failure settles loading and registration state',
    () async {
      storage.rejectWrites = true;
      await expectLater(register(), throwsStateError);
      expect(notifier.state.hasError, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(flow.isRegistering, isFalse);
      expect(server.signupBodies, isEmpty);
      storage.rejectWrites = false;
      expect(await register(), isTrue);
      expect(notifier.state.hasError, isFalse);
    },
  );

  test(
    'sign-in and reset use canonical emails without changing old passwords',
    () async {
      await notifier.signIn('  ALEX@Example.COM  ', 'oldpass');
      await notifier.resetPassword('  ALEX@Example.COM  ');
      expect(server.signInBodies.single['email'], 'alex@example.com');
      expect(server.signInBodies.single['password'], 'oldpass');
      expect(server.resetBodies.single['email'], 'alex@example.com');
    },
  );

  test(
    'profile save normalizes contacts and only targets the signed-in customer',
    () async {
      await authenticate();
      await CustomerRepository(supabase: client).updateProfile(
        customer(
          firstName: '  Alex   Maria  ',
          email: '  ALEX@Example.COM ',
          phone: '0917 123 4567',
        ),
      );
      final patch = server.profileBodies.single;
      expect(patch['first_name'], 'Alex Maria');
      expect(patch['email'], 'alex@example.com');
      expect(patch['phone_no'], '+639171234567');
      expect(patch['address'], '10 Mabini Street\nDavao City');
      expect(server.profileQueries.single['id'], 'eq.customer-1');
      expect(server.profileQueries.single['auth_id'], 'eq.user-1');
      expect(server.profileQueries.single['deleted_at'], 'is.null');
    },
  );

  test(
    'phone-only profiles keep a null email and validate names on save',
    () async {
      await authenticate();
      final repository = CustomerRepository(supabase: client);
      await expectLater(
        repository.updateProfile(customer(firstName: 'Alex22')),
        throwsArgumentError,
      );
      expect(server.profileBodies, isEmpty);
      await repository.updateProfile(customer(phone: '+639171234567'));
      expect(server.profileBodies.single['email'], isNull);
    },
  );

  test(
    'duplicate contact saves cannot report success or expose another account',
    () async {
      await authenticate();
      server.profileFailure = 'customers_phone_identity_unique';
      Object? failure;
      try {
        await CustomerRepository(supabase: client)
            .updateProfile(customer(phone: '+639171234567'));
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<PostgrestException>());
      final message = friendlyAccountError(failure!);
      expect(message, contains('phone number is already linked'));
      expect(message, isNot(contains('other-customer@example.com')));
      expect(message, isNot(contains('23505')));
    },
  );

  test(
    'external profile completion filters names and normalizes spacing',
    () async {
      await authenticate();
      final profiles = SignInProfileService(client);
      await expectLater(
        profiles.complete(
          firstName: 'Alex1',
          lastName: 'Reyes',
          address: 'Davao',
        ),
        throwsArgumentError,
      );
      expect(server.rpcBodies, isEmpty);
      await profiles.complete(
        firstName: '  Alex   Maria  ',
        lastName: '  Reyes  ',
        address: '  Davao City  ',
      );
      expect(server.rpcBodies.single, {
        'p_first_name': 'Alex Maria',
        'p_last_name': 'Reyes',
        'p_address': 'Davao City',
      });
    },
  );

  test('duplicate email and customer identity errors use actionable fixed messages', () {
    final emailError = PostgrestException(
      code: '23505',
      message: 'customers_email_identity_unique',
      details: 'other-customer@example.com',
    );
    expect(
      friendlyAccountError(emailError),
      contains('email is already linked'),
    );
    expect(friendlyAccountError(emailError), isNot(contains('other-customer')));
    final profileError = PostgrestException(
      code: '23505',
      message: 'customers_auth_id_unique',
    );
    expect(friendlyAccountError(profileError), contains('customer profile'));
    expect(
      friendlyAccountError(
        const AuthException(
          'Database error saving new user',
          code: 'unexpected_failure',
        ),
      ),
      contains('contact the shop'),
    );
  });
}

class _PkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  bool rejectWrites = false;

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    if (rejectWrites) throw StateError('Simulated unavailable local storage');
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

/// All requests use loopback and fictitious identities, with no external effects.
class _IdentityServer {
  late HttpServer _server;
  final signupBodies = <Map<String, dynamic>>[];
  final signInBodies = <Map<String, dynamic>>[];
  final resetBodies = <Map<String, dynamic>>[];
  final profileBodies = <Map<String, dynamic>>[];
  final profileQueries = <Map<String, String>>[];
  final rpcBodies = <Map<String, dynamic>>[];
  bool duplicateSignup = false;
  bool signupCreatesSession = false;
  String? profileFailure;
  int customerReads = 0;
  int logoutCalls = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  Map<String, dynamic> get user => {
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'alex@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {
      'provider': 'email',
      'providers': ['email'],
    },
    'user_metadata': <String, dynamic>{},
    'identities': duplicateSignup
        ? []
        : [
            {
              'id': 'user-1',
              'identity_id': 'identity-1',
              'user_id': 'user-1',
              'provider': 'email',
              'identity_data': {'email': 'alex@example.com'},
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          ],
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

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = raw.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('x-supabase-api-version', '2024-01-01');
    switch ('${request.method} ${request.uri.path}') {
      case 'POST /auth/v1/signup':
        signupBodies.add(body);
        request.response.write(
          jsonEncode(signupCreatesSession ? session : user),
        );
      case 'POST /auth/v1/token':
        signInBodies.add(body);
        request.response.write(jsonEncode(session));
      case 'POST /auth/v1/recover':
        resetBodies.add(body);
        request.response.write('{}');
      case 'POST /auth/v1/logout':
        logoutCalls++;
        request.response.statusCode = HttpStatus.noContent;
      case 'GET /rest/v1/customers':
        customerReads++;
        request.response.write(
          jsonEncode([
            {'id': 'customer-1', 'auth_id': 'user-1', 'deleted_at': null},
          ]),
        );
      case 'PATCH /rest/v1/customers':
        profileBodies.add(body);
        profileQueries.add(request.uri.queryParameters);
        if (profileFailure == null) {
          request.response.write('[{"id":"customer-1"}]');
        } else {
          request.response.statusCode = HttpStatus.conflict;
          request.response.write(
            jsonEncode({
              'code': '23505',
              'message': 'duplicate key violates constraint "$profileFailure"',
              'details': 'other-customer@example.com',
            }),
          );
        }
      case 'POST /rest/v1/rpc/complete_customer_profile':
        rpcBodies.add(body);
        request.response.write(jsonEncode('customer-1'));
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
    }
    await request.response.close();
  }
}
