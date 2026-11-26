import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/shell/nav_registry.dart';

/// Builds a session whose permissions are the default matrix column (PLAN 1.2)
/// for one persona. Keys not listed are NONE.
Session sessionWith(Map<String, PermissionGrant> grants, {String role = 'USER'}) {
  return Session(
    user: const SessionUser(id: 'u', username: 'tester', displayName: 'Tester'),
    tenant: const NamedRef(id: 't', name: 'Default venue'),
    outlet: const OutletRef(id: 'o', name: 'Main outlet', code: 'MAIN'),
    persona: const PersonaRef(id: 'p', key: 'x', name: 'X', homeRoute: '/pos'),
    permissions: grants,
    outlets: const [],
    role: role,
  );
}

PermissionGrant g(AccessLevel level, [num? limit]) => PermissionGrant(level: level, limit: limit);

List<String> visibleIds(Map<String, PermissionGrant> grants, {String role = 'USER'}) =>
    [for (final i in visibleNavItems(sessionWith(grants, role: role))) i.id];

/// Bartender column from the catalog (backend/src/common/permissions/catalog.ts,
/// with kds.bump EDIT per PLAN 1.6).
Map<String, PermissionGrant> bartenderMatrix() => {
      Perm.salesOrdersTake: g(AccessLevel.edit),
      Perm.salesPaymentsTake: g(AccessLevel.edit),
      Perm.salesDiscountGive: g(AccessLevel.limited, 5),
      Perm.salesVoid: g(AccessLevel.request),
      Perm.salesTabOpen: g(AccessLevel.limited, 10000),
      Perm.menuEdit: g(AccessLevel.view),
      Perm.menuMark86: g(AccessLevel.edit),
      Perm.stockCount: g(AccessLevel.edit),
      Perm.guestsQueue: g(AccessLevel.view),
      Perm.kdsBump: g(AccessLevel.edit),
    };

/// Chef column: menu view, 86 and count edit, POs request, kitchen display edit.
Map<String, PermissionGrant> chefMatrix() => {
      Perm.menuEdit: g(AccessLevel.view),
      Perm.menuMark86: g(AccessLevel.edit),
      Perm.stockCount: g(AccessLevel.edit),
      Perm.stockPurchaseOrders: g(AccessLevel.request),
      Perm.kdsBump: g(AccessLevel.edit),
    };

/// Storekeeper column: no kitchen display, reports limited.
Map<String, PermissionGrant> storekeeperMatrix() => {
      Perm.menuEdit: g(AccessLevel.view),
      Perm.menuMark86: g(AccessLevel.edit),
      Perm.stockCount: g(AccessLevel.edit),
      Perm.stockPurchaseOrders: g(AccessLevel.edit),
      Perm.reportsView: g(AccessLevel.limited),
    };

/// Waiter column: orders, menu view, kitchen display view.
Map<String, PermissionGrant> waiterMatrix() => {
      Perm.salesOrdersTake: g(AccessLevel.edit),
      Perm.salesVoid: g(AccessLevel.request),
      Perm.menuEdit: g(AccessLevel.view),
      Perm.guestsQueue: g(AccessLevel.view),
      Perm.kdsBump: g(AccessLevel.view),
    };

/// Admin column from the default matrix: EDIT on every key.
Map<String, PermissionGrant> adminMatrix() => {
      for (final key in [
        Perm.salesOrdersTake,
        Perm.salesPaymentsTake,
        Perm.salesDiscountGive,
        Perm.salesVoid,
        Perm.salesTabOpen,
        Perm.menuEdit,
        Perm.menuMark86,
        Perm.stockCount,
        Perm.stockPurchaseOrders,
        Perm.guestsQueue,
        Perm.displaysControl,
        Perm.guestsOrdersConfirm,
        Perm.reportsView,
        Perm.adminUsers,
        Perm.adminSettings,
        Perm.adminThemes,
        Perm.kdsBump,
      ])
        key: g(AccessLevel.edit),
    };

