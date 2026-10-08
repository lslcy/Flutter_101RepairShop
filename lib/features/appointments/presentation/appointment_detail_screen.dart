import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/app_dates.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/appointment.dart';
import '../data/appointments_repository.dart';

class AppointmentDetailScreen extends ConsumerStatefulWidget {
  final int appointmentId;
  const AppointmentDetailScreen({super.key, required this.appointmentId});

  @override
  ConsumerState<AppointmentDetailScreen> createState() =>
      _AppointmentDetailScreenState();
}

class _AppointmentDetailScreenState
    extends ConsumerState<AppointmentDetailScreen> {
  final _cancelFeedbackKey = GlobalKey();
  Appointment? _appointment;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isCancelling = false;
  String? _loadError;
  String? _cancelError;

  @override
  void initState() {
    super.initState();
    _loadAppointment();
  }

  Future<void> _loadAppointment() async {
    if (_isRefreshing || _isCancelling) return;
    setState(() {
      _isRefreshing = true;
      _isLoading = _appointment == null;
      _loadError = null;
    });
    try {
      final appointments = await ref
          .read(appointmentsRepositoryProvider)
          .getAppointments()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _appointment = appointments
          .where((item) => item.id == widget.appointmentId)
          .firstOrNull;
    } on TimeoutException {
      _loadError = 'Your appointment is taking longer than expected. Check your connection and try again.';
    } catch (_) {
      _loadError = 'We couldn’t load this appointment. Please try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _cancelAppointment() async {
    if (_isCancelling || _isRefreshing || _appointment == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Cancel this appointment?'),
        content: Text(
          '${_appointment!.title}\n${AppDates.format(_appointment!.appointmentDate, 'EEE, MMM d, y')}\n\nYou can book a new appointment later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep appointment'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Cancel appointment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isCancelling = true;
      _cancelError = null;
    });
    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .cancelAppointment(widget.appointmentId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Appointment cancelled.')));
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/appointments');
      }
    } catch (error) {
      if (!mounted) return;
      final notCancellable = error is AppointmentNotCancellableException;
      setState(
        () => _cancelError = error is AppointmentNotCancellableException
            ? error.message
            : 'We couldn’t cancel this appointment. Please try again.',
      );
      if (notCancellable) {
        // Staff changed the status in the web admin; show the latest one.
        _isCancelling = false;
        unawaited(_loadAppointment());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final feedbackContext = _cancelFeedbackKey.currentContext;
        if (!mounted || feedbackContext == null) return;
        Scrollable.ensureVisible(
          feedbackContext,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        );
      });
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: RefreshIndicator(
              onRefresh: _loadAppointment,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_isLoading)
                    const SliverToBoxAdapter(
                      child: ShimmerLoading(
                        label: 'Loading appointment details…',
                      ),
                    )
                  else if (_appointment == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildUnavailable(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      sliver: SliverToBoxAdapter(child: _buildDetails()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails() {
    final theme = Theme.of(context);
    final appointment = _appointment!;
    final canCancel = appointment.canCancel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRefreshing) ...[
          Semantics(
            liveRegion: true,
            child: const Text('Refreshing appointment…'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_loadError != null) ...[
          _feedback(_loadError!, cached: true),
          const SizedBox(height: AppSpacing.md),
        ],
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  appointment.title,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(status: appointment.displayStatus),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              _detailRow(
                Icons.calendar_today_outlined,
                'Date',
                AppDates.format(
                  appointment.appointmentDate,
                  'EEEE, MMMM d, yyyy',
                ),
              ),
              if (appointment.timeSlot?.trim().isNotEmpty ?? false)
                _detailRow(
                  Icons.schedule_outlined,
                  'Time',
                  appointment.timeSlot!,
                ),
              if (appointment.applianceName?.trim().isNotEmpty ?? false)
                _detailRow(
                  Icons.devices_outlined,
                  'Appliance',
                  appointment.applianceName!,
                ),
              if (appointment.notes?.trim().isNotEmpty ?? false)
                _detailRow(Icons.notes_outlined, 'Notes', appointment.notes!),
            ],
          ),
        ),
        if (_cancelError != null) ...[
          const SizedBox(height: AppSpacing.md),
          KeyedSubtree(
            key: _cancelFeedbackKey,
            child: _feedback(_cancelError!),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Cancel appointment',
            loadingLabel: 'Cancelling appointment…',
            icon: Icons.cancel_outlined,
            isOutlined: true,
            isLoading: _isCancelling,
            onPressed: _isRefreshing ? null : _cancelAppointment,
            width: double.infinity,
          ),
        ],
      ],
    );
  }

  Widget _feedback(String message, {bool cached = false}) {
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.errorContainer,
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cached) ...[
              Text(
                'Showing previously loaded details.',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            if (cached)
              TextButton.icon(
                onPressed: _loadAppointment,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _loadError == null
                  ? Icons.search_off_outlined
                  : Icons.error_outline,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _loadError == null
                  ? 'Appointment not found'
                  : 'Appointment unavailable',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _loadError ?? 'This appointment may have been removed. Refresh to check again.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _loadError == null ? 'Refresh' : 'Try again',
              icon: Icons.refresh_outlined,
              onPressed: _loadAppointment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
