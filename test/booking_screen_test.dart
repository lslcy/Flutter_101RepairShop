import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/constants/app_constants.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/appointments/presentation/book_appointment_screen.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';

const _longAddress =
    'Unit 1204, Building Three, 123 Mabini Street, Barangay San Antonio, '
    'Buhangin District, Davao City, Davao del Sur, Philippines 8000';
const _updatedAddress = '45 Jacinto Street, Davao City, 8000';

class _Customers extends CustomerRepository {
  _Customers({Customer? customer})
    : customer =
          customer ??
          Customer(
            id: 'customer',
            firstName: 'Alex',
            lastName: 'Reyes',
            phoneNo: '09171234567',
            email: 'alex.reyes@example.com',
            address: _longAddress,
          );

  Customer customer;
  bool fail = false;
  int loadCount = 0;
  Completer<void>? pending;

  @override
  Future<Customer?> getCurrentCustomer() async {
    loadCount++;
    await pending?.future;
    if (fail) throw StateError('offline');
    return customer;
  }
}

class _Appointments extends AppointmentsRepository {
  final bookings = <Map<String, dynamic>>[];
  Object? error;
  Completer<void>? pending;

  @override
  Future<void> bookAppointment(Map<String, dynamic> appointmentData) async {
    if (error != null) throw error!;
    bookings.add(Map<String, dynamic>.from(appointmentData));
    await pending?.future;
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

  Future<void> pumpBooking(
    WidgetTester tester,
    _Customers customers,
    _Appointments appointments, {
    Size size = const Size(380, 800),
    double textScale = 1,
    bool dark = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/book-appointment',
      routes: [
        GoRoute(
          path: '/book-appointment',
          builder: (context, state) => const BookAppointmentScreen(),
        ),
        GoRoute(
          path: '/appointments',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Appointments test destination')),
          ),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('Edit profile test destination')),
            body: TextButton(
              onPressed: () {
                customers.customer = Customer(
                  id: 'customer',
                  firstName: 'Alex',
                  address: _updatedAddress,
                );
                context.pop();
              },
              child: const Text('Save profile test address'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerRepositoryProvider.overrideWithValue(customers),
          appointmentsRepositoryProvider.overrideWithValue(appointments),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<DateTime> chooseDate(WidgetTester tester) async {
    await tapVisible(tester, find.text('Choose a date'));
    final pickedDate = tester
        .widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate!;
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    return pickedDate;
  }

  Future<void> chooseTime(WidgetTester tester) async {
    final dropdown = find.byType(DropdownButton<String>);
    await Scrollable.ensureVisible(tester.element(dropdown), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppConstants.timeSlots.first).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Booking fits 320px dark mode with large text and a long saved address',
    (tester) async {
      await pumpBooking(
        tester,
        _Customers(),
        _Appointments(),
        size: const Size(320, 720),
        textScale: 1.5,
        dark: true,
      );

      expect(find.text(_longAddress), findsOneWidget);
      await chooseTime(tester);
      await tester.ensureVisible(find.text(_longAddress));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Book appointment'));
      await tester.pumpAndSettle();
      expect(find.text('Edit contact details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Booking contact details can recover after a load error', (
    tester,
  ) async {
    final customers = _Customers()..fail = true;
    await pumpBooking(tester, customers, _Appointments());
    expect(find.text('We couldn’t load your contact details.'), findsOneWidget);
    expect(find.text(_longAddress), findsNothing);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    customers.fail = false;
    await tapVisible(tester, find.text('Try again'));

    expect(customers.loadCount, 2);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(find.text('We couldn’t load your contact details.'), findsNothing);
    expect(find.text(_longAddress), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Booking validates a required title, date, and time inline', (
    tester,
  ) async {
    final appointments = _Appointments();
    await pumpBooking(tester, _Customers(), appointments);
    await tapVisible(tester, find.text('Book appointment'));
    expect(find.text('Describe what needs fixing.'), findsOneWidget);
    expect(find.text('Choose a preferred date.'), findsOneWidget);
    expect(find.text('Choose a preferred time.'), findsOneWidget);
    expect(appointments.bookings, isEmpty);
    expect(
      find.text('Describe what needs fixing.').hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isTrue,
    );

    await tester.ensureVisible(find.byType(TextFormField).at(0));
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Fan will not spin',
    );
    await chooseDate(tester);
    await tapVisible(tester, find.text('Book appointment'));

    expect(find.text('Describe what needs fixing.'), findsNothing);
    expect(find.text('Choose a preferred date.'), findsNothing);
    expect(find.text('Choose a preferred time.'), findsOneWidget);
    expect(find.text('Choose a preferred time.').hitTestable(), findsOneWidget);
    expect(appointments.bookings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Booking with a saved address saves entered details and prevents double submit',
    (tester) async {
      final appointments = _Appointments()..pending = Completer<void>();
      final customers = _Customers();
      await pumpBooking(tester, customers, appointments);
      expect(find.text(_longAddress), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        '  Air conditioner is leaking  ',
      );
      await tester.ensureVisible(find.byType(TextFormField).at(1));
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '  Samsung split-type AC  ',
      );
      final pickedDate = await chooseDate(tester);
      await chooseTime(tester);
      await tester.ensureVisible(find.byType(TextFormField).at(2));
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '  Water drips after ten minutes.  ',
      );
      await tester.ensureVisible(find.text('Book appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book appointment'));
      await tester.pump();

      expect(appointments.bookings, hasLength(1));
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(appointments.bookings.single, {
        'title': 'Air conditioner is leaking',
        'appliance_name': 'Samsung split-type AC',
        'appointment_date': pickedDate.toIso8601String().split('T').first,
        'time_slot': AppConstants.timeSlots.first,
        'notes': 'Water drips after ten minutes.',
        'status': 'Pending',
      });

      appointments.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Appointments test destination'), findsOneWidget);
      expect(appointments.bookings, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Booking stays disabled while contact details load', (
    tester,
  ) async {
    final customers = _Customers()..pending = Completer<void>();
    final appointments = _Appointments();
    await pumpBooking(tester, customers, appointments, settle: false);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(appointments.bookings, isEmpty);

    customers.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final address in <String?>[null, '', '  \n  ']) {
    testWidgets('Booking requires a saved nonblank address: $address', (
      tester,
    ) async {
      final appointments = _Appointments();
      await pumpBooking(
        tester,
        _Customers(
          customer: Customer(id: 'customer', address: address),
        ),
        appointments,
      );
      expect(find.text('No address added yet'), findsOneWidget);
      expect(find.text('Add address'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'Broken fan');
      await chooseDate(tester);
      await chooseTime(tester);
      await tapVisible(tester, find.text('Book appointment'));

      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(appointments.bookings, isEmpty);
      expect(find.text('Appointments test destination'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Booking reloads a saved address rejected by the repository', (
    tester,
  ) async {
    final customers = _Customers();
    final appointments = _Appointments()
      ..error = AppointmentAddressRequiredException();
    await pumpBooking(tester, customers, appointments);
    await tester.enterText(find.byType(TextFormField).first, 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);

    // Another device clears the persisted address after this screen loaded it.
    customers.customer = Customer(id: 'customer', address: '  ');
    await tapVisible(tester, find.text('Book appointment'));

    expect(customers.loadCount, 2);
    expect(find.text('Add address'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(appointments.bookings, isEmpty);
    expect(find.text('Appointments test destination'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Booking refreshes the address after editing the profile', (
    tester,
  ) async {
    final customers = _Customers(
      customer: Customer(id: 'customer', firstName: 'Alex'),
    );
    await pumpBooking(tester, customers, _Appointments());
    await tester.enterText(find.byType(TextFormField).first, 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);
    await tapVisible(tester, find.text('Add address'));
    expect(find.text('Edit profile test destination'), findsOneWidget);

    await tester.tap(find.text('Save profile test address'));
    await tester.pumpAndSettle();

    expect(customers.loadCount, 2);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(find.text(_updatedAddress), findsOneWidget);
    expect(find.text('No address added yet'), findsNothing);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Broken fan',
    );
    expect(find.text('Choose a date'), findsNothing);
    expect(find.text('Select a time slot'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A failed booking keeps details ready for retry', (tester) async {
    final appointments = _Appointments()
      ..error = StateError('Service is offline. Try again.');
    await pumpBooking(tester, _Customers(), appointments);
    await tester.enterText(find.byType(TextFormField).first, 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);
    await tester.ensureVisible(find.byType(TextFormField).at(2));
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'Makes a loud sound',
    );
    await tapVisible(tester, find.text('Book appointment'));

    expect(find.text('Service is offline. Try again.'), findsOneWidget);
    expect(find.text('Appointments test destination'), findsNothing);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Broken fan',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller
          ?.text,
      'Makes a loud sound',
    );
    expect(find.text('Choose a date'), findsNothing);
    expect(find.text('Select a time slot'), findsNothing);

    appointments.error = null;
    await tapVisible(tester, find.text('Book appointment'));
    expect(appointments.bookings, hasLength(1));
    expect(appointments.bookings.single['notes'], 'Makes a loud sound');
    expect(find.text('Appointments test destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
