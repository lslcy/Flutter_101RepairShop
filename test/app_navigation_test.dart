import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/router/app_router.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/features/auth/data/auth_flow_controller.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/home/presentation/home_screen.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/profile/data/transactions_repository.dart';
import 'package:flutter_101repairshop/features/profile/presentation/add_appliance_screen.dart';
import 'package:flutter_101repairshop/features/profile/presentation/appliances_screen.dart';
import 'package:flutter_101repairshop/features/profile/presentation/transaction_history_screen.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/appliance.dart';
import 'package:flutter_101repairshop/features/shared/models/appointment.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';
import 'package:flutter_101repairshop/features/shared/models/service_report.dart';
import 'package:flutter_101repairshop/features/shared/models/transaction.dart'
    as models;

class _SignedInFlow extends AuthFlowController {
  _SignedInFlow() : super(Supabase.instance.client);

  @override
  bool get isLoggedIn => true;
}

class _Customers extends CustomerRepository {
  @override
  Future<Customer?> getCurrentCustomer() async => Customer(
    id: 'customer',
    firstName: 'Alex',
    lastName: 'Reyes',
    address: '123 Mabini Street, Davao City',
  );

  @override
  Future<List<Appliance>> getAppliances() async => [];
}

class _Repairs extends RepairsRepository {
  @override
  Future<List<ServiceReport>> getRepairs() async => [];
}

class _Appointments extends AppointmentsRepository {
  @override
  Future<List<Appointment>> getAppointments() async => [];
}

class _Transactions extends TransactionsRepository {
  @override
  bool get isSignedIn => true;

  @override
  Future<List<models.Transaction>?> getTransactions() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'test-key',
      debug: false,
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    setSize(tester, const Size(360, 800));
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authFlowProvider.overrideWith((ref) => _SignedInFlow()),
          customerRepositoryProvider.overrideWith((ref) => _Customers()),
          repairsRepositoryProvider.overrideWith((ref) => _Repairs()),
          appointmentsRepositoryProvider.overrideWith((ref) => _Appointments()),
          transactionsRepositoryProvider.overrideWith((ref) => _Transactions()),
        ],
        child: Consumer(
          builder: (_, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final dark in [false, true]) {
    testWidgets(
      'All six destinations work at 320px and 200% text, dark=$dark',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          setSize(tester, const Size(320, 568));
          var selected = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: const SizedBox.shrink(),
                  bottomNavigationBar: AppBottomNavigationBar(
                    selectedIndex: selected,
                    onDestinationSelected: (index) =>
                        setState(() => selected = index),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NavigationDestination), findsNWidgets(6));
          for (var index = 0; index < 6; index++) {
            final destination = find.byType(NavigationDestination).at(index);
            final label = AppBottomNavigationBar.destinations[index].label;
            final size = tester.getSize(destination);
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
            await tester.tap(destination);
            await tester.pumpAndSettle();
            expect(selected, index);
            expect(find.bySemanticsLabel(RegExp('^$label\\b')), findsOneWidget);
            final selectedLabel = tester.widget<Text>(
              find.byKey(const ValueKey('selected-navigation-label')),
            );
            expect(selectedLabel.data, label);
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('Roomy layouts show all six labels', (tester) async {
    setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: AppBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
    );
    for (final destination in AppBottomNavigationBar.destinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home shortcuts are replaced by persistent appliances and payments tabs',
    (tester) async {
      final router = await pumpApp(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('Your account'), findsNothing);
      expect(find.text('My appliances'), findsNothing);
      expect(find.text('Payment history'), findsNothing);

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/profile/appliances',
      );
      expect(find.byType(AppliancesScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/profile/transactions',
      );
      expect(find.byType(TransactionHistoryScreen), findsOneWidget);
      expect(find.byType(AppBottomNavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );

      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Existing account URLs select the matching tabs and add appliance returns safely',
    (tester) async {
      final router = await pumpApp(tester);
      router.go('/profile/transactions');
      await tester.pumpAndSettle();
      expect(find.byType(TransactionHistoryScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );

      router.go('/profile/appliances');
      await tester.pumpAndSettle();
      expect(find.byType(AppliancesScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await tester.tap(find.text('Add appliance'));
      await tester.pumpAndSettle();
      expect(find.byType(AddApplianceScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AppliancesScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'The bottom bar makes room for the keyboard and returns when it closes',
    (tester) async {
      await pumpApp(tester);
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomNavigationBar), findsNothing);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(find.byType(AppBottomNavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Existing Profile shortcuts still open the promoted navigation tabs',
    (tester) async {
      final router = await pumpApp(tester);
      router.go('/profile');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('My appliances'));
      await tester.tap(find.text('My appliances'));
      await tester.pumpAndSettle();
      expect(find.byType(AppliancesScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      router.go('/profile');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Transaction history'));
      await tester.tap(find.text('Transaction history'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionHistoryScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
