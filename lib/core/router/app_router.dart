import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_flow_controller.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/phone_sign_in_screen.dart';

import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/repairs/presentation/repairs_screen.dart';
import '../../features/repairs/presentation/repair_detail_screen.dart';
import '../../features/appointments/presentation/appointments_screen.dart';
import '../../features/appointments/presentation/book_appointment_screen.dart';
import '../../features/appointments/presentation/appointment_detail_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/appliances_screen.dart';
import '../../features/profile/presentation/add_appliance_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/transaction_history_screen.dart';
import '../../features/profile/presentation/about_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';

// Navigator keys for shell route and sub-routes
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _shellNavigatorRepairsKey = GlobalKey<NavigatorState>(
  debugLabel: 'repairs',
);
final _shellNavigatorAppointmentsKey = GlobalKey<NavigatorState>(
  debugLabel: 'appointments',
);
final _shellNavigatorAppliancesKey = GlobalKey<NavigatorState>(
  debugLabel: 'appliances',
);
final _shellNavigatorPaymentsKey = GlobalKey<NavigatorState>(
  debugLabel: 'payments',
);
final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(
  debugLabel: 'profile',
);

// GoRouter provider
final routerProvider = Provider<GoRouter>((ref) {
  final authFlow = ref.read(authFlowProvider);
  final router = GoRouter(
    refreshListenable: authFlow,
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authFlow.isLoggedIn;
      final location = state.matchedLocation;
      if (authFlow.requiresRecovery) {
        return location == '/reset-password' ? null : '/reset-password';
      }
      if (location == '/reset-password' || location == '/forgot-password') {
        return null;
      }
      if (authFlow.isRegistering && location == '/register') return null;
      if (authFlow.requiresSignInProfile) {
        return location == '/complete-profile' ? null : '/complete-profile';
      }
      if (location == '/complete-profile' && isLoggedIn) return '/';
      if (!isLoggedIn &&
          authFlow.googleSignInError != null &&
          (location == '/welcome' || location == '/login-callback')) {
        return '/login';
      }
      final isAuthRoute =
          location == '/welcome' ||
          location == '/login' ||
          location == '/register' ||
          location == '/forgot-password' ||
          location == '/phone-sign-in' ||
          location == '/login-callback';

      // Not logged in and not on auth page -> go to welcome
      if (!isLoggedIn && !isAuthRoute) return '/welcome';

      // Logged in and on auth page -> go to home
      if (isLoggedIn && isAuthRoute) return '/';

      return null;
    },
    routes: [
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/phone-sign-in',
        builder: (_, _) => const PhoneSignInScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/login-callback',
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/complete-profile',
        builder: (_, _) => const CompleteProfileScreen(),
      ),
      // Auth routes (full screen on root navigator)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/login',
        builder: (_, state) => LoginScreen(
          initialEmail: state.extra is String ? state.extra! as String : '',
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/register',
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/forgot-password',
        builder: (_, state) => ForgotPasswordScreen(
          initialEmail: state.extra is String ? state.extra! as String : '',
        ),
      ),

      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),

      // Feature sub-routes (full screen on root navigator, hides bottom nav)
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/repairs/:id',
        builder: (_, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return RepairDetailScreen(reportId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/appointments/:id',
        builder: (_, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return AppointmentDetailScreen(appointmentId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/book-appointment',
        builder: (_, _) => const BookAppointmentScreen(),
      ),

      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/profile/appliances/add',
        builder: (_, _) => const AddApplianceScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/profile/edit',
        builder: (_, _) => const EditProfileScreen(),
      ),

      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/about',
        builder: (_, _) => const AboutScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),

      // Main app tabs with bottom navigation
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, _, navigationShell) {
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
                ? null
                : AppBottomNavigationBar(
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: (i) => navigationShell.goBranch(
                      i,
                      initialLocation: i == navigationShell.currentIndex,
                    ),
                  ),
          );
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorHomeKey,
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorRepairsKey,
            routes: [
              GoRoute(
                path: '/repairs',
                builder: (_, _) => const RepairsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorAppointmentsKey,
            routes: [
              GoRoute(
                path: '/appointments',
                builder: (_, _) => const AppointmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorAppliancesKey,
            routes: [
              GoRoute(
                path: '/profile/appliances',
                builder: (_, _) => const AppliancesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorPaymentsKey,
            routes: [
              GoRoute(
                path: '/profile/transactions',
                builder: (_, _) => const TransactionHistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Keeps six destinations reachable without shrinking labels or tap targets.
/// On compact screens the selected label spans the bar; every icon retains its
/// native tooltip and screen-reader label. Roomier layouts show all labels.
class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.build_outlined), label: 'Repairs'),
    NavigationDestination(
      icon: Icon(Icons.calendar_today_outlined),
      label: 'Appointments',
    ),
    NavigationDestination(
      icon: Icon(Icons.devices_outlined),
      label: 'Appliances',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      label: 'Payments',
    ),
    NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final labelStyle =
          theme.navigationBarTheme.labelTextStyle?.resolve({
            WidgetState.selected,
          }) ??
          theme.textTheme.labelMedium!;
      final textScaler = MediaQuery.textScalerOf(context);
      var destinationWidth = 48.0;
      for (final destination in destinations) {
        final painter = TextPainter(
          text: TextSpan(text: destination.label, style: labelStyle),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout();
        final paddedWidth = painter.width + 24;
        if (paddedWidth > destinationWidth) destinationWidth = paddedWidth;
        painter.dispose();
      }
      final compact =
          constraints.maxWidth < destinationWidth * destinations.length;
      final navigationBar = NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        height: compact ? 64 : 80 + (textScaler.scale(12) - 12),
        labelBehavior: compact
            ? NavigationDestinationLabelBehavior.alwaysHide
            : NavigationDestinationLabelBehavior.alwaysShow,
        destinations: destinations,
      );
      final minimumWidth = destinations.length * 48.0;
      return Material(
        color: theme.colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ExcludeSemantics(
                  child: Text(
                    destinations[selectedIndex].label,
                    key: const ValueKey('selected-navigation-label'),
                    style: theme.textTheme.labelLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (constraints.maxWidth < minimumWidth)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: minimumWidth, child: navigationBar),
              )
            else
              navigationBar,
          ],
        ),
      );
    },
  );
}
