import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Proximity: groups related content visually.
/// Fitts's Law: entire card is a tap target with comfortable padding.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    return Material(
      color: color ?? scheme.surface,
      borderRadius: radius,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: scheme.primary.withValues(alpha: 0.08),
        highlightColor: scheme.primary.withValues(alpha: 0.04),
        child: Container(
          // Fitts's: minimum 48dp effective touch area via padding
          constraints: onTap == null
              ? null
              : const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: padding ?? const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