void main() {
  test('Bartender sees exactly the 11 POS, bar and back-office items', () {
    // Phase 2 showed 6. Phase 3 adds bar tabs, kitchen display, ready to
    // serve, availability and inventory (procurement needs purchaseOrders).
    final items = visibleNavItems(sessionWith(bartenderMatrix()));
    expect(items.map((i) => i.id).toList(), [
      'pos',
      'orders',
      'floor',
      'bar-tabs',
      'kds',
      'ready',
      'menu',
      'availability',
      'stock-count',
      'inventory',
      'my-shifts',
    ]);
    expect(items.length, 11);
  });

  test('Bartender does not see day close, procurement or hardware', () {
    final ids = visibleNavItems(sessionWith(bartenderMatrix())).map((i) => i.id).toSet();
    expect(ids.contains('day-close'), isFalse);
    expect(ids.contains('procurement'), isFalse);
    expect(ids.contains('dashboard'), isFalse);
    expect(ids.contains('hardware'), isFalse);
    expect(ids.contains('floor-setup'), isFalse);
  });

  test('Chef sees menu, stock count, kitchen display, ready list, inventory, procurement and availability', () {
    expect(visibleIds(chefMatrix()), [
      'kds',
      'ready',
      'menu',
      'availability',
      'stock-count',
      'inventory',
      'procurement',
    ]);
  });

  test('Storekeeper sees dashboard, day close and the stock pages, but no kitchen display', () {
    expect(visibleIds(storekeeperMatrix()), [
      'dashboard',
      'day-close',
      'menu',
      'availability',
      'stock-count',
      'inventory',
      'procurement',
    ]);
  });

  test('Waiter sees orders, the kitchen display and the ready list, but not stock', () {
    expect(visibleIds(waiterMatrix()), [
      'pos',
      'orders',
      'floor',
      'kds',
      'ready',
      'menu',
      'my-shifts',
    ]);
  });

  test('Admin sees every nav item', () {
    final items = visibleNavItems(sessionWith(adminMatrix(), role: 'ADMIN'));
    expect(items.map((i) => i.id).toSet(), navItems.map((i) => i.id).toSet());
    expect(items.length, navItems.length);
  });

  test('no session means no nav items', () {
    expect(visibleNavItems(null), isEmpty);
  });

  test('stock count is a real page now, not a placeholder', () {
    final item = navItems.firstWhere((i) => i.id == 'stock-count');
    expect(item.placeholder, isFalse);
    expect(item.route, '/stock-count');
  });

  test('pages without a nav entry of their own inherit their parent permission', () {
    expect(navItemForPath('/settings/appearance/themes/abc')?.id, 'appearance');
    expect(navItemForPath('/pos')?.id, 'pos');
    expect(navItemForPath('/pos/abc/pay')?.id, 'pos');
    expect(navItemForPath('/menu/products/abc')?.id, 'menu');
    expect(navItemForPath('/menu/happy-hours')?.id, 'menu');
    expect(navItemForPath('/menu/availability')?.id, 'availability');
    expect(navItemForPath('/settings/hardware')?.id, 'hardware');
    expect(navItemForPath('/inventory/items/abc')?.id, 'inventory');
    expect(navItemForPath('/procurement/po/abc')?.id, 'procurement');
    expect(navItemForPath('/procurement/grn/abc')?.id, 'procurement');
    expect(navItemForPath('/procurement/reorder')?.id, 'procurement');
    expect(navItemForPath('/tabs')?.id, 'bar-tabs');
    expect(navItemForPath('/kds')?.id, 'kds');
    expect(navItemForPath('/service/ready')?.id, 'ready');
    expect(navItemForPath('/posts'), isNull);
  });

  test('bartender is blocked from admin pages', () {
    final s = sessionWith(bartenderMatrix());
    for (final route in [
      '/users',
      '/settings/tax',
      '/settings/devices',
      '/settings/appearance',
      '/settings/hardware',
      '/settings/floor',
      '/reports/day-close',
      '/procurement',
      '/procurement/po/abc',
    ]) {
      final item = navItemForPath(route)!;
      expect(s.levelOf(item.permission).atLeast(item.min), isFalse, reason: route);
    }
  });

  test('bartender may open the bar tabs, kitchen display and inventory pages', () {
    final s = sessionWith(bartenderMatrix());
    for (final route in ['/tabs', '/kds', '/service/ready', '/inventory', '/menu/availability']) {
      final item = navItemForPath(route)!;
      expect(s.levelOf(item.permission).atLeast(item.min), isTrue, reason: route);
    }
  });
}
