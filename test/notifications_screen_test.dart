import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/shimmer_loading.dart';
import 'package:flutter_101repairshop/features/notifications/presentation/notifications_screen.dart';

class _Notifications extends NotificationsRepository {
  String? user = 'user-1';
  List<AppNotification> data = [];
  bool failLoad = false;
  bool failMark = false;
  bool stopped = false;
  int loads = 0;
  final marks = <int?>[];
  Completer<List<AppNotification>>? pending;
  VoidCallback? changed;

  @override
  String? get currentUserId => user;

  @override
  Future<List<AppNotification>> loadNotifications() async {
    loads++;
    if (pending != null) return pending!.future;
    if (failLoad) throw StateError('offline');
    return data;
  }

  @override
  Future<Set<int>> markRead({int? id}) async {
    marks.add(id);
    if (failMark) throw StateError('write failed');
    return data
        .where((item) => id == null || item.id == id)
        .map((item) => item.id)
        .toSet();
  }

  @override
  Future<void> Function() watchChanges(VoidCallback onChange) {
    changed = onChange;
    return () async {
      stopped = true;
    };
  }
}

AppNotification _notification({
  int id = 1,
  String title = 'Appointment confirmed',
  String type = 'appointment',
  bool read = false,
  int? appointment = 7,
  int? report,
  int? transaction,
}) => AppNotification(
  id: id,
  title: title,
  message: 'Open your appointment to view its latest status, date and time.',
  type: type,
  isRead: read,
  createdAt: DateTime.utc(2026, 10, 9, 2),
  appointmentId: appointment,
  reportId: report,
  transactionId: transaction,
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
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> pumpInbox(
    WidgetTester tester,
    _Notifications repository, {
    bool settle = true,
    bool narrow = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(320, 720)
        : const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Sign in page')),
        ),
        GoRoute(
          path: '/appointments/:id',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                Text('Appointment ${state.pathParameters['id']}'),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Return to inbox'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/repairs/:id',
          builder: (_, state) =>
              Scaffold(body: Text('Repair ${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/profile/transactions',
          builder: (_, _) => const Scaffold(body: Text('Payment history')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: narrow ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.5 : 1)),
            child: child!,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  test('notification decoding keeps numeric deep links when marked read', () {
    final notification = AppNotification.fromJson({
      'id': 3,
      'title': 'Repair updated',
      'type': 'repair',
      'report_id': 12,
      'created_at': '2026-10-09T02:00:00Z',
    });
    expect(notification.destination, '/repairs/12');
    expect(notification.withRead().destination, '/repairs/12');
    expect(notification.withRead().isRead, isTrue);
    expect(_notification(appointment: null).destination, isNull);
    expect(_notification(appointment: -1).destination, isNull);
  });

  testWidgets('failed load offers retry and recovers the inbox', (
    tester,
  ) async {
    final repository = _Notifications()..failLoad = true;
    await pumpInbox(tester, repository);
    expect(find.text('Notifications unavailable'), findsOneWidget);
    expect(find.text('You’re all caught up'), findsNothing);
    repository
      ..failLoad = false
      ..data = [_notification()];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment confirmed'), findsOneWidget);
    expect(repository.loads, 2);
  });

  testWidgets('failed refresh preserves the inbox and supports another retry', (
    tester,
  ) async {
    final repository = _Notifications()..data = [_notification()];
    await pumpInbox(tester, repository);
    repository.failLoad = true;
    repository.changed!();
    await tester.pumpAndSettle();
    expect(
      find.text('Showing previously loaded notifications.'),
      findsOneWidget,
    );
    expect(find.text('Appointment confirmed'), findsOneWidget);
    repository
      ..failLoad = false
      ..data = [_notification(title: 'Appointment cancelled')];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Appointment cancelled'), findsOneWidget);
    expect(find.text('Showing previously loaded notifications.'), findsNothing);
  });

  testWidgets('single read and mark all wait for confirmed repository writes', (
    tester,
  ) async {
    final repository = _Notifications()
      ..data = [_notification(), _notification(id: 2, title: 'Repair updated')];
    await pumpInbox(tester, repository);
    await tester.tap(find.text('Mark as read').first);
    await tester.pumpAndSettle();
    expect(repository.marks, [1]);
    expect(find.text('Unread'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark all as read'));
    await tester.pumpAndSettle();
    expect(repository.marks, [1, null]);
    expect(find.text('Unread'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Mark all as read',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('failed read leaves the entry unread with a recovery message', (
    tester,
  ) async {
    final repository = _Notifications()
      ..data = [_notification()]
      ..failMark = true;
    await pumpInbox(tester, repository);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(find.text('Unread'), findsOneWidget);
    expect(
      find.text(
        'We could not mark the notification as read. Please try again.',
      ),
      findsOneWidget,
    );
  });

  for (final type in ['appointment', 'repair', 'payment']) {
    testWidgets(
      '$type notifications open their relevant details after marking read',
      (tester) async {
        final notification = _notification(
          type: type,
          appointment: type == 'appointment' ? 7 : null,
          report: type == 'repair' ? 12 : null,
          transaction: type == 'payment' ? 9 : null,
        );
        final repository = _Notifications()..data = [notification];
        await pumpInbox(tester, repository);
        await tester.tap(find.text(notification.title));
        await tester.pumpAndSettle();
        expect(repository.marks, [1]);
        expect(
          find.text(switch (type) {
            'appointment' => 'Appointment 7',
            'repair' => 'Repair 12',
            _ => 'Payment history',
          }),
          findsOneWidget,
        );
        if (type == 'appointment') {
          await tester.tap(find.text('Return to inbox'));
          await tester.pumpAndSettle();
          expect(repository.loads, 2);
        }
      },
    );
  }

  testWidgets(
    'realtime updates reload the inbox and disposal removes the watcher',
    (tester) async {
      final repository = _Notifications();
      await pumpInbox(tester, repository);
      expect(find.text('You’re all caught up'), findsOneWidget);
      repository.data = [_notification()];
      repository.changed!();
      await tester.pumpAndSettle();
      expect(find.text('Appointment confirmed'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(repository.stopped, isTrue);
      repository.changed!();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching accounts discards in-flight results and sign-out clears the inbox',
    (tester) async {
      final oldRequest = Completer<List<AppNotification>>();
      final repository = _Notifications()..pending = oldRequest;
      await pumpInbox(tester, repository, settle: false);
      await tester.pump();
      expect(find.byType(ShimmerListLoading), findsOneWidget);
      repository
        ..user = 'user-2'
        ..pending = null
        ..data = [_notification(title: 'New account update')];
      repository.changed!();
      await tester.pumpAndSettle();
      expect(find.text('New account update'), findsOneWidget);
      oldRequest.complete([
        _notification(title: 'Previous account private update'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Previous account private update'), findsNothing);
      expect(find.text('New account update'), findsOneWidget);
      repository.user = null;
      repository.changed!();
      await tester.pumpAndSettle();
      expect(find.text('New account update'), findsNothing);
      expect(
        find.text('Sign in again to view your notifications.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in page'), findsOneWidget);
    },
  );

  testWidgets('notification cards fit a narrow dark screen with large text', (
    tester,
  ) async {
    final repository = _Notifications()..data = [_notification()];
    await pumpInbox(tester, repository, narrow: true);
    await tester.ensureVisible(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test(
    'repository reads and writes the customer table with an owner filter',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = _NotificationServer();
        await server.start();
        final client = SupabaseClient(
          server.url,
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        try {
          final repository = NotificationsRepository(supabase: client);
          expect(await repository.loadNotifications(), isEmpty);
          expect(server.requests, isEmpty);
          await client.auth.signInWithPassword(
            email: 'owner@example.test',
            password: 'test-password',
          );
          final notifications = await repository.loadNotifications();
          expect(notifications.single.destination, '/appointments/7');
          final load = server.requests.last;
          expect(load.uri.path, '/rest/v1/customer_notifications');
          expect(load.uri.queryParameters['user_id'], 'eq.user-1');
          expect(load.uri.queryParameters['created_at'], startsWith('lte.'));
          expect(load.uri.queryParameters['limit'], '50');
          expect(await repository.markRead(id: 3), {3});
          final mark = server.requests.last;
          expect(mark.method, 'PATCH');
          expect(mark.uri.path, '/rest/v1/customer_notifications');
          expect(mark.uri.queryParameters['user_id'], 'eq.user-1');
          expect(mark.uri.queryParameters['is_read'], 'eq.false');
          expect(mark.uri.queryParameters['id'], 'eq.3');
          expect(mark.body, {'is_read': true});
        } finally {
          await client.dispose();
          await server.close();
        }
      }, _RealHttpOverrides());
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}

class _NotificationRequest {
  _NotificationRequest(this.method, this.uri, this.body);
  final String method;
  final Uri uri;
  final Object? body;
}

class _NotificationServer {
  late HttpServer _server;
  final requests = <_NotificationRequest>[];
  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/auth/v1/token') {
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'sub': 'user-1', 'exp': expiry})))
          .replaceAll('=', '');
      await _respond(request, {
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test-signature',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': 'user-1',
          'aud': 'authenticated',
          'email': 'owner@example.test',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      });
      return;
    }
    requests.add(
      _NotificationRequest(
        request.method,
        request.uri,
        body.isEmpty ? null : jsonDecode(body),
      ),
    );
    if (request.uri.path == '/rest/v1/customer_notifications') {
      await _respond(
        request,
        request.method == 'PATCH'
            ? [
                {'id': 3},
              ]
            : [
                {
                  'id': 3,
                  'title': 'Appointment confirmed',
                  'type': 'appointment',
                  'appointment_id': 7,
                  'created_at': '2026-10-09T02:00:00Z',
                },
              ],
      );
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await _respond(request, {'message': 'Unknown test route'});
  }

  Future<void> _respond(HttpRequest request, Object value) async {
    request.response.write(jsonEncode(value));
    await request.response.close();
  }
}
