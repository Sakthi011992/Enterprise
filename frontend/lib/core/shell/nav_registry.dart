import 'package:flutter/material.dart';

import '../auth/permission_keys.dart';
import '../auth/session.dart';

/// One entry in the side nav, command palette and route guard.
class NavItem {
  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.group,
    required this.permission,
    this.min = AccessLevel.view,
    this.placeholder = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final String route;
  final String group;
  final String permission;
  final AccessLevel min;
  final bool placeholder;
}

/// Nav groups in display order. "Pinned" is built at runtime from pinned ids.
const navGroups = <String>[
  'Sales',
  'Menu & stock',
  'Guests & displays',
  'People & money',
  'Settings',
];

const navItems = <NavItem>[
  NavItem(
    id: 'dashboard',
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    route: '/dashboard',
    group: 'Sales',
    permission: Perm.reportsView,
    min: AccessLevel.limited,
  ),
  NavItem(
    id: 'pos',
    label: 'POS billing',
    icon: Icons.point_of_sale,
    route: '/pos',
    group: 'Sales',
    permission: Perm.salesOrdersTake,
    min: AccessLevel.edit,
  ),
  NavItem(
    id: 'orders',
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    route: '/orders',
    group: 'Sales',
    permission: Perm.salesOrdersTake,
  ),
  NavItem(
    id: 'menu',
    label: 'Menu & products',
    icon: Icons.inventory_2_outlined,
    route: '/menu',
    group: 'Menu & stock',
    permission: Perm.menuEdit,
  ),
  NavItem(
    id: 'stock-count',
    label: 'Stock count',
    icon: Icons.fact_check_outlined,
    route: '/stock-count',
    group: 'Menu & stock',
    permission: Perm.stockCount,
    min: AccessLevel.edit,
    placeholder: true,
  ),
  NavItem(
    id: 'my-shifts',
    label: 'My shifts',
    icon: Icons.schedule_outlined,
    route: '/my-shifts',
    group: 'People & money',
    permission: Perm.salesOrdersTake,
    placeholder: true,
  ),
  NavItem(
    id: 'users',
    label: 'Users',
    icon: Icons.people_outline,
    route: '/users',
    group: 'People & money',
    permission: Perm.adminUsers,
  ),
  NavItem(
    id: 'personas',
    label: 'Personas & permissions',
    icon: Icons.admin_panel_settings_outlined,
    route: '/settings/personas',
    group: 'People & money',
    permission: Perm.adminUsers,
  ),
  NavItem(
    id: 'outlets',
    label: 'Outlets',
    icon: Icons.storefront_outlined,
    route: '/settings/outlets',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'devices',
    label: 'Devices',
    icon: Icons.tablet_mac_outlined,
    route: '/settings/devices',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'tax',
    label: 'Tax',
    icon: Icons.percent,
    route: '/settings/tax',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'appearance',
    label: 'Appearance',
    icon: Icons.palette_outlined,
    route: '/settings/appearance',
    group: 'Settings',
    permission: Perm.adminThemes,
  ),
  NavItem(
    id: 'general',
    label: 'General settings',
    icon: Icons.settings_outlined,
    route: '/settings/general',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'branding',
    label: 'Branding & logos',
    icon: Icons.brush_outlined,
    route: '/settings/branding',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'localisation',
    label: 'Localisation',
    icon: Icons.translate,
    route: '/settings/localisation',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
  NavItem(
    id: 'kiosk',
    label: 'Kiosk',
    icon: Icons.tv_outlined,
    route: '/settings/kiosk',
    group: 'Settings',
    permission: Perm.adminSettings,
  ),
];

/// Nav items the session may see, in registry order.
List<NavItem> visibleNavItems(Session? session) {
  if (session == null) return const [];
  return [
    for (final item in navItems)
      if (session.levelOf(item.permission).atLeast(item.min)) item,
  ];
}

/// Longest nav route that equals [path] or is a parent of it, or null.
/// Used by the router to guard pages that have no nav entry of their own.
NavItem? navItemForPath(String path) {
  NavItem? best;
  for (final item in navItems) {
    final matches = path == item.route || path.startsWith('${item.route}/');
    if (matches && (best == null || item.route.length > best.route.length)) {
      best = item;
    }
  }
  return best;
}
