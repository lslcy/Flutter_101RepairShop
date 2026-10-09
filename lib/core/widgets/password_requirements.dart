import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../validation/password_policy.dart';

/// Live feedback for the same rules used when creating or resetting a password.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({
    super.key,
    required this.password,
    this.showErrors = false,
    this.isEditing = false,
  });

  final String password;
  final bool showErrors;
  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    final isComplete = PasswordPolicy.validate(password) == null;
    if (isComplete || (!isEditing && password.isEmpty && !showErrors)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final successColor = theme.brightness == Brightness.dark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF047857);
    final showMissing = password.isNotEmpty || showErrors;
    final requirements = [
      (
        id: 'length',
        label: 'At least 8 characters',
        isMet: PasswordPolicy.hasMinimumLength(password),
      ),
      (
        id: 'special',
        label: 'At least 1 special character',
        isMet: PasswordPolicy.hasSpecialCharacter(password),
      ),
      (
        id: 'uppercase',
        label: 'At least 1 uppercase letter',
        isMet: PasswordPolicy.hasUppercaseLetter(password),
      ),
      (
        id: 'number',
        label: 'At least 1 number',
        isMet: PasswordPolicy.hasNumber(password),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final requirement in requirements)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              key: ValueKey('password_requirement_${requirement.id}'),
              liveRegion: true,
              excludeSemantics: true,
              label:
                  'Password requirement${requirement.isMet
                      ? ' met'
                      : showMissing
                      ? ' not met'
                      : ''}: ${requirement.label}',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      requirement.isMet
                          ? Icons.check_circle_outline
                          : showMissing
                          ? Icons.cancel_outlined
                          : Icons.info_outline,
                      size: 20,
                      color: requirement.isMet
                          ? successColor
                          : showMissing
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      requirement.label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: requirement.isMet
                            ? successColor
                            : showMissing
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
