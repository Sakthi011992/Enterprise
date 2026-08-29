import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/features/app_feature.dart';
import '../../../core/features/feature_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../reports/presentation/dashboard_screen.dart';
import '../../products/presentation/products_screen.dart';
import '../../tax/presentation/tax_settings_screen.dart';
import '../../users/presentation/users_screen.dart';
import '../../orders/presentation/order_history_screen.dart';
import '../../themes/presentation/appearance_settings_page.dart';

typedef _Dest = ({IconData icon, String label, AppFeature feature, Widget page});

const _allDests = <_Dest>[
  (icon: Icons.dashboard,   label: 'Dashboard',  feature: AppFeature.dashboard,   page: DashboardScreen()),
  (icon: Icons.inventory_2, label: 'Products',   feature: AppFeature.products,    page: ProductsScreen()),
  (icon: Icons.percent,     label: 'Tax',        feature: AppFeature.tax,         page: TaxSettingsScreen()),
  (icon: Icons.people,      label: 'Users',      feature: AppFeature.users,       page: UsersScreen()),
  (icon: Icons.receipt_long,label: 'Orders',     feature: AppFeature.orders,      page: OrderHistoryScreen()),
  (icon: Icons.palette,     label: 'Appearance', feature: AppFeature.appearance,  page: AppearanceSettingsPage()),
];

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});
  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final granted = ref.watch(userFeaturesProvider);
    final dests = _allDests.where((d) => granted.contains(d.feature)).toList();

    // Keep index in bounds if feature set changes.
    final safeIndex = _index.clamp(0, dests.isEmpty ? 0 : dests.length - 1);
    if (safeIndex != _index) WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _index = safeIndex));

    if (dests.isEmpty) {
      return Scaffold(
        body: Center(child: Text('No features enabled for your account.\nContact an admin.', textAlign: TextAlign.center)),
      );
    }

    final wide = MediaQuery.of(context).size.width > 760;
    final t = context.tokens;

    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 1100,
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Column(children: [
              SizedBox(height: t.spacing.step(3)),
              Icon(Icons.point_of_sale, size: 32, color: t.color.background.accent),
              SizedBox(height: t.spacing.step(3)),
              IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Logout'),
            ]),
            destinations: dests
                .map((d) => NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: dests[safeIndex].page),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(dests[safeIndex].label),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: _logout),
        ],
      ),
      body: dests[safeIndex].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: dests
            .map((d) => NavigationDestination(icon: Icon(d.icon), label: d.label))
            .toList(),
      ),
    );
  }
}
