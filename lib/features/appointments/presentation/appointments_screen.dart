import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/appointment.dart';
import '../data/appointments_repository.dart';

class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  List<Appointment> _appointments = [];
  bool _isLoading = true;
  bool _requestInFlight = false;
  bool _loadFailed = false;
  bool _hasLoaded = false;
  bool _openingBooking = false;

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final data = await ref
          .read(appointmentsRepositoryProvider)
          .getAppointments()
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _appointments = data;
          _hasLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      _requestInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _bookAppointment() async {
    setState(() => _openingBooking = true);
    await context.push('/book-appointment');
    if (!mounted) return;
    setState(() => _openingBooking = false);
    await _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    final initialLoading = _isLoading && !_hasLoaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments', style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: _loadAppointments,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_appointments.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!initialLoading &&
                                !_loadFailed &&
                                _appointments.isNotEmpty) ...[
                              Text(
                                '${_appointments.length} appointment${_appointments.length == 1 ? '' : 's'}',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ],
                            if (_isLoading && _hasLoaded) ...[
                              const SizedBox(height: AppSpacing.md),
                              const LinearProgressIndicator(
                                semanticsLabel: 'Refreshing appointments',
                              ),
                            ],
                            if (_loadFailed && _appointments.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildRefreshError(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (initialLoading)
                    const SliverToBoxAdapter(
                      child: ShimmerListLoading(
                        itemCount: 4,
                        label: 'Loading your appointments...',
                      ),
                    )
                  else if (_loadFailed && _appointments.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Appointments unavailable',
                        message: 'We could not load your appointments. Check your connection and try again.',
                        action: TextButton.icon(
                          onPressed: _loadAppointments,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Try again'),
                        ),
                      ),
                    )
                  else if (_appointments.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: Icons.calendar_today_outlined,
                        title: 'No appointments yet',
                        message: 'Book an appointment to choose a preferred date and time for your repair.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      sliver: SliverList.separated(
                        itemCount: _appointments.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _buildAppointmentCard(_appointments[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 852),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openingBooking ? null : _bookAppointment,
                  icon: const Icon(Icons.add_outlined),
                  label: const Text(
                    'Book appointment',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment appointment) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () async {
        await context.push('/appointments/${appointment.id}');
        if (mounted) await _loadAppointments();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  appointment.title,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  DateFormat('EEE, MMM d, yyyy')
                      .format(appointment.appointmentDate),
                  style: AppTextStyles.body.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (appointment.timeSlot?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    appointment.timeSlot!,
                    style: AppTextStyles.body.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          StatusBadge(status: appointment.status ?? 'Pending'),
        ],
      ),
    );
  }

  Widget _buildRefreshError() {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not refresh appointments. Showing your last loaded list.',
            style: AppTextStyles.body.copyWith(color: scheme.onErrorContainer),
          ),
          TextButton.icon(
            onPressed: _loadAppointments,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTextStyles.body.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
