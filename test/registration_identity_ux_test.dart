import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';
import 'package:flutter_101repairshop/features/auth/presentation/register_screen.dart';

class _Registration extends AuthNotifier {
  _Registration(this.testClient) : super(supabase: testClient);

  final SupabaseClient testClient;
  final submitted = <Map<String, String?>>[];

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNo,
    required String address,
  }) async {
    submitted.add({
      'email': email,
      'password': password,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNo': phoneNo,
      'address': address,
    });
    throw const AuthException(
      'Account already exists',
      code: 'account_already_exists',
    );
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(testClient.dispose());
  }
}

void main() {
  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );
  Finder createButton() => find.widgetWithText(AppButton, 'Create account');

  Future<_Registration> pumpRegistration(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Registration(
      SupabaseClient(
        'http://127.0.0.1:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => auth)],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const RegisterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final target = field(label);
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  Future<void> fillRegistration(WidgetTester tester) async {
    await enterField(tester, 'First name', '  José   María  ');
    await enterField(tester, 'Last name', '  De la   Cruz  ');
    await enterField(
      tester,
      'Email address',
      '  JOSE.MARIA+Shop@EXAMPLE.COM  ',
    );
    await tapVisible(
      tester,
      find.widgetWithText(TextButton, 'Add phone number (optional)'),
    );
    await enterField(tester, 'Phone number (optional)', '0917 123 4567');
    await enterField(
      tester,
      'Address (required)',
      '12 Mabini Street, Davao City',
    );
    await enterField(tester, 'Password', 'Abcde1!f');
    await enterField(tester, 'Confirm password', 'Abcde1!f');
  }

  testWidgets('registration rejects invalid names before creating an account', (
    tester,
  ) async {
    final auth = await pumpRegistration(tester);
    await fillRegistration(tester);
    await enterField(tester, 'First name', 'Alex123😀');
    await tapVisible(tester, createButton());

    expect(auth.submitted, isEmpty);
    expect(
      find
          .text('Use letters, spaces, apostrophes, hyphens or periods')
          .hitTestable(),
      findsOneWidget,
    );
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('First name'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration validates optional numbers and focuses the number',
    (tester) async {
      final auth = await pumpRegistration(tester);
      await fillRegistration(tester);
      await enterField(tester, 'Phone number (optional)', '1234');
      await tapVisible(tester, createButton());

      expect(auth.submitted, isEmpty);
      expect(
        find.text('Enter a valid phone number').hitTestable(),
        findsOneWidget,
      );
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: field('Phone number (optional)'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration submits canonical identity and reports existing account',
    (tester) async {
      final auth = await pumpRegistration(tester);
      await fillRegistration(tester);
      await tapVisible(tester, createButton());

      expect(auth.submitted, [
        {
          'email': 'jose.maria+shop@example.com',
          'password': 'Abcde1!f',
          'firstName': 'José María',
          'lastName': 'De la Cruz',
          'phoneNo': '+639171234567',
          'address': '12 Mabini Street, Davao City',
        },
      ]);
      expect(find.textContaining('already').hitTestable(), findsOneWidget);
      expect(
        tester.widget<TextFormField>(field('First name')).controller!.text,
        '  José   María  ',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
