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
import 'package:flutter_101repairshop/features/auth/presentation/complete_profile_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/home/presentation/home_screen.dart';
import 'package:flutter_101repairshop/features/appointments/presentation/book_appointment_screen.dart';

class _ProfileFlow extends AuthFlowController {
  _ProfileFlow({this.customer})
    : super(
        SupabaseClient(
          'http://127.0.0.1:54321',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  Customer? customer;
  SignInProfileStage _profileStage = SignInProfileStage.required;
  final savedDetails = <Map<String, String>>[];
  Completer<void>? pendingSave;
  Object? saveError;

  @override
  bool get isLoggedIn => true;

  @override
  SignInProfileStage get profileStage => _profileStage;

  @override
  Customer? get signInCustomer => customer;

  @override
  bool get requiresSignInProfile => _profileStage != SignInProfileStage.ready;

  void setProfileStage(SignInProfileStage value) {
    _profileStage = value;
    notifyListeners();
  }

  @override
  Future<void> completeSignInProfile({
    required String firstName,
    required String lastName,
    required String address,
  }) async {
    savedDetails.add({
      'firstName': firstName,
      'lastName': lastName,
      'address': address,
    });
    if (pendingSave != null) await pendingSave!.future;
    if (saveError != null) throw saveError!;
    customer = Customer(
      id: 'customer-1',
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      address: address.trim(),
    );
    _profileStage = SignInProfileStage.ready;
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
  Finder saveButton() => find.widgetWithText(AppButton, 'Save and continue');

  Future<GoRouter> pumpProfile(
    WidgetTester tester,
    _ProfileFlow flow, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/complete-profile',
      refreshListenable: flow,
      redirect: (_, state) {
        final location = state.matchedLocation;
        if (flow.requiresSignInProfile && location != '/complete-profile') {
          return '/complete-profile';
        }
        if (!flow.requiresSignInProfile && location == '/complete-profile') {
          return '/';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/complete-profile',
          builder: (_, _) => const CompleteProfileScreen(),
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
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
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

  void expectFocused(WidgetTester tester, String label) {
    final target = find.descendant(
      of: field(label),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(target).focusNode.hasFocus, isTrue);
  }

  for (final dark in [false, true]) {
    testWidgets(
      'profile completion requires name and address at 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final flow = _ProfileFlow();
        final router = await pumpProfile(tester, flow, dark: dark);
        expect(find.text('Use my location'), findsOneWidget);

        await tapVisible(tester, saveButton());
        expect(find.text('Enter your first name.'), findsOneWidget);
        expectFocused(tester, 'First name');
        expect(flow.savedDetails, isEmpty);

        await enterField(tester, 'First name', 'Alex');
        await tapVisible(tester, saveButton());
        expect(find.text('Enter your last name.'), findsOneWidget);
        expectFocused(tester, 'Last name');
        expect(flow.savedDetails, isEmpty);

        await enterField(tester, 'Last name', 'Reyes');
        await tapVisible(tester, saveButton());
        expect(find.text('Enter a street or barangay.'), findsOneWidget);
        expectFocused(tester, 'Street / subdivision');
        expect(flow.savedDetails, isEmpty);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('manual address saves entered details and opens the account', (
    tester,
  ) async {
    final flow = _ProfileFlow(
      customer: Customer(
        id: 'customer-1',
        firstName: 'Alex',
        lastName: 'Reyes',
      ),
    );
    final router = await pumpProfile(tester, flow);
    expect(
      tester.widget<TextFormField>(field('First name')).controller!.text,
      'Alex',
    );
    expect(
      tester.widget<TextFormField>(field('Last name')).controller!.text,
      'Reyes',
    );
    await enterField(tester, 'Street / subdivision', '12 Mabini Street');
    await enterField(tester, 'City / municipality (required)', 'Tagum City');
    await enterField(tester, 'Province (required)', 'Davao del Norte');
    await tapVisible(tester, saveButton());

    expect(flow.savedDetails, [
      {
        'firstName': 'Alex',
        'lastName': 'Reyes',
        'address': '12 Mabini Street, Tagum City, Davao del Norte',
      },
    ]);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Account destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving prevents duplicate requests and failed save keeps inputs',
    (tester) async {
      final flow = _ProfileFlow(
        customer: Customer(
          id: 'customer-1',
          firstName: 'Alex',
          lastName: 'Reyes',
          address: '12 Mabini Street, Davao City',
        ),
      );
      flow.pendingSave = Completer<void>();
      flow.saveError = StateError('Temporary profile save failure');
      final router = await pumpProfile(tester, flow, dark: true);
      await Scrollable.ensureVisible(
        tester.element(saveButton()),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();

      // Two taps before a rebuild exercise the handler's duplicate guard.
      await tester.tap(saveButton());
      await tester.tap(saveButton());
      await tester.pump();
      expect(flow.savedDetails, hasLength(1));
      expect(find.text('Saving details...'), findsOneWidget);
      for (final widget in tester.widgetList<AppTextField>(
        find.byType(AppTextField),
      )) {
        expect(widget.enabled, isFalse);
      }
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Use another account'),
            )
            .onPressed,
        isNull,
      );

      flow.pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('We could not save your details. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(field('First name')).controller!.text,
        'Alex',
      );
      expect(
        tester.widget<TextFormField>(field('Last name')).controller!.text,
        'Reyes',
      );
      expect(
        tester
            .widget<TextFormField>(field('Street / subdivision'))
            .controller!
            .text,
        contains('Mabini Street'),
      );
      expect(tester.widget<AppButton>(saveButton()).onPressed, isNotNull);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/complete-profile',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the actual router blocks protected reads until the profile is ready',
    (tester) async {
      final flow = _ProfileFlow();
      var protectedReads = 0;
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authFlowProvider.overrideWith((ref) => flow),
            customerRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError(
                'Incomplete accounts must not read customer data',
              );
            }),
            repairsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError('Incomplete accounts must not read repairs');
            }),
            appointmentsRepositoryProvider.overrideWith((ref) {
              protectedReads++;
              throw StateError(
                'Incomplete accounts must not read appointments',
              );
            }),
          ],
          child: Consumer(
            builder: (_, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(
                routerConfig: router,
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: true),
                  child: child!,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/complete-profile',
      );

      for (final stage in [
        SignInProfileStage.required,
        SignInProfileStage.failed,
        SignInProfileStage.checking,
      ]) {
        flow.setProfileStage(stage);
        router.go('/book-appointment');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/complete-profile',
        );
        expect(find.byType(CompleteProfileScreen), findsOneWidget);
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.byType(BookAppointmentScreen), findsNothing);
        expect(protectedReads, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'profile completion filters invalid names and normalizes accepted names',
    (tester) async {
      final flow = _ProfileFlow(
        customer: Customer(
          id: 'customer-1',
          firstName: 'Alex',
          lastName: 'Reyes',
          address: '12 Mabini Street, Davao City',
        ),
      );
      await pumpProfile(tester, flow);
      await enterField(tester, 'First name', 'Alex123');
      await tapVisible(tester, saveButton());
      expect(flow.savedDetails, isEmpty);
      expect(
        find
            .text('Use letters, spaces, apostrophes, hyphens or periods.')
            .hitTestable(),
        findsOneWidget,
      );
      expectFocused(tester, 'First name');

      await enterField(tester, 'First name', '  José   María  ');
      await enterField(tester, 'Last name', '  De la   Cruz  ');
      await tapVisible(tester, saveButton());
      expect(flow.savedDetails, [
        {
          'firstName': 'José María',
          'lastName': 'De la Cruz',
          'address': '12 Mabini Street, Davao City',
        },
      ]);
      expect(find.text('Account destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
