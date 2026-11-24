import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/admin/presentation/admin_shell.dart';
import '../../features/billing/presentation/billing_screen.dart';
import '../../features/orders/presentation/order_history_screen.dart';
import '../../features/themes/presentation/appearance_settings_page.dart';
import '../../features/themes/presentation/theme_editor_page.dart';
import '../../features/themes/presentation/themes_list_page.dart';
import '../../features/kiosk/presentation/kiosk_display_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login';

      if (!auth.isLoggedIn) return loggingIn ? null : '/login';

      if (loggingIn) {
        if (auth.role == 'KIOSK') return '/kiosk';
        return auth.isAdmin ? '/admin' : '/billing';
      }

      // Kiosk users stay on /kiosk
      if (auth.role == 'KIOSK' && !loc.startsWith('/kiosk')) return '/kiosk';

      // Cashiers cannot access admin routes
      if (loc.startsWith('/admin') && !auth.isAdmin) return '/billing';

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/kiosk', builder: (_, __) => const KioskDisplayScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminShell()),
      GoRoute(path: '/admin/appearance', builder: (_, __) => const AppearanceSettingsPage()),
      GoRoute(path: '/admin/appearance/themes', builder: (_, __) => const ThemesListPage()),
      GoRoute(
        path: '/admin/appearance/themes/:id',
        builder: (_, state) => ThemeEditorPage(themeId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/billing', builder: (_, __) => const _CashierShell()),
    ],
  );
});

/// Simple cashier shell: billing + order history tabs.
class _CashierShell extends ConsumerStatefulWidget {
  const _CashierShell();
  @override
  ConsumerState<_CashierShell> createState() => _CashierShellState();
}

class _CashierShellState extends ConsumerState<_CashierShell> {
  int _index = 0;

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [BillingScreen(), OrderHistoryScreen()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Billing'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Billing'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Orders'),
        ],
      ),
    );
  }
}
