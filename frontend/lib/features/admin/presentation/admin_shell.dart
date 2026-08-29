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
import '../../localisation/presentation/localisation_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../kiosk/presentation/kiosk_admin_screen.dart';
import '../../branding/presentation/branding_screen.dart';

typedef _Dest = ({IconData icon, String label, AppFeature feature, Widget page});

const _allDests = <_Dest>[
  (icon: Icons.dashboard,      label: 'Dashboard',    feature: AppFeature.dashboard,    page: DashboardScreen()),
  (icon: Icons.inventory_2,    label: 'Products',     feature: AppFeature.products,     page: ProductsScreen()),
  (icon: Icons.percent,        label: 'Tax',          feature: AppFeature.tax,          page: TaxSettingsScreen()),
  (icon: Icons.people,         label: 'Users',        feature: AppFeature.users,        page: UsersScreen()),
  (icon: Icons.receipt_long,   label: 'Orders',       feature: AppFeature.orders,       page: OrderHistoryScreen()),
  (icon: Icons.palette,        label: 'Appearance',   feature: AppFeature.appearance,   page: AppearanceSettingsPage()),
  (icon: Icons.brush,          label: 'Branding',     feature: AppFeature.branding,     page: BrandingScreen()),
  (icon: Icons.translate,      label: 'Localisation', feature: AppFeature.localisation, page: LocalisationScreen()),
  (icon: Icons.settings,       label: 'Settings',     feature: AppFeature.settings,     page: SettingsScreen()),
  (icon: Icons.tv,             label: 'Kiosk',        feature: AppFeature.kioskAdmin,   page: KioskAdminScreen()),
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

    final safeIndex = _index.clamp(0, dests.isEmpty ? 0 : dests.length - 1);
    if (safeIndex != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _index = safeIndex));
    }

    if (dests.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text('No features enabled for your account.\nContact an admin.',
              textAlign: TextAlign.center),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width > 760;
    final t = context.tokens;

    if (wide) {
      final extended = MediaQuery.of(context).size.width > 1100;
      return Scaffold(
        body: Row(children: [
          SizedBox(
            width: extended ? 200 : 80,
            child: Column(children: [
              SizedBox(height: t.spacing.step(3)),
              Icon(Icons.point_of_sale, size: 28, color: t.color.background.accent),
              SizedBox(height: t.spacing.xs),
              IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Logout'),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: dests.length,
                  itemBuilder: (_, i) {
                    final d = dests[i];
                    final selected = i == safeIndex;
                    return Tooltip(
                      message: extended ? '' : d.label,
                      child: InkWell(
                        onTap: () => setState(() => _index = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: selected
                                ? t.color.background.accent.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(t.radius.md),
                          ),
                          margin: EdgeInsets.symmetric(horizontal: t.spacing.xs, vertical: 2),
                          padding: EdgeInsets.symmetric(
                            horizontal: extended ? t.spacing.sm : 0,
                            vertical: t.spacing.sm,
                          ),
                          child: extended
                              ? Row(children: [
                                  Icon(d.icon,
                                      color: selected
                                          ? t.color.background.accent
                                          : t.color.content.secondary),
                                  SizedBox(width: t.spacing.sm),
                                  Expanded(
                                    child: Text(d.label,
                                        style: TextStyle(
                                          color: selected
                                              ? t.color.background.accent
                                              : t.color.content.secondary,
                                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                        )),
                                  ),
                                ])
                              : Center(
                                  child: Icon(d.icon,
                                      color: selected
                                          ? t.color.background.accent
                                          : t.color.content.secondary),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: t.color.background.accent.withValues(alpha: 0.1)),
              child: Row(children: [
                Icon(Icons.point_of_sale, size: 32, color: t.color.background.accent),
                SizedBox(width: t.spacing.sm),
                const Text('POS Admin', style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
            ...dests.asMap().entries.map((e) => ListTile(
                  leading: Icon(e.value.icon,
                      color: e.key == safeIndex ? t.color.background.accent : null),
                  title: Text(e.value.label),
                  selected: e.key == safeIndex,
                  onTap: () {
                    setState(() => _index = e.key);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
      body: dests[safeIndex].page,
    );
  }
}
