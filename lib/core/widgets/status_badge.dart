import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

// Colored badge showing repair/appointment/payment status
class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        status,
        style: AppTextStyles.caption.copyWith(
          color: colors.$2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Map status text to (background, foreground) colors. Unknown statuses
  // fall back to a neutral badge instead of failing.
  (Color, Color) _getColors(String status) {
    switch (status.trim().toLowerCase()) {
      case 'completed':
      case 'paid':
      case 'active':
      case 'repaired':
        return (AppColors.successBg, const Color(0xFF065F46));
      case 'in progress':
      case 'ongoing':
      case 'confirmed':
        return (AppColors.infoBg, const Color(0xFF1E40AF));
      case 'waiting for parts':
      case 'partial':
      case 'for repair':
        return (const Color(0xFFFFEDD5), const Color(0xFF9A3412));
      case 'under repair':
        return (const Color(0xFFEDE9FE), const Color(0xFF5B21B6));
      case 'pending':
      case 'unpaid':
        return (AppColors.warningBg, const Color(0xFF92400E));
      case 'cancelled':
      case 'canceled':
      case 'overdue':
      case 'expired':
        return (AppColors.errorBg, const Color(0xFF991B1B));
      // Neutral: inactive appliances, past bookings staff never confirmed,
      // and any status the app does not know yet.
      case 'inactive':
      case 'past — awaiting staff':
      default:
        return (AppColors.surfaceVariant, AppColors.textSecondary);
    }
  }
}
