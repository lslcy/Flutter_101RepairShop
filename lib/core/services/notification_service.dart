import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/shared/models/appointment.dart';
import '../constants/statuses.dart';
import '../utils/app_dates.dart';
import '../utils/appointment_reminder_time.dart';
import 'customer_account_service.dart';

final notificationServiceProvider = Provider(
  (ref) => NotificationService.instance,
);

enum ReminderScheduleResult { scheduled, tooLate, unavailable, invalid, failed }

/// A small boundary around the device API so delivery failures can be tested.
abstract class ReminderNotifier {
  Future<void> initialize(void Function(String? payload) onOpened);
  Future<bool> requestPermission();
  Future<bool> isEnabled();
  Future<bool> canScheduleExactly();
  Future<List<PendingNotificationRequest>> pending();
  Future<void> schedule({
    required int id,
    required String body,
    required tz.TZDateTime date,
    required String payload,
    required AndroidScheduleMode mode,
  });
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class DeviceReminderNotifier implements ReminderNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<void> initialize(void Function(String? payload) onOpened) async {
    if (!_supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onOpened(response.payload),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      onOpened(launch?.notificationResponse?.payload);
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  @override
  Future<bool> isEnabled() async {
    if (!_supported) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    return (await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.checkPermissions())
            ?.isEnabled ??
        false;
  }

  @override
  Future<bool> canScheduleExactly() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.canScheduleExactNotifications() ??
      false;

  @override
  Future<List<PendingNotificationRequest>> pending() async =>
      _supported ? await _plugin.pendingNotificationRequests() : [];

  @override
  Future<void> schedule({
    required int id,
    required String body,
    required tz.TZDateTime date,
    required String payload,
    required AndroidScheduleMode mode,
  }) => _plugin.zonedSchedule(
    id: id,
    title: 'Appointment reminder',
    body: body,
    scheduledDate: date,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'appointment_reminders',
        'Appointment reminders',
        channelDescription: 'Reminders before your repair appointments',
        icon: 'ic_notification',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    androidScheduleMode: mode,
    payload: payload,
  );

  @override
  Future<void> cancel(int id) async {
    if (_supported) await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    if (_supported) await _plugin.cancelAll();
  }
}

/// Keeps local reminders aligned with this customer's current bookings.
/// Scheduling never inserts future-dated or duplicate notifications in Supabase.
class NotificationService with WidgetsBindingObserver {
  NotificationService({
    ReminderNotifier? notifier,
    SupabaseClient? supabase,
    DateTime Function()? now,
  }) : _notifier = notifier ?? DeviceReminderNotifier(),
       _providedClient = supabase,
       _now = now ?? DateTime.now;

  static final instance = NotificationService();
  final ReminderNotifier _notifier;
  final SupabaseClient? _providedClient;
  final DateTime Function() _now;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;
  Future<void>? _initialization;
  Future<void> _operations = Future.value();
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _appointmentsChannel;
  Timer? _refreshTimer;
  String? _sessionUser;
  String? _channelCustomer;
  int _sessionVersion = 0;
  final _scheduled = <int, String>{};
  void Function(int id)? _openHandler;
  (String, int)? _pendingOpen;

  Future<void> init() => _initialization ??= _notifier
      .initialize(_onOpened)
      .catchError((Object error) {
        _initialization = null;
        debugPrint('Appointment reminders could not be initialized.');
      });

  void setAppointmentOpenHandler(void Function(int id)? handler) {
    _openHandler = handler;
    final pending = _pendingOpen;
    if (handler != null && pending != null) {
      _pendingOpen = null;
      if (_client.auth.currentUser?.id == pending.$1) handler(pending.$2);
    }
  }

  void _onOpened(String? payload) {
    final pieces = payload?.split(':');
    if (pieces == null || pieces.length != 3 || pieces.first != 'appointment') {
      return;
    }
    final id = int.tryParse(pieces[2]);
    if (id == null || _client.auth.currentUser?.id != pieces[1]) return;
    if (_openHandler case final handler?) {
      handler(id);
    } else {
      _pendingOpen = (pieces[1], id);
    }
  }

  /// Start after runApp. Permissions are requested only when choosing a reminder.
  void startSessionSync() {
    if (_authSubscription != null) return;
    WidgetsBinding.instance.addObserver(this);
    _sessionUser = _client.auth.currentUser?.id;
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (state) {
        final user = state.session?.user.id;
        if (user != _sessionUser) {
          _sessionUser = user;
          _sessionVersion++;
          _pendingOpen = null;
          unawaited(
            _serialize(() async {
              try {
                await _notifier.cancelAll();
              } catch (_) {
                debugPrint(
                  'Device reminders could not be cleared after account change.',
                );
              } finally {
                _scheduled.clear();
                await _removeChannel();
              }
            }),
          );
        }
        unawaited(rescheduleAll());
      },
      onError: (Object error, StackTrace stack) {
        // The authentication screens own callback and refresh error feedback.
        // A callback failure does not itself change reminder ownership.
        debugPrint(
          'Authentication feedback received while checking reminders.',
        );
      },
    );
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(rescheduleAll());
      }
    });
    unawaited(rescheduleAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(rescheduleAll());
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<bool> requestPermission() async {
    try {
      await init();
      final allowed = await _notifier.requestPermission();
      if (allowed) unawaited(rescheduleAll());
      return allowed;
    } catch (_) {
      return false;
    }
  }

  Future<ReminderScheduleResult> scheduleAppointmentReminder({
    required int appointmentId,
    required String title,
    required DateTime appointmentDate,
    String? timeSlot,
    required int reminderMinutes,
  }) {
    final user = _client.auth.currentUser?.id;
    return _serialize(
      () => _schedule(
        appointmentId: appointmentId,
        title: title,
        appointmentDate: appointmentDate,
        timeSlot: timeSlot,
        reminderMinutes: reminderMinutes,
        owner: user,
      ),
    );
  }

  Future<ReminderScheduleResult> _schedule({
    required int appointmentId,
    required String title,
    required DateTime appointmentDate,
    String? timeSlot,
    required int reminderMinutes,
    required String? owner,
  }) async {
    final version = _sessionVersion;
    try {
      await init();
      if (owner == null || _client.auth.currentUser?.id != owner) {
        return ReminderScheduleResult.unavailable;
      }
      final deadline = AppointmentReminderTime.reminderTime(
        appointmentDate,
        timeSlot,
        reminderMinutes,
      );
      if (deadline == null || appointmentId < 1 || appointmentId > 2147483647) {
        return ReminderScheduleResult.invalid;
      }
      if (!deadline.isAfter(_now())) {
        await _notifier.cancel(appointmentId);
        _scheduled.remove(appointmentId);
        return ReminderScheduleResult.tooLate;
      }
      if (!await _notifier.isEnabled()) {
        return ReminderScheduleResult.unavailable;
      }
      final body =
          'Your repair appointment "$title" starts at ${timeSlot!.split(RegExp(r'\s*[-–—]\s*')).first.trim()}. '
          'Reminder: $reminderMinutes minutes before.';
      final fingerprint = '$owner|${deadline.millisecondsSinceEpoch}|$body';
      if (_scheduled[appointmentId] == fingerprint) {
        return ReminderScheduleResult.scheduled;
      }
      final exact = await _notifier.canScheduleExactly();
      if (version != _sessionVersion || _client.auth.currentUser?.id != owner) {
        return ReminderScheduleResult.unavailable;
      }
      Future<void> schedule(AndroidScheduleMode mode) => _notifier.schedule(
        id: appointmentId,
        body: body,
        date: deadline,
        payload: 'appointment:$owner:$appointmentId',
        mode: mode,
      );
      try {
        await schedule(
          exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on PlatformException catch (error) {
        if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      }
      if (version != _sessionVersion || _client.auth.currentUser?.id != owner) {
        await _notifier.cancel(appointmentId);
        return ReminderScheduleResult.unavailable;
      }
      _scheduled[appointmentId] = fingerprint;
      return ReminderScheduleResult.scheduled;
    } catch (_) {
      debugPrint(
        'The appointment was saved, but its device reminder could not be scheduled.',
      );
      return ReminderScheduleResult.failed;
    }
  }

  Future<void> cancelReminder(int appointmentId) => _serialize(() async {
    try {
      await init();
      await _notifier.cancel(appointmentId);
    } catch (_) {
      debugPrint('A device reminder could not be cancelled.');
    }
    _scheduled.remove(appointmentId);
  });

  Future<void> rescheduleAll() => _serialize(() async {
    try {
      await init();
      final user = _client.auth.currentUser?.id;
      final version = _sessionVersion;
      if (user == null) {
        await _notifier.cancelAll();
        _scheduled.clear();
        await _removeChannel();
        return;
      }
      final customer = await CustomerAccountService(supabase: _client)
          .currentCustomerId();
      if (version != _sessionVersion || _client.auth.currentUser?.id != user) {
        return;
      }
      if (customer == null) {
        await _notifier.cancelAll();
        _scheduled.clear();
        await _removeChannel();
        return;
      }
      final rows = await _client
          .from('appointments')
          .select()
          .eq('customer_id', customer)
          .gte(
            'appointment_date',
            AppDates.toDateString(AppDates.manilaDateOf(_now())),
          );
      if (version != _sessionVersion || _client.auth.currentUser?.id != user) {
        return;
      }
      final appointments = rows.map(Appointment.fromJson).toList();
      final desired = <int>{};
      for (final appointment in appointments) {
        if (appointment.reminderMinutes == null ||
            !AppointmentStatus.canCancel(appointment.status)) {
          continue;
        }
        final date = AppDates.manilaDateOf(appointment.appointmentDate);
        final deadline = AppointmentReminderTime.reminderTime(
          date,
          appointment.timeSlot,
          appointment.reminderMinutes!,
        );
        if (deadline != null && deadline.isAfter(_now())) {
          desired.add(appointment.id);
        }
      }
      final pending = await _notifier.pending();
      if (version != _sessionVersion || _client.auth.currentUser?.id != user) {
        return;
      }
      final pendingIds = pending.map((request) => request.id).toSet();
      _scheduled.removeWhere((id, _) => !pendingIds.contains(id));
      for (final request in pending) {
        // Legacy reminders had no payload; this app has no other local schedules.
        if ((request.payload?.startsWith('appointment:') ?? true) &&
            (!desired.contains(request.id) ||
                (request.payload != null &&
                    !request.payload!.startsWith('appointment:$user:')))) {
          await _notifier.cancel(request.id);
          _scheduled.remove(request.id);
        }
      }
      for (final appointment in appointments.where(
        (item) => desired.contains(item.id),
      )) {
        if (version != _sessionVersion ||
            _client.auth.currentUser?.id != user) {
          return;
        }
        await _schedule(
          appointmentId: appointment.id,
          title: appointment.title,
          appointmentDate: AppDates.manilaDateOf(appointment.appointmentDate),
          timeSlot: appointment.timeSlot,
          reminderMinutes: appointment.reminderMinutes!,
          owner: user,
        );
      }
      if (_authSubscription != null) _watchAppointments(customer);
    } catch (_) {
      debugPrint('Appointment reminders could not be refreshed.');
    }
  });

  void _watchAppointments(String customer) {
    if (_channelCustomer == customer) return;
    final old = _appointmentsChannel;
    if (old != null) {
      unawaited(
        _client.removeChannel(old).catchError((Object error) {
          debugPrint(
            'The previous reminder subscription could not be removed.',
          );
          return 'error';
        }),
      );
    }
    _channelCustomer = customer;
    _appointmentsChannel = _client
        .channel('customer-reminders-$customer')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customer,
          ),
          callback: (_) => unawaited(rescheduleAll()),
        )
        .subscribe();
  }

  Future<void> _removeChannel() async {
    final channel = _appointmentsChannel;
    _appointmentsChannel = null;
    _channelCustomer = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {
        debugPrint('The reminder subscription could not be removed.');
      }
    }
  }

  Future<void> dispose() async {
    _sessionVersion++;
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _removeChannel();
    _openHandler = null;
  }
}
