import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/features/appointments/data/appointments_repository.dart';
import 'package:flutter_101repairshop/features/appointments/presentation/appointment_detail_screen.dart';
import 'package:flutter_101repairshop/features/repairs/data/repairs_repository.dart';
import 'package:flutter_101repairshop/features/repairs/presentation/repair_detail_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/appointment.dart';
import 'package:flutter_101repairshop/features/shared/models/service_report.dart';

class _Appointments extends AppointmentsRepository {
  bool fail = false;
  @override
  Future<List<Appointment>> getAppointments() async {
    if (fail) throw StateError('offline');
    return [
      Appointment(
        id: 1,
        customerId: 'customer',
        title: 'Air conditioner keeps leaking after several minutes',
        appointmentDate: DateTime(2026, 10, 5),
        status: 'Pending',
        timeSlot: '9:00 AM - 10:00 AM',
        notes: 'Please call before arriving.',
      ),
    ];
  }
}

class _Repairs extends RepairsRepository {
  bool fail = false;
  @override
  Future<ServiceReport?> getRepairById(int id) async {
    if (fail) throw StateError('offline');
    return ServiceReport(
      id: id,
      customerId: 'customer',
      status: 'In Progress',
      findings: 'The fan motor needs replacement.',
      dateIn: DateTime(2026, 9, 20),
    );
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
  tearDownAll(() => Supabase.instance.dispose());

  for (final repair in [true, false]) {
    final title = repair ? 'Repair' : 'Appointment';
    testWidgets(
      '$title details recover from a read failure and fit large text',
      (tester) async {
        final repairs = _Repairs()..fail = true;
        final appointments = _Appointments()..fail = true;
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repairsRepositoryProvider.overrideWithValue(repairs),
              appointmentsRepositoryProvider.overrideWithValue(appointments),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: repair
                  ? const RepairDetailScreen(reportId: 1)
                  : const AppointmentDetailScreen(appointmentId: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Report not found'), findsNothing);
        expect(find.text('Appointment not found'), findsNothing);
        repairs.fail = false;
        appointments.fail = false;
        await tester.ensureVisible(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Try again').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsNothing);
        final target = repair
            ? find.text('The fan motor needs replacement.')
            : find.text('Please call before arriving.');
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(target, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
