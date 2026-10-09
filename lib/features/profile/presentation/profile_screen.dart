import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/load_errors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../data/customer_repository.dart';
import '../../shared/models/customer.dart';
import '../../shared/widgets/customer_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/providers/theme_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Customer? _customer;
  bool _isLoading = true;
  bool _isSigningOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (mounted) setState(() => _error = null);
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getCurrentCustomer()
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _isLoading = false;
        _error = customer == null
            ? 'Your profile is unavailable. Please try again.'
            : null;
      });
    } catch (error) {
      debugPrint('Profile load failed: ${loadFailureDiagnostic(error)}');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyError(
          error,
          fallback: 'We could not load your profile. Please try again.',
        );
      });
    }
  }

  Future<void> _editProfile() async {
    await context.push('/profile/edit');
    if (mounted) await _loadProfile();
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return AlertDialog(
          semanticLabel: 'Sign out confirmation',
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 400),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            side: BorderSide(color: colors.outlineVariant),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          title: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    Icons.logout_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Sign out?', style: theme.textTheme.titleLarge),
                ),
              ),
            ],
          ),
          scrollable: true,
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your repairs and appointments will stay saved.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Sign out', textAlign: TextAlign.center),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                autofocus: true,
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text(
                  'Stay signed in',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSigningOut = true);
    try {
      await ref.read(authStateProvider.notifier).signOut();
      if (mounted) context.go('/welcome');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t sign out. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final address = _customer?.address?.trim() ?? '';
    final darkMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Your profile', style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        child: _isLoading
            ? const ShimmerLoading(label: 'Loading your profile...')
            : RefreshIndicator(
                onRefresh: _loadProfile,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null) ...[
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(_error!, style: AppTextStyles.body),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() => _isLoading = true);
                                      _loadProfile();
                                    },
                                    icon: const Icon(Icons.refresh_outlined),
                                    label: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (_customer != null) ...[
                            AppCard(
                              child: Column(
                                children: [
                                  CustomerAvatar(customer: _customer!),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    _customer!.fullName.isNotEmpty
                                        ? _customer!.fullName
                                        : 'Customer',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.heading2,
                                  ),
                                  if (_customer!.email?.trim().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      _customer!.email!,
                                      textAlign: TextAlign.center,
                                      style: AppTextStyles.body.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.md),
                                  OutlinedButton.icon(
                                    onPressed: _editProfile,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Edit personal information',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppCard(
                              onTap: _editProfile,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colors.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.location_on_outlined,
                                          color: colors.onPrimaryContainer,
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Text(
                                          'Saved address',
                                          style: AppTextStyles.heading3,
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_outlined,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    address.isEmpty
                                        ? 'Add your address'
                                        : address,
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    address.isEmpty
                                        ? 'Keep your contact details ready for your next repair.'
                                        : 'Keep this up to date so the team has the right contact details.',
                                    style: AppTextStyles.body.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  TextButton.icon(
                                    onPressed: _editProfile,
                                    icon: Icon(
                                      address.isEmpty
                                          ? Icons.add_outlined
                                          : Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      address.isEmpty
                                          ? 'Add address'
                                          : 'Edit address',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _sectionLabel('Your account'),
                          AppCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                _menuItem(
                                  Icons.devices_outlined,
                                  'My appliances',
                                  'Manage your registered appliances',
                                  () => context.go('/profile/appliances'),
                                ),
                                const Divider(
                                  height: 1,
                                  indent: 56,
                                  endIndent: 16,
                                ),
                                _menuItem(
                                  Icons.receipt_long_outlined,
                                  'Transaction history',
                                  'View your repair payments',
                                  () => context.go('/profile/transactions'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _sectionLabel('Preferences'),
                          AppCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                SwitchListTile(
                                  secondary: Icon(
                                    darkMode
                                        ? Icons.dark_mode_outlined
                                        : Icons.light_mode_outlined,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  title: Text(
                                    'Dark mode',
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                  value: darkMode,
                                  onChanged: (_) => ref
                                      .read(themeModeProvider.notifier)
                                      .toggle(),
                                ),
                                const Divider(
                                  height: 1,
                                  indent: 56,
                                  endIndent: 16,
                                ),
                                _menuItem(
                                  Icons.info_outline,
                                  'About 101 RepairShop',
                                  null,
                                  () => context.push('/about'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          TextButton.icon(
                            onPressed: _isSigningOut ? null : _handleSignOut,
                            style: TextButton.styleFrom(
                              foregroundColor: colors.error,
                              minimumSize: const Size(0, 48),
                            ),
                            icon: const Icon(Icons.logout_outlined),
                            label: Text(
                              _isSigningOut ? 'Signing out…' : 'Sign out',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(label, style: AppTextStyles.heading3),
  );

  Widget _menuItem(
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Icon(icon, color: colors.onSurfaceVariant),
      title: Text(title, style: AppTextStyles.bodyMedium),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        Icons.chevron_right_outlined,
        color: colors.onSurfaceVariant,
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
    );
  }
}
