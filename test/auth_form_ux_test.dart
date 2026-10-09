import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/validation/password_policy.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/core/widgets/password_requirements.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter_101repairshop/features/auth/presentation/login_screen.dart';
import 'package:flutter_101repairshop/features/auth/presentation/register_screen.dart';

void main() {
  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  Future<void> pumpForm(
    WidgetTester tester,
    Widget screen, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authFlowProvider.overrideWith((ref) {
            final client = SupabaseClient(
              'http://127.0.0.1:54321',
              'test-anon-key',
              authOptions: const AuthClientOptions(autoRefreshToken: false),
            );
            ref.onDispose(() => unawaited(client.dispose()));
            return AuthFlowController(client);
          }),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    // Let validation and the focused field finish resizing before scrolling.
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void expectFieldFocused(WidgetTester tester, Finder target) {
    final editable = tester.widget<EditableText>(
      find.descendant(of: target, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  }

  void expectFieldVisible(WidgetTester tester, Finder target) {
    final rect = tester.getRect(target);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.top, lessThan(568));
    expect(rect.bottom, greaterThan(kToolbarHeight));
  }

  for (final dark in [false, true]) {
    testWidgets(
      'auth forms fit a 320px screen at 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        for (final screen in <Widget>[
          const LoginScreen(),
          const RegisterScreen(),
          const ForgotPasswordScreen(),
        ]) {
          await pumpForm(tester, screen, dark: dark);
          final scrollable = find.byType(SingleChildScrollView);
          expect(scrollable, findsOneWidget);
          await tester.drag(scrollable, const Offset(0, -4000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('login reveals and focuses the first invalid field', (
    tester,
  ) async {
    await pumpForm(tester, const LoginScreen());
    await tapVisible(tester, find.text('Sign in'));

    expect(find.text('Enter your email address'), findsOneWidget);
    expectFieldFocused(tester, field('Email address'));
    expectFieldVisible(tester, field('Email address'));

    await tester.enterText(field('Email address'), 'alex@example.com');
    await tapVisible(tester, find.text('Sign in'));
    expectFieldFocused(tester, field('Password'));
    expectFieldVisible(tester, field('Password'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'login next action moves to password and links have touch targets',
    (tester) async {
      await pumpForm(tester, const LoginScreen());
      await tester.ensureVisible(field('Email address'));
      await tester.enterText(field('Email address'), 'alex@example.com');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expectFieldFocused(tester, field('Password'));

      final createAccount = find.widgetWithText(TextButton, 'Create account');
      final resetPassword = find.widgetWithText(TextButton, 'Forgot password?');
      expect(tester.getSize(createAccount).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(resetPassword).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('registration takes the user back to the first missing detail', (
    tester,
  ) async {
    await pumpForm(tester, const RegisterScreen());
    await tapVisible(tester, find.widgetWithText(AppButton, 'Create account'));

    expect(find.text('Enter your first name'), findsOneWidget);
    expectFieldFocused(tester, field('First name'));
    expectFieldVisible(tester, field('First name'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration reveals and focuses the optional phone field', (
    tester,
  ) async {
    await pumpForm(tester, const RegisterScreen());
    expect(field('Phone number (optional)'), findsNothing);
    final addPhone = find.widgetWithText(
      TextButton,
      'Add phone number (optional)',
    );
    expect(tester.getSize(addPhone).height, greaterThanOrEqualTo(48));

    await tapVisible(tester, addPhone);

    expect(field('Phone number (optional)'), findsOneWidget);
    expectFieldFocused(tester, field('Phone number (optional)'));
    expectFieldVisible(tester, field('Phone number (optional)'));
    await tester.enterText(field('Phone number (optional)'), '09123456789');
    await tester.pumpAndSettle();
    expect(find.text('09123456789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('new password policy requires every listed rule without rewriting', () {
    expect(PasswordPolicy.minimumLength, 8);
    for (final password in <String?>[null, '', '        ']) {
      expect(PasswordPolicy.validate(password), 'Enter a password');
    }
    expect(
      PasswordPolicy.validate('seven77'),
      PasswordPolicy.minimumLengthMessage,
    );
    expect(PasswordPolicy.validate('eight888'), isNotNull);
    expect(PasswordPolicy.validate('a longer passphrase'), isNotNull);
    expect(PasswordPolicy.validate(' Secret1! '), isNull);
    expect(PasswordPolicy.validate('Secret1!'), isNull);
  });

  testWidgets(
    'registration removes intro and keeps required address guidance',
    (tester) async {
      await pumpForm(tester, const RegisterScreen());
      expect(
        find.text('All fields are required unless marked optional.'),
        findsNothing,
      );
      expect(find.text('Your details'), findsOneWidget);
      expect(field('Address (required)'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration checklist follows focus, valid input, edits and autofill',
    (tester) async {
      await pumpForm(tester, const RegisterScreen());
      final rules = ['length', 'special', 'uppercase', 'number'];
      void expectChecklistHidden() {
        for (final rule in rules) {
          expect(
            find.byKey(ValueKey('password_requirement_$rule')),
            findsNothing,
          );
        }
      }

      void expectNeutralChecklist() {
        for (final rule in rules) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey('password_requirement_$rule')),
              matching: find.byIcon(Icons.info_outline),
            ),
            findsOneWidget,
          );
        }
      }

      expectChecklistHidden();
      await tapVisible(tester, field('Password'));
      expectFieldFocused(tester, field('Password'));
      expectNeutralChecklist();
      await tapVisible(tester, field('Confirm password'));
      expectChecklistHidden();
      await tapVisible(tester, field('Password'));
      expectNeutralChecklist();

      await tester.enterText(field('Password'), 'eight888');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('password_requirement_special')),
          matching: find.byIcon(Icons.cancel_outlined),
        ),
        findsOneWidget,
      );
      expect(find.text('Passwords match'), findsNothing);

      await tester.enterText(field('Password'), 'Complete1!');
      await tester.pumpAndSettle();
      expectFieldFocused(tester, field('Password'));
      expectChecklistHidden();
      await tester.enterText(field('Password'), 'Complete1');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('password_requirement_special')),
          matching: find.byIcon(Icons.cancel_outlined),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, field('Confirm password'));
      expect(find.text('At least 1 special character'), findsOneWidget);

      // Password managers update the controller without invoking onChanged.
      final passwordController = tester
          .widget<EditableText>(
            find.descendant(
              of: field('Password'),
              matching: find.byType(EditableText),
            ),
          )
          .controller;
      passwordController.text = 'Complete1!';
      await tester.pumpAndSettle();
      final requirements = tester.widget<PasswordRequirements>(
        find.byType(PasswordRequirements),
      );
      expect(requirements.password, 'Complete1!');
      expectChecklistHidden();
      await tapVisible(tester, field('Password'));
      expectChecklistHidden();
      passwordController.clear();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PasswordRequirements>(find.byType(PasswordRequirements))
            .password,
        isEmpty,
      );
      expectNeutralChecklist();
      await tapVisible(tester, field('Confirm password'));
      expectChecklistHidden();
      expect(find.text('Passwords match'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('registration password visibility retains the exact password', (
    tester,
  ) async {
    await pumpForm(tester, const RegisterScreen());
    await tester.ensureVisible(field('Password'));
    await tester.enterText(field('Password'), ' secret ');
    await tester.pumpAndSettle();
    final passwordEditable = find.descendant(
      of: field('Password'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(passwordEditable).obscureText, isTrue);
    await tapVisible(tester, find.byTooltip('Show password'));
    expect(tester.widget<EditableText>(passwordEditable).obscureText, isFalse);
    expect(
      tester.widget<EditableText>(passwordEditable).controller.text,
      ' secret ',
    );
    await tapVisible(tester, find.byTooltip('Hide password'));
    expect(tester.widget<EditableText>(passwordEditable).obscureText, isTrue);
    expect(
      tester.widget<EditableText>(passwordEditable).controller.text,
      ' secret ',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('password success requires a valid matching password', (
    tester,
  ) async {
    await pumpForm(tester, const RegisterScreen(), dark: true);

    Future<void> enterPassword(String label, String value) async {
      await tester.ensureVisible(field(label));
      await tester.pumpAndSettle();
      await tester.enterText(field(label), value);
      await tester.pumpAndSettle();
    }

    await enterPassword('Password', 'seven77');
    await enterPassword('Confirm password', 'seven77');
    expect(find.text('Passwords match'), findsNothing);
    expect(find.text(PasswordPolicy.minimumLengthMessage), findsOneWidget);

    await enterPassword('Password', 'Eight888!');
    await enterPassword('Confirm password', 'Eight888!');
    expect(find.text('Passwords match'), findsOneWidget);

    await enterPassword('Password', 'different123');
    expect(find.text('Passwords match'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration reveals a missing required address after keyboard submit',
    (tester) async {
      await pumpForm(tester, const RegisterScreen(), dark: true);
      for (final entry in {
        'First name': 'Alex',
        'Last name': 'Reyes',
        'Email address': 'alex@example.com',
        'Password': 'Secret123!',
        'Confirm password': 'Secret123!',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.enterText(field(entry.key), entry.value);
        await tester.pumpAndSettle();
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        find.text('Enter your address or use your current location.'),
        findsOneWidget,
      );
      expectFieldFocused(tester, field('Address (required)'));
      expectFieldVisible(tester, field('Address (required)'));
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset validation rejects malformed email and focuses correction',
    (tester) async {
      await pumpForm(tester, const ForgotPasswordScreen(), dark: true);
      await tapVisible(tester, find.text('Send reset link'));
      expect(find.text('Enter your email address'), findsOneWidget);
      expectFieldFocused(tester, field('Email address'));
      expectFieldVisible(tester, field('Email address'));

      await tester.enterText(field('Email address'), 'alex@');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expectFieldFocused(tester, field('Email address'));
      expect(find.text('Check your email'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
