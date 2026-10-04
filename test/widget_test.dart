import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/features/auth/presentation/welcome_screen.dart';
import 'package:flutter_101repairshop/features/home/presentation/home_screen.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';
import 'package:flutter_101repairshop/features/shared/models/appointment.dart';
import 'package:flutter_101repairshop/features/shared/models/service_report.dart';

class _Customers extends CustomerRepository {
  @override
  Future<Customer?> getCurrentCustomer() async => Customer(
    id: 'customer',
    firstName: 'Alex',
    lastName: 'Reyes',
    address: '123 Mabini Street, Barangay San Antonio, Davao City, 8000',
  );
}

class _Repairs extends RepairsRepository {
  bool fail = false;
  @override
  Future<List<ServiceReport>> getRepairs() async {
    if (fail) throw Exception('offline');
    return [
      ServiceReport(id: 1, customerId: 'customer', status: 'In Progress'),
      ServiceReport(id: 2, customerId: 'customer', status: 'Completed'),
    ];
  }
}

class _Appointments extends AppointmentsRepository {
  @override
  Future<List<Appointment>> getAppointments() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      Appointment(
        id: 1,
        customerId: 'customer',
        title: 'Later visit',
        appointmentDate: today.add(const Duration(days: 4)),
      ),
      Appointment(
        id: 2,
        customerId: 'customer',
        title: 'Past visit',
        appointmentDate: today.subtract(const Duration(days: 1)),
      ),
      Appointment(
        id: 3,
        customerId: 'customer',
        title: 'Cancelled visit',
        appointmentDate: today.add(const Duration(days: 1)),
        status: 'Cancelled',
      ),
      Appointment(
        id: 4,
        customerId: 'customer',
        title: 'Next visit',
        appointmentDate: today.add(const Duration(days: 2)),
      ),
    ];
  }
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

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  Future<void> pumpDashboard(
    WidgetTester tester,
    _Repairs repairs, {
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider.overrideWithValue(_Customers()),
          repairsRepositoryProvider.overrideWithValue(repairs),
          appointmentsRepositoryProvider.overrideWithValue(_Appointments()),
        ],
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Dashboard displays saved address and filters completed and past work',
    (tester) async {
      await pumpDashboard(tester, _Repairs(), dark: true);
      expect(
        find.text('123 Mabini Street, Barangay San Antonio, Davao City, 8000'),
        findsOneWidget,
      );
      expect(find.text('Active repairs (1)'), findsOneWidget);
      expect(find.text('SR-2'), findsNothing);
      expect(find.text('Upcoming appointments (2)'), findsOneWidget);
      expect(find.text('Past visit'), findsNothing);
      expect(find.text('Cancelled visit'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Next visit')).dy,
        lessThan(tester.getTopLeft(find.text('Later visit')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Dashboard errors provide a working retry instead of an empty state',
    (tester) async {
      final repairs = _Repairs()..fail = true;
      await pumpDashboard(tester, repairs);
      expect(find.text('We could not load your dashboard'), findsOneWidget);
      repairs.fail = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('We could not load your dashboard'), findsNothing);
      expect(find.text('Active repairs (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Welcome remains scrollable on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create Account'));
    expect(find.text('Create Account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
