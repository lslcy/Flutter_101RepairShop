import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../models/customer.dart';

/// Profile picture with an initials/person placeholder. The placeholder is
/// also shown when the image URL fails to load.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({super.key, required this.customer, this.radius = 36});

  final Customer customer;
  final double radius;

  String get _initials {
    final first = customer.firstName?.trim() ?? '';
    final last = customer.lastName?.trim() ?? '';
    return '${first.isNotEmpty ? first.characters.first : ''}'
            '${last.isNotEmpty ? last.characters.first : ''}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = customer.profilePictureUrl;
    final initials = _initials;
    return Semantics(
      label: 'Profile picture',
      image: true,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: colors.primaryContainer,
        foregroundImage: url == null ? null : NetworkImage(url),
        // Keep the placeholder visible if the image cannot be loaded.
        onForegroundImageError: url == null ? null : (_, _) {},
        child: initials.isEmpty
            ? Icon(
                Icons.person_outline,
                size: radius,
                color: colors.onPrimaryContainer,
              )
            : Text(
                initials,
                style: AppTextStyles.heading1.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
      ),
    );
  }
}
