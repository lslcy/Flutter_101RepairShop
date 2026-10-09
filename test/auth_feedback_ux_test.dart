import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_repository.dart';
import 'package:flutter_101repairshop/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter_101repairshop/features/auth/presentation/login_screen.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(SupabaseClient client, AuthFlowController flow)
    : super(supabase: client, authFlow: flow);

  final requestedEmails = <String>[];
  int signInCalls = 0;

  @override
  Future<void> resetPassword(String email) async {
    requestedEmails.add(email);
  }

  @override
  Future<void> signIn(String email, String password) async {
    signInCalls++;
    throw const AuthException('Invalid login credentials');
  }
}

void main() {
  late SupabaseClient client;
  late AuthFlowController flow;
  late _FakeAuth auth;

  setUp(() {
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    flow = AuthFlowController(client);
    auth = _FakeAuth(client, flow);
  });

  tearDown(() async {
    await client.dispose();
  });

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required bool dark,
    required bool recovery,
    String email = 'alex@example.com',
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final router = GoRouter(
      initialLocation: recovery ? '/forgot-password' : '/login',
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => ForgotPasswordScreen(initialEmail: email),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => recovery
              ? Scaffold(body: Text('Sign in: ${state.extra}'))
              : const LoginScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authFlowProvider.overrideWith((ref) => flow),
          authStateProvider.overrideWith((ref) => auth),
        ],
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
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> requestReset(WidgetTester tester) async {
    await tester.ensureVisible(field('Email address'));
    await tester.pumpAndSettle();
    await tester.tap(field('Email address'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets(
      'invalid login is revealed above fields with the keyboard in $mode mode',
      (tester) async {
        await pumpScreen(tester, dark: dark, recovery: false);
        await tester.enterText(field('Email address'), 'alex@example.com');
        await tester.ensureVisible(field('Password'));
        await tester.pumpAndSettle();
        await tester.enterText(field('Password'), 'old-password');
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        final error = find.text(
          'Incorrect email or password. Check your details and try again.',
        );
        expect(error, findsOneWidget);
        final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
        final errorRect = tester.getRect(error);
        expect(errorRect.top, greaterThanOrEqualTo(appBarBottom));
        expect(errorRect.top, lessThan(appBarBottom + 40));
        expect(errorRect.top, lessThan(568 - 180));
        // Long, enlarged feedback stays scrollable rather than being truncated.
        expect(tester.widget<Text>(error).maxLines, isNull);
        expect(errorRect.left, greaterThanOrEqualTo(0));
        expect(errorRect.right, lessThanOrEqualTo(320));
        final password = tester.widget<EditableText>(
          find.descendant(
            of: field('Password'),
            matching: find.byType(EditableText),
          ),
        );
        expect(password.focusNode.hasFocus, isFalse);
        expect(
          tester.getRect(field('Email address')).top,
          greaterThan(errorRect.bottom),
        );
        final liveRegions = tester.widgetList<Semantics>(
          find.ancestor(of: error, matching: find.byType(Semantics)),
        );
        expect(
          liveRegions.any((widget) => widget.properties.liveRegion == true),
          isTrue,
        );
        expect(auth.signInCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'reset confirmation preserves privacy and fits long email at 200% text in $mode mode',
      (tester) async {
        const email = 'a.long.customer.email.address@example.com';
        await pumpScreen(tester, dark: dark, recovery: true, email: email);
        await requestReset(tester);

        expect(auth.requestedEmails, [email]);
        expect(find.text('Check your email').hitTestable(), findsOneWidget);
        expect(
          find.text(
            'If an account uses this email, a password reset link will arrive shortly.',
          ),
          findsOneWidget,
        );
        final emailText = find.byKey(const ValueKey('reset-email-address'));
        expect(tester.widget<SelectableText>(emailText).data, email);
        expect(
          tester.widget<SelectableText>(emailText).style?.fontFamily,
          'Roboto',
        );
        final card = find.byKey(const ValueKey('reset-email-confirmation'));
        final liveRegion = tester.widget<Semantics>(
          find.ancestor(of: card, matching: find.byType(Semantics)).first,
        );
        expect(liveRegion.properties.liveRegion, isTrue);
        for (final button in [
          find.widgetWithText(AppButton, 'Back to sign in'),
          find.widgetWithText(TextButton, 'Use a different email'),
        ]) {
          expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('editing credentials clears the top error and keeps password', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false, recovery: false);
    await tester.enterText(field('Email address'), 'alex@example.com');
    await tester.ensureVisible(field('Password'));
    await tester.enterText(field('Password'), ' unchanged password ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Incorrect email or password. Check your details and try again.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(field('Email address'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Email address'), 'corrected@example.com');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Incorrect email or password. Check your details and try again.',
      ),
      findsNothing,
    );
    expect(
      tester.widget<TextFormField>(field('Password')).controller?.text,
      ' unchanged password ',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('different email restores the form and focuses correction', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false, recovery: true);
    await requestReset(tester);
    await tapVisible(tester, find.text('Use a different email'));
    expect(find.text('Check your email'), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: field('Email address'),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'alex@example.com');
    expect(auth.requestedEmails, ['alex@example.com']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation sign-in action preserves the submitted email', (
    tester,
  ) async {
    final router = await pumpScreen(tester, dark: true, recovery: true);
    await requestReset(tester);
    await tapVisible(tester, find.widgetWithText(AppButton, 'Back to sign in'));
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Sign in: alex@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
