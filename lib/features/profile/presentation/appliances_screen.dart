import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/app_dates.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/appliance.dart';
import '../data/customer_repository.dart';

class AppliancesScreen extends ConsumerStatefulWidget {
  const AppliancesScreen({super.key});

  @override
  ConsumerState<AppliancesScreen> createState() => _AppliancesScreenState();
}

class _AppliancesScreenState extends ConsumerState<AppliancesScreen> {
  List<Appliance> _appliances = [];
  bool _isLoading = true;
  bool _requestInFlight = false;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  bool _openingForm = false;

  @override
  void initState() {
    super.initState();
    _loadAppliances();
  }

  Future<void> _loadAppliances() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final data = await ref
          .read(customerRepositoryProvider)
          .getAppliances()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _appliances = data;
        _hasLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      _requestInFlight = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addAppliance() async {
    if (_openingForm) return;
    setState(() => _openingForm = true);
    await context.push('/profile/appliances/add');
    if (!mounted) return;
    setState(() => _openingForm = false);
    await _loadAppliances();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initialLoading = _isLoading && !_hasLoaded;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My appliances', style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: _loadAppliances,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Keep appliance details and warranties in one place.',
                            style: AppTextStyles.body.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (_hasLoaded && _appliances.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              '${_appliances.length} appliance${_appliances.length == 1 ? '' : 's'}',
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                          if (_isLoading && _hasLoaded) ...[
                            const SizedBox(height: AppSpacing.md),
                            const LinearProgressIndicator(
                              semanticsLabel: 'Refreshing appliances',
                            ),
                          ],
                          if (_loadFailed && _appliances.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            AppCard(
                              color: scheme.errorContainer,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Could not refresh appliances. Showing your last loaded list.',
                                    style: AppTextStyles.body.copyWith(
                                      color: scheme.onErrorContainer,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _loadAppliances,
                                    icon: const Icon(Icons.refresh_outlined),
                                    label: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (initialLoading)
                    const SliverToBoxAdapter(
                      child: ShimmerListLoading(
                        itemCount: 4,
                        label: 'Loading your appliances...',
                      ),
                    )
                  else if (_loadFailed && _appliances.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Appliances unavailable',
                        message: 'We could not load your appliances. Check your connection and try again.',
                        action: TextButton.icon(
                          onPressed: _loadAppliances,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Try again'),
                        ),
                      ),
                    )
                  else if (_appliances.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: Icons.devices_outlined,
                        title: 'No appliances yet',
                        message: 'Add your first appliance to keep its details ready for your next repair.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      sliver: SliverList.separated(
                        itemCount: _appliances.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _buildApplianceCard(_appliances[index]),
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
              child: AppButton(
                label: 'Add appliance',
                icon: Icons.add_outlined,
                onPressed: _openingForm ? null : _addAppliance,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _displayName(Appliance appliance) {
    final parts = [appliance.brand, appliance.product]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Appliance' : parts.join(' ');
  }

  Widget _buildApplianceCard(Appliance appliance) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => _showApplianceDetail(appliance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.devices_outlined, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _displayName(appliance),
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
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(status: ApplianceStatus.normalize(appliance.status)),
              if (appliance.category?.trim().isNotEmpty ?? false)
                Text(
                  appliance.category!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (appliance.modelNo?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Model: ${appliance.modelNo}',
              style: AppTextStyles.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showApplianceDetail(Appliance appliance) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _displayName(appliance),
                        style: AppTextStyles.heading3,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close appliance details',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                StatusBadge(status: ApplianceStatus.normalize(appliance.status)),
                const SizedBox(height: AppSpacing.lg),
                if (appliance.category?.trim().isNotEmpty ?? false)
                  _infoRow(
                    Icons.category_outlined,
                    'Category',
                    appliance.category!,
                  ),
                if (appliance.modelNo?.trim().isNotEmpty ?? false)
                  _infoRow(
                    Icons.tag_outlined,
                    'Model number',
                    appliance.modelNo!,
                  ),
                if (appliance.serialNo?.trim().isNotEmpty ?? false)
                  _infoRow(
                    Icons.qr_code_outlined,
                    'Serial number',
                    appliance.serialNo!,
                  ),
                if (appliance.applianceSize?.trim().isNotEmpty ?? false)
                  _infoRow(
                    Icons.straighten_outlined,
                    'Size',
                    appliance.applianceSize!,
                  ),
                if (appliance.dateIn != null)
                  _infoRow(
                    Icons.calendar_today_outlined,
                    'Date added',
                    AppDates.format(appliance.dateIn!, 'MMM d, yyyy'),
                  ),
                if (appliance.warrantyEnd != null)
                  _infoRow(
                    Icons.verified_outlined,
                    'Warranty',
                    appliance.isUnderWarranty
                        ? 'Until ${AppDates.format(appliance.warrantyEnd!, 'MMM d, yyyy')}'
                        : 'Expired ${AppDates.format(appliance.warrantyEnd!, 'MMM d, yyyy')}',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: AppTextStyles.bodyMedium),
              ],
            ),
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
