import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: dark ? AppColors.darkSurface : AppColors.surface,
    );
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14));

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme:
          TextTheme(
            displaySmall: AppTextStyles.heading1,
            headlineLarge: AppTextStyles.heading1,
            headlineMedium: AppTextStyles.heading1,
            headlineSmall: AppTextStyles.heading2,
            titleLarge: AppTextStyles.heading2,
            titleMedium: AppTextStyles.heading3,
            titleSmall: AppTextStyles.bodyMedium,
            bodyLarge: AppTextStyles.body,
            bodyMedium: AppTextStyles.body,
            bodySmall: AppTextStyles.bodySmall,
            labelLarge: AppTextStyles.button,
            labelMedium: AppTextStyles.label,
            labelSmall: AppTextStyles.caption,
          ).apply(
            fontFamily: 'Roboto',
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: rounded,
          textStyle: AppTextStyles.button,
        ),
      ),
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? AppColors.darkBackground
          : AppColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.darkBackground : AppColors.background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleSpacing: 24,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: rounded,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkSurface : AppColors.surface,
        border: border,
        enabledBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
        helperStyle: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        constraints: const BoxConstraints(minHeight: 56),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 76,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        labelStyle: AppTextStyles.bodyMedium,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
