import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/app_dates.dart';
import '../../../core/utils/load_errors.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../profile/data/customer_repository.dart';
import '../../repairs/data/repairs_repository.dart';
import '../../appointments/data/appointments_repository.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/service_report.dart';
import '../../shared/models/appointment.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Customer? _customer;
  List<ServiceReport> _repairs = [];
  List<Appointment> _appointments = [];
  bool _isLoading = true;
  Object? _profileError;
  Object? _repairsError;
  Object? _appointmentsError;
  bool _profileLoaded = false;
  bool _repairsLoaded = false;
  bool _appointmentsLoaded = false;
  bool _hasLoaded = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final requestId = ++_requestId;
    setState(() => _isLoading = true);
    final customerRepository = ref.read(customerRepositoryProvider);
    final repairsRepository = ref.read(repairsRepositoryProvider);
    final appointmentsRepository = ref.read(appointmentsRepositoryProvider);

    Future<void> loadSection<T>(
      String section,
      Future<T> Function() request,
      void Function(T) apply,
      void Function(Object?) setError,
    ) async {
      try {
        final value = await request().timeout(const Duration(seconds: 20));
        if (!mounted || requestId != _requestId) return;
        apply(value);
        setError(null);
      } catch (error) {
        // Keep the exception type for accurate guidance; avoid logging profile
        // fields or request tokens. One failed section must not hide the others.
        debugPrint(
          'Dashboard $section failed: ${loadFailureDiagnostic(error)}',
        );
        if (!mounted || requestId != _requestId) return;
        setError(error);
      }
    }

    await Future.wait([
      loadSection<Customer?>('profile', customerRepository.getCurrentCustomer, (
        customer,
      ) {
        _customer = customer;
        _profileLoaded = true;
      }, (error) => _profileError = error),
      loadSection<List<ServiceReport>>(
        'repairs',
        repairsRepository.getRepairs,
        (repairs) {
          _repairs = repairs
              .where(
                (report) =>
                    report.datePulledOut == null && !_isFinished(report.status),
              )
              .toList();
          _repairsLoaded = true;
        },
        (error) => _repairsError = error,
      ),
      loadSection<List<Appointment>>(
        'appointments',
        appointmentsRepository.getAppointments,
        (appointments) {
          final today = AppDates.manilaToday();
          _appointments =
              appointments
                  .where(
                    (appointment) =>
                        !appointment.appointmentDate.isBefore(today) &&
                        !_isFinished(appointment.status),
                  )
                  .toList()
                ..sort(
                  (a, b) => a.appointmentDate.compareTo(b.appointmentDate),
                );
          _appointmentsLoaded = true;
        },
        (error) => _appointmentsError = error,
      ),
    ]);
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _hasLoaded = true;
      _isLoading = false;
    });
  }

  bool _isFinished(String? status) => const {
    'completed',
    'cancelled',
    'canceled',
    'released',
    'closed',
  }.contains(status?.trim().toLowerCase());

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (mounted) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(customerProfileRevisionProvider, (_, _) => _loadData());
    final firstName = _customer?.firstName?.trim();
    final addressMissing = _customer?.address?.trim().isEmpty ?? true;
    return Scaffold(
      appBar: AppBar(
        leading: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 32,
                  height: 32,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
        title: const Text('Home', style: AppTextStyles.heading3),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.push('/notifications'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        firstName?.isNotEmpty == true
                            ? '${_getGreeting()}, $firstName'
                            : _getGreeting(),
                        style: AppTextStyles.heading1,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildBookingBanner(),
                    const SizedBox(height: 24),
                    if (_isLoading && !_hasLoaded)
                      const ShimmerListLoading(
                        label: 'Loading your dashboard...',
                        itemCount: 3,
                      )
                    else ...[
                      if (_isLoading) ...[
                        const LinearProgressIndicator(
                          semanticsLabel: 'Refreshing your dashboard',
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_hasLoaded) ...[
                        if (_profileError != null) ...[
                          _buildError('profile', _profileError!),
                          const SizedBox(height: 24),
                        ],
                        if (_profileLoaded && addressMissing) ...[
                          _buildAddressCard(),
                          const SizedBox(height: 24),
                        ],
                        if (_appointmentsError != null) ...[
                          _buildError('appointments', _appointmentsError!),
                          const SizedBox(height: 12),
                        ],
                        if (_appointmentsLoaded) ...[
                          _sectionTitle(
                            'Upcoming appointments',
                            _appointments.length,
                            '/appointments',
                          ),
                          const SizedBox(height: 12),
                          if (_appointments.isEmpty)
                            _emptyState(
                              Icons.event_available_outlined,
                              'No appointments coming up',
                              'Choose a date and time when you need a repair.',
                            )
                          else
                            ..._appointments
                                .take(3)
                                .map(
                                  (appointment) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildAppointmentCard(appointment),
                                  ),
                                ),
                        ],
                        const SizedBox(height: 24),
                        if (_repairsError != null) ...[
                          _buildError('repairs', _repairsError!),
                          const SizedBox(height: 12),
                        ],
                        if (_repairsLoaded) ...[
                          _sectionTitle(
                            'Active repairs',
                            _repairs.length,
                            '/repairs',
                          ),
                          const SizedBox(height: 12),
                          if (_repairs.isEmpty)
                            _emptyState(
                              Icons.build_outlined,
                              'No active repairs',
                              'Your repair progress will appear here.',
                            )
                          else
                            ..._repairs
                                .take(3)
                                .map(
                                  (report) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildRepairCard(report),
                                  ),
                                ),
                        ],
                        if (_profileLoaded && !addressMissing) ...[
                          const SizedBox(height: 24),
                          _buildAddressCard(),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildBookingBanner() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need a repair?',
            style: AppTextStyles.heading2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us what needs fixing and choose a preferred schedule.',
            style: AppTextStyles.body.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openAndRefresh('/book-appointment'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryDark,
            ),
            icon: const Icon(Icons.add_outlined),
            label: const Text('Book a repair'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    final scheme = Theme.of(context).colorScheme;
    final address = _customer?.address?.trim() ?? '';
    return AppCard(
      onTap: () => _openAndRefresh('/profile/edit'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address.isEmpty ? 'Add your address' : 'Your saved address',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  address.isEmpty
                      ? 'An address is required before you can book. Add it manually or use your phone location.'
                      : address,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_outlined, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count, String route) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text('$title ($count)', style: AppTextStyles.heading3),
        TextButton(
          onPressed: () => context.go(route),
          child: const Text('View all'),
        ),
      ],
    );
  }

  Widget _buildRepairCard(ServiceReport report) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => _openAndRefresh('/repairs/${report.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.build_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text('SR-${report.id}', style: AppTextStyles.bodyMedium),
                    const SizedBox(width: 8),
                    StatusBadge(status: RepairStatus.normalize(report.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  report.findings?.trim().isNotEmpty == true
                      ? report.findings!
                      : 'Tap to see repair details.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (report.dateIn != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Received ${AppDates.format(report.dateIn!, 'MMM d, yyyy')}',
                    style: AppTextStyles.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_outlined, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment appointment) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => _openAndRefresh('/appointments/${appointment.id}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.calendar_today_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(appointment.title, style: AppTextStyles.bodyMedium),
                    const SizedBox(width: 8),
                    StatusBadge(status: appointment.displayStatus),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  AppDates.format(appointment.appointmentDate, 'EEEE, MMM d'),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (appointment.timeSlot?.isNotEmpty == true)
                  Text(
                    appointment.timeSlot!,
                    style: AppTextStyles.caption.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_outlined, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String section, Object error) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We could not load your $section',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 8),
          Text(
            friendlyError(error, fallback: 'Please try again in a moment.'),
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
