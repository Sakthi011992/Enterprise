import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/outlet_picker_screen.dart';
import '../../features/auth/presentation/pin_login_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/billing/presentation/billing_screen.dart';
import '../../features/branding/presentation/branding_screen.dart';
import '../../features/dev/component_gallery_screen.dart';
import '../../features/devices/presentation/devices_screen.dart';
import '../../features/kiosk/presentation/kiosk_admin_screen.dart';
import '../../features/kiosk/presentation/kiosk_display_screen.dart';
import '../../features/localisation/presentation/localisation_screen.dart';
import '../../features/orders/presentation/order_history_screen.dart';
import '../../features/outlets/presentation/outlets_screen.dart';
import '../../features/personas/presentation/personas_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/reports/presentation/dashboard_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tax/presentation/tax_settings_screen.dart';
import '../../features/themes/presentation/appearance_settings_page.dart';
import '../../features/themes/presentation/theme_editor_page.dart';
import '../../features/themes/presentation/themes_list_page.dart';
import '../../features/users/presentation/users_screen.dart';
import '../auth/permissions.dart';
import '../auth/session_controller.dart';
import '../shell/app_shell.dart';
import '../shell/nav_registry.dart';
import '../shell/placeholder_screen.dart';

/// Reachable without a session.
const _publicPaths = {'/login', '/forgot-password', '/reset-password', '/pin'};

/// Only useful when signed out; a signed-in user is sent to their home.
const _signedOutOnlyPaths = {'/login', '/select-outlet', '/pin'};

/// Old paths kept so bookmarks and links from before the shell still work.
const _legacyRedirects = {
  '/admin': '/dashboard',
  '/admin/appearance': '/settings/appearance',
  '/admin/appearance/themes': '/settings/appearance/themes',
  '/billing': '/pos',
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<SessionState>(sessionProvider, (_, __) => refresh.value++);

  String? redirect(BuildContext context, GoRouterState state) {
    final path = state.matchedLocation;

    final legacy = _legacyRedirects[path];
    if (legacy != null) return legacy;
    if (path.startsWith('/admin/appearance/themes/')) {
      return '/settings/appearance/themes/${path.substring('/admin/appearance/themes/'.length)}';
    }

    final auth = ref.read(sessionProvider);
    final session = auth.session;

    if (session == null) {
      if (auth.pendingOutletChoice != null) {
        return path == '/select-outlet' ? null : '/select-outlet';
      }
      if (path == '/select-outlet') return '/login';
      return _publicPaths.contains(path) ? null : '/login';
    }

    final home = session.persona.homeRoute;
    if (_signedOutOnlyPaths.contains(path) || _isForbidden(path)) {
      // Avoid a redirect loop when the home route is itself not permitted.
      return path == home ? null : home;
    }
    return null;
  }

  bool _isForbidden(String path) {
    final session = ref.read(sessionProvider).session;
    final item = navItemForPath(path);
    return item != null && !canOf(session, item.permission, item.min);
  }

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => ResetPasswordScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(path: '/select-outlet', builder: (_, __) => const OutletPickerScreen()),
      GoRoute(path: '/pin', builder: (_, __) => const PinLoginScreen()),
      // Kiosk display: full screen, outside the shell.
      GoRoute(path: '/kiosk', builder: (_, __) => const KioskDisplayScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/pos', builder: (_, __) => const BillingScreen()),
          GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
          GoRoute(path: '/menu', builder: (_, __) => const ProductsScreen()),
          GoRoute(
            path: '/stock-count',
            builder: (_, __) => const PlaceholderScreen(title: 'Stock count'),
          ),
          GoRoute(
            path: '/my-shifts',
            builder: (_, __) => const PlaceholderScreen(title: 'My shifts'),
          ),
          GoRoute(path: '/users', builder: (_, __) => const UsersScreen()),
          GoRoute(path: '/settings/general', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/settings/personas', builder: (_, __) => const PersonasScreen()),
          GoRoute(path: '/settings/outlets', builder: (_, __) => const OutletsScreen()),
          GoRoute(path: '/settings/devices', builder: (_, __) => const DevicesScreen()),
          GoRoute(path: '/settings/tax', builder: (_, __) => const TaxSettingsScreen()),
          GoRoute(path: '/settings/branding', builder: (_, __) => const BrandingScreen()),
          GoRoute(
            path: '/settings/localisation',
            builder: (_, __) => const LocalisationScreen(),
          ),
          GoRoute(path: '/settings/kiosk', builder: (_, __) => const KioskAdminScreen()),
          GoRoute(
            path: '/settings/appearance',
            builder: (_, __) => const AppearanceSettingsPage(),
          ),
          GoRoute(
            path: '/settings/appearance/themes',
            builder: (_, __) => const ThemesListPage(),
          ),
          GoRoute(
            path: '/settings/appearance/themes/:id',
            builder: (_, state) => ThemeEditorPage(themeId: state.pathParameters['id']!),
          ),
          if (kDebugMode)
            GoRoute(path: '/dev/components', builder: (_, __) => const ComponentGalleryScreen()),
        ],
      ),
    ],
  );
});
