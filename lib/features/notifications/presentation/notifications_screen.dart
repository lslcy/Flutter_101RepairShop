import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';

class AppNotification {
  final int id;
  final String title;
  final String? message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final int? appointmentId;
  final int? reportId;
  final int? transactionId;

  AppNotification({
    required this.id,
    required this.title,
    this.message,
    this.type = 'info',
    this.isRead = false,
    this.createdAt,
    this.appointmentId,
    this.reportId,
    this.transactionId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] as num).toInt(),
      title: json['title'] ?? '',
      message: json['message'],
      type: json['type'] ?? 'info',
      isRead: json['is_read'] ?? false,
      createdAt: AppDates.parseTimestamp(json['created_at']),
      appointmentId: (json['appointment_id'] as num?)?.toInt(),
      reportId: (json['report_id'] as num?)?.toInt(),
      transactionId: (json['transaction_id'] as num?)?.toInt(),
    );
  }

  String? get destination {
    if (appointmentId != null && appointmentId! > 0) {
      return '/appointments/$appointmentId';
    }
    if (reportId != null && reportId! > 0) return '/repairs/$reportId';
    if (transactionId != null && transactionId! > 0) {
      return '/profile/transactions';
    }
    return null;
  }

  AppNotification withRead() => AppNotification(
    id: id,
    title: title,
    message: message,
    type: type,
    isRead: true,
    createdAt: createdAt,
    appointmentId: appointmentId,
    reportId: reportId,
    transactionId: transactionId,
  );
}

final notificationsRepositoryProvider = Provider(
  (ref) => NotificationsRepository(),
);

class NotificationsRepository {
  NotificationsRepository({SupabaseClient? supabase})
    : _client = supabase ?? Supabase.instance.client;
  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<AppNotification>> loadNotifications() async {
    final user = currentUserId;
    if (user == null) return [];
    final rows = await _client
        .from('customer_notifications')
        .select()
        .eq('user_id', user)
        .lte('created_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<Set<int>> markRead({int? id}) async {
    final user = currentUserId;
    if (user == null) throw StateError('Sign in again.');
    var query = _client
        .from('customer_notifications')
        .update({'is_read': true})
        .eq('user_id', user)
        .eq('is_read', false)
        .lte('created_at', DateTime.now().toUtc().toIso8601String());
    if (id != null) query = query.eq('id', id);
    final rows = await query.select('id');
    return rows.map((row) => (row['id'] as num).toInt()).toSet();
  }

  Future<void> Function() watchChanges(void Function() onChange) {
    RealtimeChannel? channel;
    String? watchedUser;
    var stopped = false;
    Future<void> removeChannel(RealtimeChannel previous) async {
      try {
        await _client.removeChannel(previous);
      } catch (_) {
        debugPrint('Notification updates could not be disconnected.');
      }
    }

    void watchUser() {
      final user = currentUserId;
      if (stopped || user == watchedUser) return;
      final previous = channel;
      channel = null;
      watchedUser = user;
      if (previous != null) unawaited(removeChannel(previous));
      if (user == null) return;
      channel = _client
          .channel('customer-notifications-$user')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customer_notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user,
            ),
            callback: (_) {
              if (!stopped && currentUserId == user) onChange();
            },
          )
          .subscribe();
    }

