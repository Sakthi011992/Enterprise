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

/// Bartender column from the default matrix (PLAN 1.2).
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
        Perm.reportsView,
        Perm.adminUsers,
        Perm.adminSettings,
        Perm.adminThemes,
      ])
        key: g(AccessLevel.edit),
    };

void main() {
  test('Bartender sees exactly the 5 exit-test items', () {
    final items = visibleNavItems(sessionWith(bartenderMatrix()));
    expect(items.map((i) => i.id).toList(), [
      'pos',
      'orders',
      'menu',
      'stock-count',
      'my-shifts',
    ]);
    expect(items.length, 5);
  });

  test('Admin sees every nav item', () {
    final items = visibleNavItems(sessionWith(adminMatrix(), role: 'ADMIN'));
    expect(items.map((i) => i.id).toSet(), navItems.map((i) => i.id).toSet());
    expect(items.length, navItems.length);
  });

  test('no session means no nav items', () {
    expect(visibleNavItems(null), isEmpty);
  });

  test('pages without a nav entry of their own inherit their parent permission', () {
    expect(navItemForPath('/settings/appearance/themes/abc')?.id, 'appearance');
    expect(navItemForPath('/pos')?.id, 'pos');
    expect(navItemForPath('/posts'), isNull);
  });

  test('bartender is blocked from admin pages', () {
    final s = sessionWith(bartenderMatrix());
    for (final route in ['/users', '/settings/tax', '/settings/devices', '/settings/appearance']) {
      final item = navItemForPath(route)!;
      expect(s.levelOf(item.permission).atLeast(item.min), isFalse, reason: route);
    }
  });
}
