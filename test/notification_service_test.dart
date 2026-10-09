import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_101repairshop/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late NotificationService service;
  late _Notifier notifier;
  late List<Map<String, dynamic>> appointments;
  late List<Uri> reads;

  setUp(() async {
    notifier = _Notifier();
    appointments = [_appointment(1)];
    reads = [];
    client = SupabaseClient(
      'http://notification.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        reads.add(request.url);
        if (request.url.path.endsWith('/customers')) {
          return http.Response(
            jsonEncode([
              {'id': 'customer-1'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.url.path.endsWith('/appointments')) {
          return http.Response(
            jsonEncode(appointments),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.setInitialSession(_session('user-1'));
    service = NotificationService(
      notifier: notifier,
      supabase: client,
      now: () => DateTime.utc(2026, 10, 10),
    );
  });

  tearDown(() async {
    await service.dispose();
    await client.dispose();
  });

  Future<ReminderScheduleResult> schedule({
    int minutes = 15,
    String? slot = '8:00 AM - 9:00 AM',
    DateTime? date,
  }) => service.scheduleAppointmentReminder(
    appointmentId: 1,
    title: 'Fan repair',
    appointmentDate: date ?? DateTime(2026, 10, 11),
    timeSlot: slot,
    reminderMinutes: minutes,
  );

  test('initialization never prompts for notification permission', () async {
    await service.init();
    await service.init();
    expect(notifier.initializations, 1);
    expect(notifier.permissionRequests, 0);
  });

  test(
    'permission denial remains unavailable instead of reporting success',
    () async {
      notifier.enabled = false;
      expect(await schedule(), ReminderScheduleResult.unavailable);
      expect(notifier.modes, isEmpty);
    },
  );

  test('invalid slot is not scheduled at an invented default hour', () async {
    expect(await schedule(slot: '13:99 PM'), ReminderScheduleResult.invalid);
    expect(notifier.modes, isEmpty);
  });

  test(
    'elapsed reminder cancels an older pending alarm for that appointment',
    () async {
      notifier.requests[1] = const PendingNotificationRequest(
        1,
        'old',
        'old',
        'appointment:user-1:1',
      );
      expect(
        await schedule(date: DateTime(2026, 10, 10)),
        ReminderScheduleResult.tooLate,
      );
      expect(notifier.cancelled, [1]);
      expect(notifier.requests, isEmpty);
    },
  );

  test('when available exact permission uses exact idle scheduling', () async {
    notifier.exact = true;
    expect(await schedule(), ReminderScheduleResult.scheduled);
    expect(notifier.modes, [AndroidScheduleMode.exactAllowWhileIdle]);
    expect(notifier.requests[1]!.payload, 'appointment:user-1:1');
    expect(notifier.lastDate!.toUtc(), DateTime.utc(2026, 10, 10, 23, 45));
  });

  test('unavailable exact permission uses inexact scheduling without a settings prompt', () async {
    expect(await schedule(), ReminderScheduleResult.scheduled);
    expect(notifier.modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
    expect(notifier.permissionRequests, 0);
  });

  test(
    'exact permission revoked during scheduling falls back to inexact',
    () async {
      notifier.exact = true;
      notifier.rejectExact = true;
      expect(await schedule(), ReminderScheduleResult.scheduled);
      expect(notifier.modes, [
        AndroidScheduleMode.exactAllowWhileIdle,
        AndroidScheduleMode.inexactAllowWhileIdle,
      ]);
    },
  );

  test(
    'delivery exception returns failure without throwing after the booking',
    () async {
      notifier.fail = true;
      expect(await schedule(), ReminderScheduleResult.failed);
    },
  );

  test(
    'same deadline and content do not schedule the same reminder twice',
    () async {
      await schedule();
      await schedule();
      expect(notifier.modes, hasLength(1));
      await schedule(minutes: 30);
      expect(notifier.modes, hasLength(2));
      expect(notifier.requests, hasLength(1));
    },
  );

  test(
    'reminders reconcile via auth_id and never insert future inbox rows',
    () async {
      await service.rescheduleAll();
      await service.rescheduleAll();
      expect(reads.first.queryParameters['auth_id'], 'eq.user-1');
      expect(reads.first.queryParameters['deleted_at'], 'is.null');
      expect(reads.any((uri) => uri.path.contains('notifications')), isFalse);
      expect(notifier.modes, hasLength(1));
    },
  );

  test('admin cancellation removes the pending reminder', () async {
    await service.rescheduleAll();
    appointments.single['status'] = 'Cancelled';
    await service.rescheduleAll();
    expect(notifier.cancelled, [1]);
    expect(notifier.requests, isEmpty);
  });

  test(
    'admin completion and removed reminder both remove pending alarms',
    () async {
      appointments.add(_appointment(2));
      await service.rescheduleAll();
      appointments[0]['status'] = 'Completed';
      appointments[1]['reminder_minutes'] = null;
      await service.rescheduleAll();
      expect(notifier.cancelled, containsAll([1, 2]));
    },
  );

  test('admin rescheduling replaces the appointment deadline', () async {
    await service.rescheduleAll();
    appointments.single['time_slot'] = '1:00 PM - 2:00 PM';
    await service.rescheduleAll();
    expect(notifier.modes, hasLength(2));
    expect(notifier.lastDate!.toUtc(), DateTime.utc(2026, 10, 11, 4, 45));
  });

  test(
    'authentication callback errors do not become uncaught reminder errors',
    () async {
      await schedule();
      notifier.failPending =
          true; // Keep this test isolated from realtime sockets.
      service.startSessionSync();
      await service.rescheduleAll();
      // Inject the SDK error channel without a real failed auth request.
      // ignore: invalid_use_of_internal_member
      client.auth.notifyException(
        const AuthException('Simulated callback failure'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.requests[1]?.payload, 'appointment:user-1:1');
    },
  );

  test(
    'account cleanup failures are handled without allowing old reminder taps',
    () async {
      await schedule();
      notifier.failPending = true;
      service.startSessionSync();
      await service.rescheduleAll();
      notifier.failCancelAll = true;
      await client.auth.signOut(scope: SignOutScope.local);
      await service
          .rescheduleAll(); // Also waits for serialized account cleanup.
      expect(notifier.cancelAllCalls, greaterThanOrEqualTo(1));
      final opened = <int>[];
      service.setAppointmentOpenHandler(opened.add);
      notifier.onOpened!('appointment:user-1:1');
      expect(opened, isEmpty);
    },
  );
  test('signed-out reconciliation clears account reminders', () async {
    await schedule();
    await client.auth.signOut(scope: SignOutScope.local);
    await service.rescheduleAll();
    expect(notifier.cancelAllCalls, 1);
    expect(notifier.requests, isEmpty);
  });

  test(
    'account changes during delivery cannot leave the old account alarm',
    () async {
      notifier.hold = Completer<void>();
      final pending = schedule();
      await notifier.started.future;
      await client.auth.setInitialSession(_session('user-2'));
      notifier.hold!.complete();
      expect(await pending, ReminderScheduleResult.unavailable);
      expect(notifier.cancelled, [1]);
      expect(notifier.requests, isEmpty);
    },
  );

  test(
    'a cold-start reminder opens its appointment when the router attaches',
    () async {
      notifier.launchPayload = 'appointment:user-1:9';
      await service.init();
      final opened = <int>[];
      service.setAppointmentOpenHandler(opened.add);
      expect(opened, [9]);
      notifier.onOpened!('appointment:user-2:8');
      notifier.onOpened!('invalid');
      expect(opened, [9]);
    },
  );
}

Map<String, dynamic> _appointment(int id) => {
  'id': id,
  'customer_id': 'customer-1',
  'title': 'Fan repair',
  'appointment_date': '2026-10-11T00:00:00+08:00',
  'time_slot': '8:00 AM - 9:00 AM',
  'status': 'Pending',
  'reminder_minutes': 15,
};

String _session(String user) {
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': user, 'exp': expiry})))
      .replaceAll('=', '');
  return jsonEncode({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
    'refresh_token': 'test-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': user,
      'aud': 'authenticated',
      'email': 'test@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  });
}

class _Notifier implements ReminderNotifier {
  bool enabled = true, exact = false, rejectExact = false, fail = false;
  bool failPending = false, failCancelAll = false;
  int initializations = 0, permissionRequests = 0, cancelAllCalls = 0;
  final requests = <int, PendingNotificationRequest>{};
  final cancelled = <int>[];
  final modes = <AndroidScheduleMode>[];
  tz.TZDateTime? lastDate;
  Completer<void>? hold;
  final started = Completer<void>();
  void Function(String?)? onOpened;
  String? launchPayload;

  @override
  Future<void> initialize(void Function(String?) onOpened) async {
    initializations++;
    this.onOpened = onOpened;
    if (launchPayload != null) onOpened(launchPayload);
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return enabled;
  }

  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<bool> canScheduleExactly() async => exact;
  @override
  Future<List<PendingNotificationRequest>> pending() async {
    if (failPending) throw PlatformException(code: 'pending_failed');
    return requests.values.toList();
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    requests.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    if (failCancelAll) throw PlatformException(code: 'cancel_failed');
    requests.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String body,
    required tz.TZDateTime date,
    required String payload,
    required AndroidScheduleMode mode,
  }) async {
    modes.add(mode);
    lastDate = date;
    if (!started.isCompleted) started.complete();
    await hold?.future;
    if (fail) throw PlatformException(code: 'delivery_failed');
    if (rejectExact && mode == AndroidScheduleMode.exactAllowWhileIdle) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    requests[id] = PendingNotificationRequest(
      id,
      'Appointment reminder',
      body,
      payload,
    );
  }
}
