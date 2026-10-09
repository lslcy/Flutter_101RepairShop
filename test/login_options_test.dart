import 'dart:async';

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
import 'package:flutter_101repairshop/features/auth/presentation/login_screen.dart';

void main() {
  late SupabaseClient client;
  late AuthFlowController flow;
  late AuthNotifier notifier;
  Completer<bool>? pendingLaunch;
  Object? launchError;
  int launchCalls = 0;

  setUp(() {
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    flow = AuthFlowController(client);
    pendingLaunch = null;
    launchError = null;
    launchCalls = 0;
    notifier = AuthNotifier(
      supabase: client,
      authFlow: flow,
      googleSignInLauncher: ({required redirectTo, required launchMode}) async {
        launchCalls++;
        if (launchError != null) throw launchError!;
        return pendingLaunch?.future ?? Future.value(true);
      },
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<GoRouter> pumpLogin(WidgetTester tester, {bool dark = false}) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/phone-sign-in',
          builder: (_, _) => const Scaffold(body: Text('Phone destination')),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Scaffold(body: Text('Welcome destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authFlowProvider.overrideWith((ref) => flow),
          authStateProvider.overrideWith((ref) => notifier),
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
    await tester.pump();
  }

  Finder googleButton() =>
      find.widgetWithText(AppButton, 'Continue with Google');

  testWidgets('phone sign-in is reachable without validating email fields', (
    tester,
  ) async {
    final router = await pumpLogin(tester);
    final phoneButton = find.widgetWithText(AppButton, 'Continue with phone');
    expect(tester.getSize(phoneButton).height, greaterThanOrEqualTo(48));

    await tapVisible(tester, phoneButton);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/phone-sign-in');
    expect(find.text('Phone destination'), findsOneWidget);
    expect(find.text('Enter your email address'), findsNothing);
    expect(launchCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Google launch waits for browser completion and can be canceled',
    (tester) async {
      pendingLaunch = Completer<bool>();
      await pumpLogin(tester, dark: true);
      expect(tester.getSize(googleButton()).height, greaterThanOrEqualTo(48));

      await tapVisible(tester, googleButton());
      expect(find.text('Opening Google...'), findsOneWidget);
      expect(
        find.text('Finish signing in with Google in your browser.'),
        findsNothing,
      );
      expect(launchCalls, 1);
      expect(flow.isGoogleSignInPending, isTrue);
      expect(
        tester
            .widget<AppButton>(
              find.widgetWithText(AppButton, 'Continue with phone'),
            )
            .onPressed,
        isNull,
      );
      for (final field in tester.widgetList<AppTextField>(
        find.byType(AppTextField),
      )) {
        expect(field.enabled, isFalse);
      }
      expect(find.text('Enter your email address'), findsNothing);
      expect(client.auth.currentSession, isNull);

      pendingLaunch!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Opening Google...'), findsNothing);
      expect(
        find.text('Finish signing in with Google in your browser.'),
        findsOneWidget,
      );
      expect(tester.widget<AppButton>(googleButton()).onPressed, isNull);
      expect(client.auth.currentSession, isNull);

      await tapVisible(tester, find.text('Use another sign-in method'));
      await tester.pumpAndSettle();
      expect(flow.isGoogleSignInPending, isFalse);
      expect(
        find.text('Finish signing in with Google in your browser.'),
        findsNothing,
      );
      expect(tester.widget<AppButton>(googleButton()).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed browser launch offers a usable retry', (tester) async {
    pendingLaunch = Completer<bool>()..complete(false);
    await pumpLogin(tester);

    await tapVisible(tester, googleButton());
    await tester.pumpAndSettle();

    expect(
      find.text('We could not open Google sign-in. Please try again.'),
      findsOneWidget,
    );
    expect(flow.isGoogleSignInPending, isFalse);
    expect(tester.widget<AppButton>(googleButton()).onPressed, isNotNull);
    expect(find.text('Enter your email address'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured Google provider gives a clear alternative', (
    tester,
  ) async {
    launchError = const AuthException(
      'Unsupported provider: provider is not enabled',
    );
    await pumpLogin(tester, dark: true);

    await tapVisible(tester, googleButton());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Google sign-in is not available yet. Please use another sign-in method.',
      ),
      findsOneWidget,
    );
    expect(flow.isGoogleSignInPending, isFalse);
    expect(tester.widget<AppButton>(googleButton()).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
