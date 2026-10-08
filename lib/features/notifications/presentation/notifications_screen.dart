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

  AppNotification({
    required this.id,
    required this.title,
    this.message,
    this.type = 'info',
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      message: json['message'],
      type: json['type'] ?? 'info',
      isRead: json['is_read'] ?? false,
      createdAt: AppDates.parseTimestamp(json['created_at']),
    );
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

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_isRefreshing) return;
    setState(() {
      _isLoading = _notifications.isEmpty;
      _isRefreshing = true;
      _loadError = null;
      _needsSignIn = false;
    });
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        _notifications = [];
        _needsSignIn = true;
        _loadError = 'Sign in again to view your notifications.';
        return;
      }
      final data = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _notifications = data.map(AppNotification.fromJson).toList();
    } on TimeoutException {
      _loadError = 'Notifications are taking longer than expected. Check your connection and try again.';
    } catch (_) {
      _loadError = 'We couldn’t load your notifications. Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
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
                if (notification.message?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    notification.message!,
                    style: theme.textTheme.bodyMedium,
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
