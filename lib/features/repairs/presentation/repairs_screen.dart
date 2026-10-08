import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/statuses.dart';
import '../../../core/utils/app_dates.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../core/widgets/status_badge.dart';
import '../../shared/models/service_report.dart';
import '../data/repairs_repository.dart';

class RepairsScreen extends ConsumerStatefulWidget {
  const RepairsScreen({super.key});

  @override
  ConsumerState<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends ConsumerState<RepairsScreen> {
  static const _statusFilters = [
    'All',
    RepairStatus.pending,
    RepairStatus.inProgress,
    RepairStatus.completed,
    RepairStatus.cancelled,
  ];
  final _searchController = TextEditingController();
  List<ServiceReport> _allRepairs = [];
  bool _isLoading = true;
  bool _requestInFlight = false;
  bool _loadFailed = false;
  bool _hasLoaded = false;
  String _selectedFilter = 'All';

  List<ServiceReport> get _filteredRepairs {
    final query = _searchController.text.trim().toLowerCase();
    return _allRepairs.where((report) {
      if (_selectedFilter != 'All') {
        final matches = _selectedFilter == RepairStatus.inProgress
            ? RepairStatus.isInProgress(report.status)
            : RepairStatus.normalize(report.status) == _selectedFilter;
        if (!matches) return false;
      }
      return query.isEmpty ||
          'sr-${report.id}'.contains(query) ||
          (report.findings ?? '').toLowerCase().contains(query) ||
          (report.remarks ?? '').toLowerCase().contains(query);
    }).toList();
  }

  bool get _hasFilters =>
      _selectedFilter != 'All' || _searchController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadRepairs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  void _resetFilters() {
    _searchController.clear();
    setState(() => _selectedFilter = 'All');
  }

  Future<void> _loadRepairs() async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final repairs = await ref
          .read(repairsRepositoryProvider)
          .getRepairs()
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _allRepairs = repairs;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repairs = _filteredRepairs;
    final initialLoading = _isLoading && !_hasLoaded;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My repairs', style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: _loadRepairs,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              labelText: 'Search repairs',
                              hintText: 'Repair ID or issue',
                              prefixIcon: const Icon(Icons.search_outlined),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      constraints: const BoxConstraints(
                                        minWidth: 48,
                                        minHeight: 48,
                                      ),
                                      icon: const Icon(Icons.clear_outlined),
                                      onPressed: _searchController.clear,
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Repair status',
                            style: AppTextStyles.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          SingleChildScrollView(
                            key: const ValueKey('repair-status-filters'),
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: _statusFilters.map((filter) {
                                final selected = _selectedFilter == filter;
                                return Padding(
                                  padding: EdgeInsets.only(
                                    right: filter == _statusFilters.last
                                        ? 0
                                        : AppSpacing.sm,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(filter),
                                    selected: selected,
                                    selectedColor: scheme.primary,
                                    backgroundColor: scheme.surface,
                                    labelStyle: AppTextStyles.bodyMedium
                                        .copyWith(
                                          color: selected
                                              ? scheme.onPrimary
                                              : scheme.onSurface,
                                        ),
                                    checkmarkColor: scheme.onPrimary,
                                    side: BorderSide(
                                      color: selected
                                          ? scheme.primary
                                          : scheme.outline,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.padded,
                                    visualDensity: VisualDensity.standard,
                                    onSelected: (_) => setState(
                                      () => _selectedFilter = filter,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          if (!initialLoading && !_loadFailed) ...[
                            const SizedBox(height: AppSpacing.md),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                '${repairs.length} ${_hasFilters ? 'matching ' : ''}repair${repairs.length == 1 ? '' : 's'}',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ),
                          ],
                          if (_isLoading && _hasLoaded) ...[
                            const SizedBox(height: AppSpacing.md),
                            const LinearProgressIndicator(
                              semanticsLabel: 'Refreshing repairs',
                            ),
                          ],
                          if (_loadFailed && _allRepairs.isNotEmpty) ...[
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
                        label: 'Loading your repairs...',
                      ),
                    )
                  else if (_loadFailed && _allRepairs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Repairs unavailable',
                        message: 'We could not load your repairs. Check your connection and try again.',
                        action: TextButton.icon(
                          onPressed: _loadRepairs,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Try again'),
                        ),
                      ),
                    )
                  else if (repairs.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildState(
                        icon: _hasFilters
                            ? Icons.search_off_outlined
                            : Icons.build_outlined,
                        title: _hasFilters
                            ? 'No matching repairs'
                            : 'No repairs yet',
                        message: _hasFilters
                            ? 'Try a different search or clear your filters.'
                            : 'Your repair updates will appear here once a service report is created.',
                        action: _hasFilters
                            ? TextButton(
                                onPressed: _resetFilters,
                                child: const Text('Clear filters'),
                              )
                            : null,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      sliver: SliverList.separated(
                        itemCount: repairs.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, index) =>
                            _buildRepairCard(repairs[index]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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
            'Could not refresh repairs. Showing your last loaded list.',
            style: AppTextStyles.body.copyWith(color: scheme.onErrorContainer),
          ),
          TextButton.icon(
            onPressed: _loadRepairs,
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

  Widget _buildRepairCard(ServiceReport report) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () async {
        await context.push('/repairs/${report.id}');
        if (mounted) await _loadRepairs();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build_outlined, color: scheme.primary, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('SR-${report.id}', style: AppTextStyles.bodyMedium),
              ),
              Icon(
                Icons.chevron_right_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (report.findings?.trim().isNotEmpty ?? false) ...[
            Text(
              report.findings!,
              style: AppTextStyles.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(status: RepairStatus.normalize(report.status)),
              Text(
                report.dateIn == null
                    ? 'Date not recorded'
                    : 'Received ${AppDates.format(report.dateIn!, 'MMM d, yyyy')}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
