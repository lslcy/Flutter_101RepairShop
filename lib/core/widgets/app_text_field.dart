import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';
import '../theme/app_spacing.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final TextStyle? labelStyle;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final int? maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? helperText;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onFieldSubmitted;

  const AppTextField({
    super.key,
    required this.label,
    this.labelStyle,
    this.focusNode,
    this.onTap,
    this.hint,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.prefixIcon,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
    this.helperText,
    this.autofillHints,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle ?? AppTextStyles.label),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: label,
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            onTap: onTap,
            validator: validator,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLines: maxLines,
            enabled: enabled,
            onChanged: onChanged,
            autofillHints: autofillHints,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            onFieldSubmitted: onFieldSubmitted,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: hint,
              helperText: helperText,
              helperMaxLines: 3,
              errorMaxLines: 3,
              suffixIcon: suffixIcon,
              prefixIcon: prefixIcon,
            ),
          ),
        ),
      ],
    );
  }
}
