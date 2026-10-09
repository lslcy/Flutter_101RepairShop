import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

class AppButton extends StatelessWidget {
  final String label;
  final String? loadingLabel;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final IconData? icon;
  final Widget? leading;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.loadingLabel,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.leading,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading || icon != null || leading != null) ...[
          SizedBox(
            width: 20,
            height: 20,
            child: isLoading
                ? MediaQuery.disableAnimationsOf(context)
                      ? Icon(
                          Icons.hourglass_empty_outlined,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        )
                      : CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onSurfaceVariant,
                        )
                : leading ?? Icon(icon, size: 20),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            isLoading ? (loadingLabel ?? label) : label,
            style: AppTextStyles.button,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      textStyle: const WidgetStatePropertyAll(AppTextStyles.button),
    );
    final button = isOutlined
        ? OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: style,
            child: child,
          )
        : ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: style,
            child: child,
          );
    return Semantics(
      liveRegion: isLoading,
      label: isLoading ? '$label in progress' : null,
      child: width == null ? button : SizedBox(width: width, child: button),
    );
  }
}
