import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
  bool _hasError = false;
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
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final results = await Future.wait([
        ref.read(customerRepositoryProvider).getCurrentCustomer(),
        ref.read(repairsRepositoryProvider).getRepairs(),
        ref.read(appointmentsRepositoryProvider).getAppointments(),
      ]).timeout(const Duration(seconds: 20));
      if (!mounted || requestId != _requestId) return;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      const finished = {
        'completed',
        'cancelled',
        'canceled',
        'released',
        'closed',
      };
      final appointments =
          (results[2] as List<Appointment>)
              .where(
                (a) =>
                    !a.appointmentDate.isBefore(today) &&
                    !finished.contains(a.status?.trim().toLowerCase()),
              )
              .toList()
            ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
      setState(() {
        _hasLoaded = true;
        _customer = results[0] as Customer?;
        _repairs = (results[1] as List<ServiceReport>)
            .where(
              (r) =>
                  r.datePulledOut == null &&
                  !finished.contains(r.status?.trim().toLowerCase()),
            )
            .toList();
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

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
        title: Row(
          children: [
            ClipRRect(
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
            const SizedBox(width: 10),
            const Flexible(
              child: Text('101 RepairShop', style: AppTextStyles.heading3),
            ),
          ],
        ),
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
                      if (_hasError) ...[
                        _buildError(),
                        const SizedBox(height: 24),
                      ],
                      if (_hasLoaded) ...[
                        if (addressMissing) ...[
                          _buildAddressCard(),
                          const SizedBox(height: 24),
                        ],
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
                                (a) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildAppointmentCard(a),
                                ),
                              ),
                        const SizedBox(height: 24),
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
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildRepairCard(r),
                                ),
                              ),
                        if (!addressMissing) ...[
                          const SizedBox(height: 24),
                          _buildAddressCard(),
                        ],
                      ],
                    ],
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        'Your account',
                        style: AppTextStyles.heading3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
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

  Widget _buildQuickActions() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        AppCard(
          onTap: () => context.push('/profile/appliances'),
          child: Row(
            children: [
              Icon(Icons.devices_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'My appliances',
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your registered devices',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          onTap: () => context.push('/profile/transactions'),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment history',
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Review your repair payments',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
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
                    StatusBadge(status: report.status ?? 'Pending'),
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
                    'Received ${DateFormat('MMM d, yyyy').format(report.dateIn!)}',
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
                    StatusBadge(status: appointment.status ?? 'Pending'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, MMM d').format(appointment.appointmentDate),
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

  Widget _buildError() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We could not load your dashboard',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 8),
          const Text(
            'Check your connection and try again.',
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
