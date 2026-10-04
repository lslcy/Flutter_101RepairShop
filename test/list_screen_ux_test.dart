import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/shimmer_loading.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/appointments/presentation/appointments_screen.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/repairs/presentation/repairs_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/appointment.dart';
import 'package:flutter_101repairshop/features/shared/models/service_report.dart';

class _Repairs extends RepairsRepository {
  List<ServiceReport> data = [];
  bool fail = false;
  int loads = 0;
  Completer<void>? pending;

  @override
  Future<List<ServiceReport>> getRepairs() async {
    loads++;
    await pending?.future;
    if (fail) throw StateError('offline');
    return data;
  }
}

class _Appointments extends AppointmentsRepository {
  List<Appointment> data = [];
  bool fail = false;
  int loads = 0;

  @override
  Future<List<Appointment>> getAppointments() async {
    loads++;
    if (fail) throw StateError('offline');
    return data;
  }
}

Appointment _appointment({String status = 'Pending'}) => Appointment(
  id: 7,
  customerId: 'customer',
  title: 'Air conditioner leaks after running for ten minutes',
  appointmentDate: DateTime(2026, 10, 5),
  timeSlot: '9:00 AM - 10:00 AM',
  status: status,
);

ServiceReport _repair({int id = 1, String? status, String? findings}) =>
    ServiceReport(
      id: id,
      customerId: 'customer',
      status: status,
      findings: findings ?? 'Fan motor needs replacement',
      dateIn: DateTime(2026, 9, 20),
    );

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

  tearDownAll(() async => Supabase.instance.dispose());

  Future<void> pumpList(
    WidgetTester tester, {
    _Repairs? repairs,
    _Appointments? appointments,
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
      initialLocation: repairs == null ? '/appointments' : '/repairs',
      routes: [
        GoRoute(path: '/repairs', builder: (_, _) => const RepairsScreen()),
        GoRoute(
          path: '/appointments',
          builder: (_, _) => const AppointmentsScreen(),
        ),
        GoRoute(
          path: '/appointments/:id',
          builder: (context, state) => Scaffold(
            appBar: AppBar(
              title: Text('Appointment ${state.pathParameters['id']}'),
            ),
            body: TextButton(
              onPressed: () {
                appointments!.data = [_appointment(status: 'Cancelled')];
                context.pop();
              },
              child: const Text('Update and return'),
            ),
          ),
        ),
        GoRoute(
          path: '/book-appointment',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('Book a repair visit')),
            body: TextButton(
              onPressed: () {
                appointments!.data = [_appointment()];
                context.pop();
              },
              child: const Text('Finish booking'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (repairs != null)
            repairsRepositoryProvider.overrideWithValue(repairs),
          if (appointments != null)
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

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('Repair load failures offer retry instead of an empty list', (
    tester,
  ) async {
    final repairs = _Repairs()..fail = true;
    await pumpList(tester, repairs: repairs);
    expect(find.text('Repairs unavailable'), findsOneWidget);
    expect(find.text('No repairs yet'), findsNothing);

    repairs
      ..fail = false
      ..data = [_repair()];
    await tapVisible(tester, find.text('Try again'));

    expect(repairs.loads, 2);
    expect(find.text('SR-1'), findsOneWidget);
    expect(find.text('Repairs unavailable'), findsNothing);
  });

  testWidgets(
    'Search combines with status and clearing filters restores repairs',
    (tester) async {
      final repairs = _Repairs()
        ..data = [
          _repair(),
          _repair(
            id: 2,
            status: 'Completed',
            findings: 'Refrigerator is cooling normally',
          ),
        ];
      await pumpList(tester, repairs: repairs);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
      await tester.pumpAndSettle();
      // Missing stored status is displayed and filtered consistently as Pending.
      expect(find.text('SR-1'), findsOneWidget);
      expect(find.text('SR-2'), findsNothing);
      expect(find.text('1 matching repair'), findsOneWidget);

      await tester.enterText(find.byType(TextField), ' refrigerator ');
      await tester.pumpAndSettle();
      expect(find.text('0 matching repairs'), findsOneWidget);
      expect(find.text('No matching repairs'), findsOneWidget);
      await tapVisible(tester, find.text('Clear filters'));

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('2 repairs'), findsOneWidget);
      expect(find.text('SR-1'), findsOneWidget);
      expect(find.text('SR-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Repair status filters scroll in one readable row in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final repairs = _Repairs()
          ..data = [
            _repair(status: 'Pending'),
            _repair(id: 2, status: 'Completed'),
          ];
        await pumpList(
          tester,
          repairs: repairs,
          size: const Size(320, 720),
          textScale: 1.5,
          dark: dark,
        );

        final filters = find.byKey(const ValueKey('repair-status-filters'));
        final all = find.widgetWithText(ChoiceChip, 'All');
        final completed = find.widgetWithText(ChoiceChip, 'Completed');
        final rowTop = tester.getTopLeft(all).dy;
        for (final element in find.byType(ChoiceChip).evaluate()) {
          final chip = find.byWidget(element.widget);
          expect(tester.getTopLeft(chip).dy, closeTo(rowTop, 0.01));
          expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
        }
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: filters, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.axis, Axis.horizontal);
        expect(scrollable.position.maxScrollExtent, greaterThan(0));

        double contrast(Color foreground, Color background) {
          final visibleForeground = Color.alphaBlend(foreground, background);
          final first = visibleForeground.computeLuminance();
          final second = background.computeLuminance();
          return first > second
              ? (first + 0.05) / (second + 0.05)
              : (second + 0.05) / (first + 0.05);
        }

        void expectReadableChips() {
          for (final element in find.byType(ChoiceChip).evaluate()) {
            final chip = find.byWidget(element.widget);
            // Read the effective text and painted chip background, so inherited
            // white labels on a light chip fail even when label widgets exist.
            final text = tester.widget<RichText>(
              find.descendant(of: chip, matching: find.byType(RichText)).first,
            );
            final ink = tester.widget<Ink>(
              find.descendant(of: chip, matching: find.byType(Ink)).first,
            );
            final background = (ink.decoration! as ShapeDecoration).color!;
            final foreground = text.text.style!.color!;
            expect(
              contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '${text.text.toPlainText()} must remain readable',
            );
            final rawChip = tester.widget<RawChip>(
              find.descendant(of: chip, matching: find.byType(RawChip)),
            );
            if (rawChip.selected) {
              expect(rawChip.checkmarkColor, isNotNull);
              expect(
                contrast(rawChip.checkmarkColor!, background),
                greaterThanOrEqualTo(3),
                reason: 'The selected filter checkmark must remain visible',
              );
            }
          }
        }

        expectReadableChips();
        expect(completed.hitTestable(), findsNothing);
        await tester.drag(filters, const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(completed.hitTestable(), findsOneWidget);
        await tester.tap(completed);
        await tester.pumpAndSettle();

        expect(tester.widget<ChoiceChip>(completed).selected, isTrue);
        expect(tester.widget<ChoiceChip>(all).selected, isFalse);
        expect(find.text('1 matching repair'), findsOneWidget);
        expect(find.text('SR-2'), findsOneWidget);
        expect(find.text('SR-1'), findsNothing);
        expectReadableChips();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Empty repairs remain pull-to-refreshable', (tester) async {
    final repairs = _Repairs();
    await pumpList(tester, repairs: repairs);
    expect(find.text('No repairs yet'), findsOneWidget);
    repairs.data = [_repair()];
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(repairs.loads, 2);
    expect(find.text('SR-1'), findsOneWidget);
  });

  testWidgets('Appointment cards open details and refresh when returning', (
    tester,
  ) async {
    final appointments = _Appointments()..data = [_appointment()];
    await pumpList(tester, appointments: appointments);
    await tapVisible(tester, find.text(_appointment().title));
    expect(find.text('Appointment 7'), findsOneWidget);
    await tester.tap(find.text('Update and return'));
    await tester.pumpAndSettle();

    expect(appointments.loads, 2);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Failed appointment refresh keeps the last list and supports retry',
    (tester) async {
      final appointments = _Appointments()..data = [_appointment()];
      await pumpList(tester, appointments: appointments);
      appointments.fail = true;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(find.text(_appointment().title), findsOneWidget);
      expect(
        find.text(
          'Could not refresh appointments. Showing your last loaded list.',
        ),
        findsOneWidget,
      );
      expect(find.text('No appointments yet'), findsNothing);
      appointments
        ..fail = false
        ..data = [_appointment(status: 'Confirmed')];
      await tapVisible(tester, find.text('Try again'));
      expect(appointments.loads, 3);
      expect(find.text('Confirmed'), findsOneWidget);
    },
  );

  testWidgets(
    'Empty appointments can refresh and have one primary booking action',
    (tester) async {
      final appointments = _Appointments();
      await pumpList(tester, appointments: appointments);
      expect(find.text('No appointments yet'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(appointments.loads, 2);
      expect(find.text('Book appointment'), findsOneWidget);
      expect(
        tester.getSize(find.byType(ElevatedButton)).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.text('Book appointment'));
      await tester.pumpAndSettle();
      expect(find.text('Book a repair visit'), findsOneWidget);
      await tester.tap(find.text('Finish booking'));
      await tester.pumpAndSettle();
      expect(find.text(_appointment().title), findsOneWidget);
      expect(appointments.loads, 3);
    },
  );

  testWidgets(
    'Slow repair requests stop loading and can recover after timeout',
    (tester) async {
      final request = Completer<void>();
      final repairs = _Repairs()..pending = request;
      await pumpList(tester, repairs: repairs, settle: false);
      await tester.pump();
      expect(find.byType(ShimmerListLoading), findsOneWidget);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();

      expect(find.text('Repairs unavailable'), findsOneWidget);
      expect(find.byType(ShimmerListLoading), findsNothing);
      request.complete();
      repairs
        ..pending = null
        ..data = [_repair()];
      await tapVisible(tester, find.text('Try again'));
      expect(find.text('SR-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final list in ['repairs', 'appointments']) {
    testWidgets('$list fit narrow dark screens with large text', (
      tester,
    ) async {
      await pumpList(
        tester,
        repairs: list == 'repairs'
            ? (_Repairs()..data = [_repair(status: 'In Progress')])
            : null,
        appointments: list == 'appointments'
            ? (_Appointments()..data = [_appointment()])
            : null,
        size: const Size(320, 720),
        textScale: 1.5,
        dark: true,
      );
      expect(tester.takeException(), isNull);
      if (list == 'repairs') {
        for (final chip in find.byType(ChoiceChip).evaluate()) {
          expect(
            tester.getSize(find.byWidget(chip.widget)).height,
            greaterThanOrEqualTo(48),
          );
        }
        await tester.scrollUntilVisible(
          find.text('SR-1'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      } else {
        await tester.ensureVisible(find.text(_appointment().timeSlot!));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Repair loading ignores a response after the screen is disposed',
    (tester) async {
      final request = Completer<void>();
      final repairs = _Repairs()..pending = request;
      await pumpList(tester, repairs: repairs, settle: false);
      await tester.pumpWidget(const SizedBox.shrink());
      request.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