    watchUser();
    final authChanges = _client.auth.onAuthStateChange.listen(
      (_) {
        watchUser();
        if (!stopped) onChange();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!stopped) onChange();
      },
    );
    return () async {
      stopped = true;
      try {
        await authChanges.cancel();
      } finally {
        final previous = channel;
        if (previous != null) await removeChannel(previous);
      }
    };
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _needsSignIn = false;
  String? _loadError;
  final _markingRead = <int>{};
  bool _markingAllRead = false;
  Future<void> Function()? _stopWatching;
  String? _loadedUserId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _stopWatching = ref.read(notificationsRepositoryProvider).watchChanges(() {
      if (mounted) _loadNotifications();
    });
  }

  @override
  void dispose() {
    final stop = _stopWatching;
    if (stop != null) {
      unawaited(
        stop().catchError((Object error) {
          debugPrint('Notification updates could not be disconnected.');
        }),
      );
    }
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final repository = ref.read(notificationsRepositoryProvider);
    final userId = repository.currentUserId;
    final userChanged = _loadedUserId != userId;
    if (_isRefreshing && !userChanged) return;
    final generation = ++_loadGeneration;
    _loadedUserId = userId;
    setState(() {
      if (userChanged) {
        _notifications = [];
        _markingRead.clear();
        _markingAllRead = false;
      }
      _isLoading = _notifications.isEmpty;
      _isRefreshing = true;
      _loadError = null;
      _needsSignIn = false;
    });
    try {
      if (userId == null) {
        _notifications = [];
        _needsSignIn = true;
        _loadError = 'Sign in again to view your notifications.';
        return;
      }
      final data = await repository.loadNotifications().timeout(
        const Duration(seconds: 20),
      );
      if (!mounted ||
          generation != _loadGeneration ||
          repository.currentUserId != userId) {
        return;
      }
      _notifications = data;
    } on TimeoutException {
      if (generation != _loadGeneration || repository.currentUserId != userId) {
        return;
      }
      _loadError = 'Notifications are taking longer than expected. Check your connection and try again.';
    } catch (_) {
      if (generation != _loadGeneration || repository.currentUserId != userId) {
        return;
      }
      _loadError = 'We couldn’t load your notifications. Please try again.';
    } finally {
      if (mounted &&
          generation == _loadGeneration &&
          repository.currentUserId == userId) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _markRead({int? id}) async {
    if (_markingAllRead || (id != null && _markingRead.contains(id))) return;
    final repository = ref.read(notificationsRepositoryProvider);
    final user = repository.currentUserId;
    if (user == null) return;
    setState(() {
      if (id == null) {
        _markingAllRead = true;
      } else {
        _markingRead.add(id);
      }
    });
    try {
      final ids = await repository
          .markRead(id: id)
          .timeout(const Duration(seconds: 15));
      if (!mounted || repository.currentUserId != user) return;
      if (id != null && !ids.contains(id)) {
        throw StateError('Notification was not updated.');
      }
      setState(() {
        _notifications = _notifications
            .map((item) => ids.contains(item.id) ? item.withRead() : item)
            .toList();
      });
    } catch (_) {
      if (mounted && repository.currentUserId == user) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'We could not mark the notification as read. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && repository.currentUserId == user) {
        setState(() {
          _markingAllRead = false;
          if (id != null) _markingRead.remove(id);
        });
      }
    }
  }

  IconData _notificationIcon(String type) => switch (type) {
    'repair' => Icons.build_outlined,
    'appointment' => Icons.calendar_today_outlined,
    'payment' => Icons.payments_outlined,
    _ => Icons.notifications_outlined,
  };

  Future<void> _openNotification(AppNotification notification) async {
    final destination = notification.destination;
    if (destination == null) return;
    final repository = ref.read(notificationsRepositoryProvider);
    final userId = repository.currentUserId;
    if (userId == null || userId != _loadedUserId) return;
    if (!notification.isRead) await _markRead(id: notification.id);
    if (!mounted || repository.currentUserId != userId) return;
    if (destination == '/profile/transactions') {
      context.go(destination);
    } else {
      await context.push(destination);
      if (mounted) await _loadNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all_outlined),
            onPressed:
                _markingAllRead || !_notifications.any((item) => !item.isRead)
                ? null
                : () => _markRead(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _loadNotifications,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_isLoading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: AppSpacing.md),
                        child: ShimmerListLoading(
                          label: 'Loading notifications…',
                        ),
                      ),
                    )
                  else if (_notifications.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyOrErrorState(),
                    )
                  else ...[
                    if (_isRefreshing)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Semantics(
                            liveRegion: true,
                            child: Text('Refreshing notifications…'),
                          ),
                        ),
                      ),
                    if (_loadError != null)
                      SliverToBoxAdapter(child: _buildRefreshError()),
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverList.separated(
                        itemCount: _notifications.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _buildNotificationCard(_notifications[index]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshError() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: AppCard(
        color: theme.colorScheme.errorContainer,
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Showing previously loaded notifications.',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _loadError!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              TextButton.icon(
                onPressed: _loadNotifications,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(AppNotification notification) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      onTap: notification.destination == null
          ? null
          : () => _openNotification(notification),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              _notificationIcon(notification.type),
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!notification.isRead) ...[
                  Text(
                    'Unread',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(notification.title, style: theme.textTheme.titleMedium),
                if (notification.destination != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.type == 'payment'
                        ? 'View payments'
                        : 'View details',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
                if (notification.message?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    notification.message!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                if (!notification.isRead) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed:
                        _markingAllRead ||
                            _markingRead.contains(notification.id)
                        ? null
                        : () => _markRead(id: notification.id),
                    icon: const Icon(Icons.done_outlined),
                    label: Text(
                      _markingRead.contains(notification.id)
                          ? 'Marking as read...'
                          : 'Mark as read',
                    ),
                  ),
                ],
                if (notification.createdAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppDates.format(
                      notification.createdAt!,
                      'MMM d, yyyy · h:mm a',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyOrErrorState() {
    final theme = Theme.of(context);
    final hasError = _loadError != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.notifications_outlined,
              size: 48,
              color: hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasError ? 'Notifications unavailable' : 'You’re all caught up',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: hasError,
              child: Text(
                _loadError ?? 'Repair, appointment, and payment updates will appear here. Pull down to refresh.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _needsSignIn ? 'Sign in' : 'Try again',
                icon: _needsSignIn
                    ? Icons.login_outlined
                    : Icons.refresh_outlined,
                onPressed: _needsSignIn
                    ? () => context.go('/login')
                    : _loadNotifications,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
