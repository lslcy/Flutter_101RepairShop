import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/notification_service.dart';

// Root app widget with dynamic theme
class RepairShopApp extends ConsumerWidget {
  const RepairShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      NotificationService.instance.setAppointmentOpenHandler((id) {
        if (context.mounted) router.push('/appointments/$id');
      });
    });

    return MaterialApp.router(
      title: '101 RepairShop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}
