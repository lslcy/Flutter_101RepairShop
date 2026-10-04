import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';

// About screen — simple and informative
// Miller's Law: chunked into 3 groups (logo, info, version)
// Proximity: related items grouped in cards
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('About', style: AppTextStyles.heading2)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),

            // Logo
            Image.asset('assets/images/logo.png', width: 140, height: 140),
            const SizedBox(height: AppSpacing.md),
            Text(
              '101 Repair Service',
              style: AppTextStyles.heading2.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Because Every Appliance Matters.',
              style: AppTextStyles.bodySmall.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // About info card — Proximity: grouped related info
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About Us', style: AppTextStyles.heading3),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '101 Repair Service is your trusted partner for appliance repair and maintenance. '
                    'We provide professional repair services for all types of home appliances with '
                    'quality workmanship and genuine parts.',
                    style: AppTextStyles.body.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Contact info — Proximity
            AppCard(
              child: Column(
                children: [
                  _infoRow(
                    context,
                    Icons.phone_outlined,
                    'Contact',
                    '+63 912 345 6789',
                  ),
                  const Divider(height: AppSpacing.lg),
                  _infoRow(
                    context,
                    Icons.email_outlined,
                    'Email',
                    'service@101repairshop.com',
                  ),
                  const Divider(height: AppSpacing.lg),
                  _infoRow(
                    context,
                    Icons.location_on_outlined,
                    'Address',
                    'Quezon City, Philippines',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Version info
            Text(
              'Version 1.0.0',
              style: AppTextStyles.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
