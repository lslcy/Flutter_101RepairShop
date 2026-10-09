import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/constants/app_constants.dart';
import 'package:flutter_101repairshop/core/services/notification_service.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/appointments/presentation/book_appointment_screen.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';
import 'package:flutter_101repairshop/features/shared/models/appliance.dart';

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

  final appliances = <Appliance>[
    Appliance(
      id: 1,
      customerId: 'customer',
      brand: 'Samsung',
      product: 'split-type AC',
      modelNo: 'AR12',
      serialNo: 'SN12345',
    ),
  ];
  Customer customer;
  bool fail = false;
  int loadCount = 0;
  Completer<void>? pending;

  @override
  Future<List<Appliance>> getAppliances() async => appliances;

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
  int? insertedId;
  Object? error;
  Completer<void>? pending;

  @override
  Future<int?> bookAppointment(Map<String, dynamic> appointmentData) async {
    if (error != null) throw error!;
    bookings.add(Map<String, dynamic>.from(appointmentData));
    await pending?.future;
    return insertedId;
  }
}

class _Reminders extends NotificationService {
  bool allowed = true;
  int permissionRequests = 0;
  ReminderScheduleResult result = ReminderScheduleResult.scheduled;
  final scheduledIds = <int>[];
  final scheduledMinutes = <int>[];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allowed;
  }

  @override
  Future<ReminderScheduleResult> scheduleAppointmentReminder({
    required int appointmentId,
    required String title,
    required DateTime appointmentDate,
    String? timeSlot,
    required int reminderMinutes,
  }) async {
    scheduledIds.add(appointmentId);
    scheduledMinutes.add(reminderMinutes);
    return result;
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
    _Reminders? reminders,
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
          notificationServiceProvider.overrideWithValue(
            reminders ?? _Reminders(),
          ),
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

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  Finder bookButton() => find.byWidgetPredicate(
    (widget) => widget is AppButton && widget.label == 'Book appointment',
  );

  Finder bookElevatedButton() =>
      find.descendant(of: bookButton(), matching: find.byType(ElevatedButton));

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
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
    await tapVisible(tester, dropdown);
    await tester.tap(find.text(AppConstants.timeSlots.first).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseReminder(WidgetTester tester, String label) async {
    await tapVisible(tester, find.byType(DropdownButton<int>).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'chosen leadtime is saved and schedules one reminder after booking',
    (tester) async {
      final appointments = _Appointments()..insertedId = 77;
      final reminders = _Reminders();
      await pumpBooking(
        tester,
        _Customers(),
        appointments,
        reminders: reminders,
      );
      expect(reminders.permissionRequests, 0);
      await tester.enterText(field('What needs fixing?'), 'Fan repair');
      await chooseDate(tester);
      await chooseTime(tester);
      await chooseReminder(tester, '15 minutes before');
      expect(reminders.permissionRequests, 1);
      await tapVisible(tester, bookButton());
      expect(appointments.bookings.single['reminder_minutes'], 15);
      expect(reminders.scheduledIds, [77]);
      expect(reminders.scheduledMinutes, [15]);
      expect(find.text('Appointments test destination'), findsOneWidget);
    },
  );

  testWidgets('No reminder clears a previously selected reminder', (
    tester,
  ) async {
    final appointments = _Appointments()..insertedId = 77;
    final reminders = _Reminders();
    await pumpBooking(tester, _Customers(), appointments, reminders: reminders);
    await chooseReminder(tester, '15 minutes before');
    await chooseReminder(tester, 'No reminder');
    await tester.enterText(field('What needs fixing?'), 'Fan repair');
    await chooseDate(tester);
    await chooseTime(tester);
    await tapVisible(tester, bookButton());
    expect(appointments.bookings.single['reminder_minutes'], isNull);
    expect(reminders.scheduledIds, isEmpty);
    expect(reminders.permissionRequests, 1);
  });

  testWidgets(
    'denied notification permission keeps the preference and allows booking',
    (tester) async {
      final appointments = _Appointments()..insertedId = 77;
      final reminders = _Reminders()..allowed = false;
      await pumpBooking(
        tester,
        _Customers(),
        appointments,
        reminders: reminders,
      );
      await chooseReminder(tester, '10 minutes before');
      expect(
        find.text(
          'Your choice will be saved. Allow notifications in phone settings to receive reminders.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
        isNotNull,
      );
      await tester.enterText(field('What needs fixing?'), 'Fan repair');
      await chooseDate(tester);
      await chooseTime(tester);
      await tapVisible(tester, bookButton());
      expect(appointments.bookings.single['reminder_minutes'], 10);
      expect(find.text('Appointments test destination'), findsOneWidget);
    },
  );

  testWidgets('a device reminder failure never invites a duplicate booking', (
    tester,
  ) async {
    final appointments = _Appointments()..insertedId = 77;
    final reminders = _Reminders()..result = ReminderScheduleResult.failed;
    await pumpBooking(tester, _Customers(), appointments, reminders: reminders);
    await tester.enterText(field('What needs fixing?'), 'Fan repair');
    await chooseDate(tester);
    await chooseTime(tester);
    await chooseReminder(tester, '5 minutes before');
    await tapVisible(tester, bookButton());
    expect(appointments.bookings, hasLength(1));
    expect(find.text('Appointments test destination'), findsOneWidget);
    expect(
      find.text('We couldn’t book your appointment. Please try again.'),
      findsNothing,
    );
  });
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
      await tester.ensureVisible(bookButton());
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
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
      isNull,
    );

    customers.fail = false;
    await tapVisible(tester, find.text('Try again'));

    expect(customers.loadCount, 2);
    expect(
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
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
    await tapVisible(tester, bookButton());
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

    await tester.ensureVisible(field('What needs fixing?'));
    await tester.enterText(field('What needs fixing?'), 'Fan will not spin');
    await chooseDate(tester);
    await tapVisible(tester, bookButton());

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
        field('What needs fixing?'),
        '  Air conditioner is leaking  ',
      );
      // The saved appliance supplies the booking label, including model and serial.
      expect(
        customers.appliances.single.bookingLabel,
        'Samsung split-type AC (Model AR12, S/N SN12345)',
      );
      final pickedDate = await chooseDate(tester);
      await chooseTime(tester);
      await tester.ensureVisible(field('Anything else? (optional)'));
      await tester.enterText(
        field('Anything else? (optional)'),
        '  Water drips after ten minutes.  ',
      );
      await tester.ensureVisible(bookButton());
      await tester.pumpAndSettle();
      await tester.tap(bookButton());
      await tester.pump();

      expect(appointments.bookings, hasLength(1));
      expect(
        tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
        isNull,
      );
      expect(appointments.bookings.single, {
        'title': 'Air conditioner is leaking',
        'appliance_name': customers.appliances.single.bookingLabel,
        'appointment_date': pickedDate.toIso8601String().split('T').first,
        'time_slot': AppConstants.timeSlots.first,
        'notes': 'Water drips after ten minutes.',
        'reminder_minutes': null,
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
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
      isNull,
    );
    expect(appointments.bookings, isEmpty);

    customers.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
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

      await tester.enterText(field('What needs fixing?'), 'Broken fan');
      await chooseDate(tester);
      await chooseTime(tester);
      await tapVisible(tester, bookButton());

      expect(
        tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
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
    await tester.enterText(field('What needs fixing?'), 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);

    // Another device clears the persisted address after this screen loaded it.
    customers.customer = Customer(id: 'customer', address: '  ');
    await tapVisible(tester, bookButton());

    expect(customers.loadCount, 2);
    expect(find.text('Add address'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
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
    await tester.enterText(field('What needs fixing?'), 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);
    await tapVisible(tester, find.text('Add address'));
    expect(find.text('Edit profile test destination'), findsOneWidget);

    await tester.tap(find.text('Save profile test address'));
    await tester.pumpAndSettle();

    expect(customers.loadCount, 2);
    expect(
      tester.widget<ElevatedButton>(bookElevatedButton()).onPressed,
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
    await tester.enterText(field('What needs fixing?'), 'Broken fan');
    await chooseDate(tester);
    await chooseTime(tester);
    await tester.ensureVisible(field('Anything else? (optional)'));
    await tester.enterText(
      field('Anything else? (optional)'),
      'Makes a loud sound',
    );
    await tapVisible(tester, bookButton());

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
          .widget<TextFormField>(field('Anything else? (optional)'))
          .controller
          ?.text,
      'Makes a loud sound',
    );
    expect(find.text('Choose a date'), findsNothing);
    expect(find.text('Select a time slot'), findsNothing);

    appointments.error = null;
    await tapVisible(tester, bookButton());
    expect(appointments.bookings, hasLength(1));
    expect(appointments.bookings.single['notes'], 'Makes a loud sound');
    expect(find.text('Appointments test destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
