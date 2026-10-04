import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/router/app_router.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/auth/presentation/reset_password_screen.dart';
import 'package:flutter_101repairshop/features/auth/presentation/forgot_password_screen.dart';
import 'package:flutter_101repairshop/features/home/presentation/home_screen.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';

class _FakeFlow extends AuthFlowController {
  _FakeFlow({
    PasswordRecoveryStage stage = PasswordRecoveryStage.ready,
    this.preserveSessionOnAbandon = false,
  }) : _testStage = stage,
       _loggedIn = stage != PasswordRecoveryStage.idle,
       super(
         SupabaseClient(
           'http://127.0.0.1:54321',
           'test-anon-key',
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  final bool preserveSessionOnAbandon;
  PasswordRecoveryStage _testStage;
  bool _loggedIn;
  final submittedPasswords = <String>[];
  Completer<void>? pendingUpdate;
  int abandonCalls = 0;
  int finishCalls = 0;

  @override
  PasswordRecoveryStage get stage => _testStage;
  @override
  bool get isLoggedIn => _loggedIn;
  @override
  bool get requiresRecovery => stage != PasswordRecoveryStage.idle;
  @override
  bool get canResetPassword =>
      stage == PasswordRecoveryStage.ready && isLoggedIn;

  void receiveRecovery() {
    _loggedIn = true;
    _testStage = PasswordRecoveryStage.ready;
    notifyListeners();
  }

  @override
  Future<void> updatePassword(String password) async {
    submittedPasswords.add(password);
    final update = Completer<void>();
    pendingUpdate = update;
    await update.future;
    _testStage = PasswordRecoveryStage.complete;
    notifyListeners();
  }

  @override
  Future<void> abandonRecovery() async {
    abandonCalls++;
    if (!preserveSessionOnAbandon) _loggedIn = false;
    _testStage = PasswordRecoveryStage.idle;
    notifyListeners();
  }

  @override
  void finishRecovery() {
    finishCalls++;
    _testStage = PasswordRecoveryStage.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(client.dispose());
  }
}

void main() {
  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );
  Finder editable(String label) =>
      find.descendant(of: field(label), matching: find.byType(EditableText));
  Finder saveButton() => find.widgetWithText(AppButton, 'Save new password');

  Future<GoRouter> pumpForm(
    WidgetTester tester,
    _FakeFlow flow, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/reset-password',
      routes: [
        GoRoute(
          path: '/reset-password',
          builder: (_, _) => const ResetPasswordScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (_, _) => const Scaffold(body: Text('Request reset email')),
        ),
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
        overrides: [authFlowProvider.overrideWith((ref) => flow)],
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
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enterPassword(
    WidgetTester tester,
    String label,
    String text,
  ) async {
    await tester.ensureVisible(field(label));
    await tester.pumpAndSettle();
    await tester.enterText(field(label), text);
    await tester.pumpAndSettle();
  }

  Future<void> enterValidPasswords(WidgetTester tester) async {
    await enterPassword(tester, 'New password', 'eight888');
    await enterPassword(tester, 'Confirm password', 'eight888');
  }

  for (final dark in [false, true]) {
    testWidgets(
      'reset form fits 320px at 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await pumpForm(tester, _FakeFlow(), dark: dark);
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(find.text('At least 8 characters'), findsOneWidget);
        await tapVisible(tester, find.byTooltip('Show password'));
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -1800),
        );
        await tester.pumpAndSettle();
        expect(saveButton(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final stage in [
    PasswordRecoveryStage.idle,
    PasswordRecoveryStage.invalid,
  ]) {
    testWidgets(
      '${stage.name} recovery offers a new link without a password form',
      (tester) async {
        final flow = _FakeFlow(stage: stage);
        final router = await pumpForm(tester, flow);
        expect(find.byType(TextFormField), findsNothing);
        expect(
          find.text(
            stage == PasswordRecoveryStage.idle
                ? 'Open your password reset link'
                : 'This link is no longer valid',
          ),
          findsOneWidget,
        );
        await tapVisible(
          tester,
          find.widgetWithText(AppButton, 'Request a new link'),
        );
        expect(flow.abandonCalls, 1);
        expect(flow.submittedPasswords, isEmpty);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/forgot-password',
        );
        expect(find.text('Request reset email'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a fresh recovery link restores the form after an invalid link', (
    tester,
  ) async {
    final flow = _FakeFlow(stage: PasswordRecoveryStage.invalid);
    await pumpForm(tester, flow);
    expect(find.text('This link is no longer valid'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    flow.receiveRecovery();
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('This link is no longer valid'), findsNothing);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reset focuses the first error and requires eight matching characters',
    (tester) async {
      final flow = _FakeFlow();
      await pumpForm(tester, flow);
      await tapVisible(tester, saveButton());
      expect(find.text('Enter a password'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(editable('New password'))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.getTopLeft(field('New password')).dy, lessThan(568));

      await enterPassword(tester, 'New password', 'seven77');
      await enterPassword(tester, 'Confirm password', 'seven77');
      await tapVisible(tester, saveButton());
      expect(find.text('Use at least 8 characters'), findsOneWidget);
      expect(find.text('Passwords match'), findsNothing);
      expect(
        tester
            .widget<EditableText>(editable('New password'))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await enterPassword(tester, 'New password', 'eight888');
      await enterPassword(tester, 'Confirm password', 'different');
      await tapVisible(tester, saveButton());
      expect(find.text('Use at least 8 characters'), findsNothing);
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(editable('Confirm password'))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(flow.submittedPasswords, isEmpty);
      await enterPassword(tester, 'Confirm password', 'eight888');
      expect(find.text('Passwords match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset password visibility preserves entered spaces and characters',
    (tester) async {
      await pumpForm(tester, _FakeFlow());
      await enterPassword(tester, 'New password', ' secret ');
      expect(
        tester.widget<EditableText>(editable('New password')).obscureText,
        isTrue,
      );
      await tapVisible(tester, find.byTooltip('Show password'));
      expect(
        tester.widget<EditableText>(editable('New password')).obscureText,
        isFalse,
      );
      expect(
        tester.widget<EditableText>(editable('New password')).controller.text,
        ' secret ',
      );
      await tapVisible(tester, find.byTooltip('Hide password'));
      expect(
        tester.widget<EditableText>(editable('New password')).obscureText,
        isTrue,
      );
      expect(
        tester.widget<EditableText>(editable('New password')).controller.text,
        ' secret ',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving blocks repeats and exit and confirms only after completion',
    (tester) async {
      final flow = _FakeFlow();
      final router = await pumpForm(tester, flow);
      await enterValidPasswords(tester);
      final queuedSubmit = tester.widget<AppButton>(saveButton()).onPressed!;
      await tapVisible(tester, saveButton());
      queuedSubmit();
      await tester.pumpAndSettle();
      expect(flow.submittedPasswords, ['eight888']);
      expect(find.text('Password updated'), findsNothing);
      expect(find.text('Saving password...'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Back to sign in'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Back to sign in'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(flow.abandonCalls, 0);
      expect(router.routeInformationProvider.value.uri.path, '/reset-password');

      flow.pendingUpdate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Password updated'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tapVisible(tester, find.widgetWithText(AppButton, 'Continue'));
      expect(flow.finishCalls, 1);
      expect(find.text('Account destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset network failure retains input and allows a successful retry',
    (tester) async {
      final flow = _FakeFlow();
      await pumpForm(tester, flow, dark: true);
      await enterValidPasswords(tester);
      await tapVisible(tester, saveButton());
      flow.pendingUpdate!.completeError(
        const AuthException('network connection failed'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'We could not connect. Check your internet connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Password updated'), findsNothing);
      expect(
        tester.widget<EditableText>(editable('New password')).controller.text,
        'eight888',
      );
      expect(
        tester
            .widget<EditableText>(editable('Confirm password'))
            .controller
            .text,
        'eight888',
      );
      await tapVisible(tester, saveButton());
      expect(flow.submittedPasswords, ['eight888', 'eight888']);
      flow.pendingUpdate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Password updated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an invalid reset link can request a new link while an ordinary session remains',
    (tester) async {
      final flow = _FakeFlow(
        stage: PasswordRecoveryStage.invalid,
        preserveSessionOnAbandon: true,
      );
      var protectedReads = 0;
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authFlowProvider.overrideWith((ref) => flow),
            customerRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Requesting a reset must not open Home');
            }),
            repairsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Requesting a reset must not load repairs');
            }),
            appointmentsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Requesting a reset must not load appointments');
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(
                routerConfig: router,
                theme: AppTheme.light,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/reset-password');
      expect(find.text('This link is no longer valid'), findsOneWidget);
      await tapVisible(
        tester,
        find.widgetWithText(AppButton, 'Request a new link'),
      );
      expect(flow.abandonCalls, 1);
      expect(flow.isLoggedIn, isTrue);
      expect(flow.stage, PasswordRecoveryStage.idle);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/forgot-password',
      );
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(protectedReads, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real router prioritizes recovery over an authenticated Home route',
    (tester) async {
      final flow = _FakeFlow(stage: PasswordRecoveryStage.idle);
      var protectedReads = 0;
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authFlowProvider.overrideWith((ref) => flow),
            customerRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Recovery must not load the customer profile');
            }),
            repairsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Recovery must not load repairs');
            }),
            appointmentsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Recovery must not load appointments');
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(
                routerConfig: router,
                theme: AppTheme.light,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/welcome');
      flow.receiveRecovery();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/reset-password');
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(protectedReads, 0);
      router.go('/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/reset-password');
      expect(protectedReads, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
