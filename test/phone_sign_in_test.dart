import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/validation/phone_number.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';
import 'package:flutter_101repairshop/features/auth/presentation/phone_sign_in_screen.dart';

class _FakePhoneAuth extends AuthNotifier {
  _FakePhoneAuth()
    : this._(
        SupabaseClient(
          'http://127.0.0.1:54321',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  _FakePhoneAuth._(this.testClient) : super(supabase: testClient);

  final SupabaseClient testClient;
  final sentPhones = <String>[];
  final verifiedCodes = <(String, String)>[];
  Completer<void>? pendingSend;
  Completer<void>? pendingVerify;
  Object? sendError;
  Object? verifyError;

  @override
  Future<void> sendPhoneCode(String phone) async {
    sentPhones.add(phone);
    if (pendingSend != null) await pendingSend!.future;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<void> verifyPhoneCode({
    required String phone,
    required String code,
  }) async {
    verifiedCodes.add((phone, code));
    if (pendingVerify != null) await pendingVerify!.future;
    if (verifyError != null) throw verifyError!;
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(testClient.dispose());
  }
}

void main() {
  test('Philippine mobile formats normalize to the same E.164 number', () {
    for (final input in [
      '09123456789',
      '0912 345 6789',
      '9123456789',
      '639123456789',
      '+639123456789',
      ' +63 (912) 345-6789 ',
      '00639123456789',
    ]) {
      expect(PhoneNumber.normalize(input), '+639123456789', reason: input);
      expect(PhoneNumber.validate(input), isNull, reason: input);
    }
  });

  test('international numbers require an explicit country code', () {
    expect(PhoneNumber.normalize('+1 (415) 555-2671'), '+14155552671');
    expect(PhoneNumber.normalize('0044 7700 900123'), '+447700900123');
    expect(PhoneNumber.normalize('4155552671'), isNull);
    expect(PhoneNumber.normalize('+123456789012345'), '+123456789012345');
    expect(PhoneNumber.normalize('+1234567890123456'), isNull);
  });

  test('malformed inputs and unsupported local numbers are rejected', () {
    for (final input in [
      '',
      ' ',
      '0912',
      '08123456789',
      '+6309123456789',
      '+63281234567',
      '+63912345678',
      '+001234567890',
      '++639123456789',
      '+63 912 345 6789 ext 1',
      'call09123456789',
      '+639123456789/0',
    ]) {
      expect(PhoneNumber.normalize(input), isNull, reason: input);
      expect(PhoneNumber.validate(input), isNotNull, reason: input);
    }
    expect(PhoneNumber.validate(null), 'Enter your phone number');
  });

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  Finder action(String label) => find.widgetWithText(AppButton, label);

  Future<GoRouter> pumpForm(
    WidgetTester tester,
    _FakePhoneAuth auth, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/phone',
      routes: [
        GoRoute(path: '/phone', builder: (_, _) => const PhoneSignInScreen()),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Sign in destination')),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Account destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => auth)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
    addTearDown(() async {
      // Dispose the provider-owned resend timer and test client.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> requestCode(WidgetTester tester) async {
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '0912 345 6789');
    await tapVisible(tester, action('Send code'));
  }

  Finder countrySelector() =>
      find.byKey(const ValueKey('phone-country-selector'));

  Finder countrySearch() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Search country or code',
  );

  Future<void> chooseCountry(WidgetTester tester, String countryName) async {
    await tapVisible(tester, countrySelector());
    expect(countrySearch(), findsOneWidget);
    await tester.enterText(countrySearch(), countryName);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ListTile, countryName));
    expect(countrySearch(), findsNothing);
  }

  String phoneInput(WidgetTester tester) =>
      tester.widget<TextFormField>(field('Phone number')).controller!.text;

  testWidgets('Philippines is selected and its country code is automatic', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    expect(find.text('Country code'), findsOneWidget);
    expect(find.text('Philippines (+63)'), findsOneWidget);
    expect(find.text('+63 will be added automatically.'), findsNothing);
    expect(
      find.text('Use 09 in the Philippines, or +country code.'),
      findsNothing,
    );
    final input = tester.widget<AppTextField>(
      find.widgetWithText(AppTextField, 'Phone number'),
    );
    expect(input.hint, '912 345 6789');
    expect(tester.getSize(countrySelector()).height, greaterThanOrEqualTo(48));
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '912 345 6789');
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, ['+639123456789']);
    expect(field('Verification code'), findsOneWidget);
    expect(find.textContaining('+639123456789'), findsOneWidget);
    expect(countrySelector(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final input in [
    '0912 345 6789',
    '639123456789',
    '+63 (912) 345-6789',
    '00639123456789',
  ]) {
    testWidgets(
      'automatic country code never duplicates the prefix of $input',
      (tester) async {
        final auth = _FakePhoneAuth();
        await pumpForm(tester, auth);
        await tester.ensureVisible(field('Phone number'));
        await tester.enterText(field('Phone number'), input);
        await tester.pumpAndSettle();
        expect(find.text('Philippines (+63)'), findsOneWidget);
        await tapVisible(tester, action('Send code'));
        expect(auth.sentPhones, ['+639123456789']);
        expect(field('Verification code'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final example in [
    ('United States', '+1', '4155552671', '+14155552671'),
    ('United Kingdom', '+44', '07700900123', '+447700900123'),
  ]) {
    testWidgets('selecting ${example.$1} prefixes its national number', (
      tester,
    ) async {
      final auth = _FakePhoneAuth();
      await pumpForm(tester, auth);
      await chooseCountry(tester, example.$1);
      expect(find.text('${example.$1} (${example.$2})'), findsOneWidget);
      expect(
        find.text('${example.$2} will be added automatically.'),
        findsNothing,
      );
      await tester.ensureVisible(field('Phone number'));
      await tester.enterText(field('Phone number'), example.$3);
      await tapVisible(tester, action('Send code'));
      expect(auth.sentPhones, [example.$4]);
      expect(field('Verification code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing country retains already entered national digits', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '4155552671');
    await chooseCountry(tester, 'United States');
    expect(phoneInput(tester), '4155552671');
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, ['+14155552671']);
    expect(tester.takeException(), isNull);
  });

  for (final example in [
    ('+1 (415) 555-2671', 'United States (+1)', '4155552671', '+14155552671'),
    ('0044 7700 900123', 'United Kingdom (+44)', '7700900123', '+447700900123'),
    ('0063 912 345 6789', 'Philippines (+63)', '9123456789', '+639123456789'),
  ]) {
    testWidgets(
      'pasting ${example.$1} selects its country without a double prefix',
      (tester) async {
        final auth = _FakePhoneAuth();
        await pumpForm(tester, auth);
        await tester.ensureVisible(field('Phone number'));
        await tester.enterText(field('Phone number'), example.$1);
        await tester.pumpAndSettle();
        expect(find.text(example.$2), findsOneWidget);
        expect(phoneInput(tester), example.$3);
        await tapVisible(tester, action('Send code'));
        expect(auth.sentPhones, [example.$4]);
        expect(field('Verification code'), findsOneWidget);
        await tester.ensureVisible(field('Verification code'));
        await tester.enterText(field('Verification code'), '123456');
        await tapVisible(tester, action('Verify and sign in'));
        expect(auth.verifiedCodes, [(example.$4, '123456')]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'country search fits 320px at 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final auth = _FakePhoneAuth();
        await pumpForm(tester, auth, dark: dark);
        await tapVisible(tester, countrySelector());
        await tester.enterText(countrySearch(), '+39');
        await tester.pumpAndSettle();
        final italy = find.widgetWithText(ListTile, 'Italy');
        expect(italy, findsOneWidget);
        expect(
          find.descendant(of: italy, matching: find.text('+39')),
          findsOneWidget,
        );
        expect(tester.getSize(italy).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tapVisible(tester, italy);
        expect(find.text('Italy (+39)'), findsOneWidget);
        expect(find.text('+39 will be added automatically.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'country search stays usable with a 300px keyboard at 320px and 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final auth = _FakePhoneAuth();
        await pumpForm(tester, auth, dark: dark);
        await tapVisible(tester, countrySelector());
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tapVisible(tester, countrySearch());
        await tester.pumpAndSettle();
        final search = tester.widget<TextField>(countrySearch());
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: countrySearch(),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(search.keyboardType, isNot(TextInputType.phone));
        await tester.enterText(countrySearch(), '+39');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final italy = find.widgetWithText(ListTile, 'Italy');
        expect(italy, findsOneWidget);
        expect(tester.getSize(italy).height, greaterThanOrEqualTo(48));
        await tapVisible(tester, italy);
        expect(countrySearch(), findsNothing);
        expect(find.text('Italy (+39)'), findsOneWidget);
        expect(auth.sentPhones, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('country and number cannot change while SMS is being sent', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()..pendingSend = Completer<void>();
    await pumpForm(tester, auth);
    await requestCode(tester);
    expect(tester.widget<OutlinedButton>(countrySelector()).onPressed, isNull);
    expect(
      tester.widget<TextFormField>(field('Phone number')).enabled,
      isFalse,
    );
    await tapVisible(tester, countrySelector());
    expect(countrySearch(), findsNothing);
    expect(auth.sentPhones, ['+639123456789']);
    auth.pendingSend!.complete();
    await tester.pumpAndSettle();
    expect(field('Verification code'), findsOneWidget);
    expect(countrySelector(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic prefix does not send SMS for an incomplete number', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '912');
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, isEmpty);
    expect(field('Verification code'), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('Phone number'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(
      tester.state<FormFieldState<String>>(field('Phone number')).errorText,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'phone forms fit 320px at 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final auth = _FakePhoneAuth();
        await pumpForm(tester, auth, dark: dark);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await requestCode(tester);
        expect(field('Verification code'), findsOneWidget);
        expect(find.textContaining('+639123456789'), findsOneWidget);
        final editable = tester.widget<EditableText>(
          find.descendant(
            of: field('Verification code'),
            matching: find.byType(EditableText),
          ),
        );
        expect(editable.autofillHints, contains(AutofillHints.oneTimeCode));
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('phone validation focuses missing input without sending SMS', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    await tapVisible(tester, action('Send code'));
    expect(find.text('Enter your phone number'), findsOneWidget);
    expect(auth.sentPhones, isEmpty);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('Phone number'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending is guarded and normalizes the phone number', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()..pendingSend = Completer<void>();
    await pumpForm(tester, auth);
    await requestCode(tester);
    expect(auth.sentPhones, ['+639123456789']);
    expect(find.text('Sending code...'), findsOneWidget);
    final sendButton = find.byType(ElevatedButton);
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNull);
    await tester.tap(sendButton);
    await tester.pump();
    expect(auth.sentPhones, hasLength(1));
    auth.pendingSend!.complete();
    await tester.pumpAndSettle();
    expect(field('Verification code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cooldown survives changing number and leaving the phone route', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    final router = await pumpForm(tester, auth);
    await requestCode(tester);
    expect(find.text('Resend code in 60s'), findsOneWidget);
    await tapVisible(
      tester,
      find.widgetWithText(TextButton, 'Change phone number'),
    );
    expect(field('Phone number'), findsOneWidget);
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '09987654321');
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, hasLength(1));
    router.go('/login');
    await tester.pumpAndSettle();
    router.go('/phone');
    await tester.pumpAndSettle();
    await tester.ensureVisible(field('Phone number'));
    await tester.enterText(field('Phone number'), '09987654321');
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, hasLength(1));
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, ['+639123456789', '+639987654321']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired verification stays on the code form and can retry', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()
      ..verifyError = const AuthException(
        'Token has expired or is invalid',
        code: 'otp_expired',
      );
    final router = await pumpForm(tester, auth);
    await requestCode(tester);
    await tester.ensureVisible(field('Verification code'));
    await tester.enterText(field('Verification code'), '123456');
    await tapVisible(tester, action('Verify and sign in'));
    expect(
      find.text(
        'That code is incorrect or has expired. Check the latest SMS or request a new code.',
      ),
      findsOneWidget,
    );
    expect(field('Verification code'), findsOneWidget);
    expect(auth.verifiedCodes, [('+639123456789', '123456')]);
    auth.verifyError = null;
    await tester.ensureVisible(field('Verification code'));
    await tester.enterText(field('Verification code'), '87654321');
    await tapVisible(tester, action('Verify and sign in'));
    expect(auth.verifiedCodes, [
      ('+639123456789', '123456'),
      ('+639123456789', '87654321'),
    ]);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Account destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete verification is focused without contacting auth', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    await requestCode(tester);
    await tester.ensureVisible(field('Verification code'));
    await tester.enterText(field('Verification code'), '12345');
    await tapVisible(tester, action('Verify and sign in'));
    expect(auth.verifiedCodes, isEmpty);
    expect(
      find.text('Enter the complete verification code from your SMS'),
      findsOneWidget,
    );
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('Verification code'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  for (final identity in ['phone number', 'email']) {
    for (final verifying in [false, true]) {
      testWidgets(
        'duplicate $identity during ${verifying ? 'verification' : 'code sending'} explains how to use the existing account',
        (tester) async {
          final duplicate = AuthException(
            'This $identity is already associated with a customer account.',
            code: 'hook_error',
          );
          final auth = _FakePhoneAuth();
          if (verifying) {
            auth.verifyError = duplicate;
          } else {
            auth.sendError = duplicate;
          }
          final router = await pumpForm(tester, auth);
          await requestCode(tester);
          if (verifying) {
            await tester.ensureVisible(field('Verification code'));
            await tester.enterText(field('Verification code'), '123456');
            await tapVisible(tester, action('Verify and sign in'));
          }

          final expected = identity == 'phone number'
              ? 'This phone number is already linked to an account. Sign in to that account or contact the shop.'
              : 'This email is already linked to an account. Sign in or reset your password.';
          expect(find.text(expected).hitTestable(), findsOneWidget);
          expect(router.routeInformationProvider.value.uri.path, '/phone');
          expect(find.text('Account destination'), findsNothing);
          expect(
            field(verifying ? 'Verification code' : 'Phone number'),
            findsOneWidget,
          );

          // Failure leaves the form usable and retains its entered identity.
          if (verifying) {
            expect(auth.verifiedCodes, [('+639123456789', '123456')]);
            expect(
              tester
                  .widget<TextFormField>(field('Verification code'))
                  .controller!
                  .text,
              '123456',
            );
            auth.verifyError = null;
            await tapVisible(tester, action('Verify and sign in'));
            expect(router.routeInformationProvider.value.uri.path, '/');
          } else {
            expect(auth.sentPhones, ['+639123456789']);
            auth.sendError = null;
            await tapVisible(tester, action('Send code'));
            expect(auth.sentPhones, ['+639123456789', '+639123456789']);
            expect(field('Verification code'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('phone network failures keep connection feedback', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()
      ..sendError = TimeoutException('Request timeout');
    await pumpForm(tester, auth);
    await requestCode(tester);
    expect(
      find.text(
        'We could not connect. Check your internet connection and try again.',
      ),
      findsOneWidget,
    );
    expect(field('Phone number'), findsOneWidget);
    expect(field('Verification code'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unknown phone errors keep the sending and verification feedback',
    (tester) async {
      final auth = _FakePhoneAuth()
        ..sendError = const AuthException(
          'Unexpected auth rejection',
          code: 'unknown',
        );
      await pumpForm(tester, auth);
      await requestCode(tester);
      expect(
        find.text(
          'We could not send a code. Check your phone number and try again.',
        ),
        findsOneWidget,
      );
      auth.sendError = null;
      auth.verifyError = const AuthException(
        'Unexpected auth rejection',
        code: 'unknown',
      );
      await tapVisible(tester, action('Send code'));
      await tester.ensureVisible(field('Verification code'));
      await tester.enterText(field('Verification code'), '123456');
      await tapVisible(tester, action('Verify and sign in'));
      expect(
        find.text(
          'We could not verify that code. Check the latest SMS and try again.',
        ),
        findsOneWidget,
      );
      expect(field('Verification code'), findsOneWidget);
      expect(find.text('Unexpected auth rejection'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SMS configuration failures do not claim the device is offline', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()
      ..sendError = const AuthException(
        'Phone provider is disabled',
        code: 'phone_provider_disabled',
      );
    await pumpForm(tester, auth);
    await requestCode(tester);
    expect(
      find.text(
        'Phone sign-in is unavailable right now. Use email or Google, or try again later.',
      ),
      findsOneWidget,
    );
    expect(field('Phone number'), findsOneWidget);
    expect(field('Verification code'), findsNothing);
    expect(find.textContaining('internet connection'), findsNothing);
  });

  testWidgets('verification prevents duplicate submits while pending', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()..pendingVerify = Completer<void>();
    final router = await pumpForm(tester, auth);
    await requestCode(tester);
    await tester.ensureVisible(field('Verification code'));
    await tester.enterText(field('Verification code'), '123456');
    await tapVisible(tester, action('Verify and sign in'));
    expect(find.text('Verifying code...'), findsOneWidget);
    expect(auth.verifiedCodes, [('+639123456789', '123456')]);
    final verifyButton = find.byType(ElevatedButton);
    expect(tester.widget<ElevatedButton>(verifyButton).onPressed, isNull);
    await tester.tap(verifyButton);
    await tester.pump();
    expect(auth.verifiedCodes, hasLength(1));
    auth.pendingVerify!.complete();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('SMS rate limits disable sending for a full cooldown', (
    tester,
  ) async {
    final auth = _FakePhoneAuth()
      ..sendError = const AuthException(
        'Too many SMS requests',
        code: 'over_sms_send_rate_limit',
      );
    await pumpForm(tester, auth);
    await requestCode(tester);
    expect(
      find.text(
        'Too many requests. Wait a minute before requesting another code.',
      ),
      findsOneWidget,
    );
    expect(find.text('You can request another code in 60s.'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, hasLength(1));
    auth.sendError = null;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    await tapVisible(tester, action('Send code'));
    expect(auth.sentPhones, hasLength(2));
    expect(field('Verification code'), findsOneWidget);
  });

  testWidgets('resend failure preserves the code and current number', (
    tester,
  ) async {
    final auth = _FakePhoneAuth();
    await pumpForm(tester, auth);
    await requestCode(tester);
    await tester.ensureVisible(field('Verification code'));
    await tester.enterText(field('Verification code'), '123456');
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    auth.sendError = const AuthException(
      'SMS provider temporarily unavailable',
      code: 'sms_send_failed',
    );
    await tapVisible(tester, action('Resend code'));
    expect(field('Verification code'), findsOneWidget);
    expect(auth.sentPhones, ['+639123456789', '+639123456789']);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('Verification code'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, '123456');
    expect(find.textContaining('+639123456789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
