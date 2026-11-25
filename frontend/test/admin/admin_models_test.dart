import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/features/devices/data/devices_repository.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';
import 'package:pos_billing/features/personas/data/persona_models.dart';
import 'package:pos_billing/features/users/data/users_repository.dart';

void main() {
  group('persona models', () {
    test('a limit is sent only with LIMITED', () {
      const limited = PersonaGrant(key: 'sales.discount.give', level: AccessLevel.limited, limit: 10);
      const edit = PersonaGrant(key: 'menu.edit', level: AccessLevel.edit, limit: 5);

      expect(limited.toJson(), {'key': 'sales.discount.give', 'level': 'LIMITED', 'limit': 10});
      expect(edit.toJson(), {'key': 'menu.edit', 'level': 'EDIT', 'limit': null});
    });

    test('cell labels show the limit and unit', () {
      const percent = CatalogEntry(
        key: 'sales.discount.give',
        group: 'Sales',
        label: 'Give discount',
        limitUnit: 'percent',
        sortOrder: 1,
      );
      const inr = CatalogEntry(
        key: 'sales.tab.open',
        group: 'Sales',
        label: 'Open bar tab',
        limitUnit: 'inr',
        sortOrder: 2,
      );
      const grant = PersonaGrant(key: 'x', level: AccessLevel.limited, limit: 10);

      expect(permissionLabel(grant, percent), 'Limited ≤ 10%');
      expect(permissionLabel(grant, inr), 'Limited ≤ ₹10');
      expect(permissionLabel(const PersonaGrant(key: 'x', level: AccessLevel.view), null), 'View');
    });

    test('groups keep sortOrder and the group order follows the first entry', () {
      const catalog = [
        CatalogEntry(key: 'menu.edit', group: 'Menu & stock', label: 'Edit menu', sortOrder: 3),
        CatalogEntry(key: 'sales.void', group: 'Sales', label: 'Void', sortOrder: 2),
        CatalogEntry(key: 'sales.orders.take', group: 'Sales', label: 'Take orders', sortOrder: 1),
      ];

      final groups = groupCatalog(catalog);
      expect(groups.map((g) => g.key), ['Sales', 'Menu & stock']);
      expect(groups.first.value.map((e) => e.key), ['sales.orders.take', 'sales.void']);
    });

    test('unknown API levels fall back to NONE', () {
      expect(accessLevelFromApi('EDIT'), AccessLevel.edit);
      expect(accessLevelFromApi('SOMETHING_NEW'), AccessLevel.none);
      expect(accessLevelFromApi(null), AccessLevel.none);
    });

    test('home routes have readable labels', () {
      expect(homeRouteLabel('/pos'), 'POS billing');
      expect(homeRouteLabel('/custom'), '/custom');
    });
  });

  group('user models', () {
    test('label falls back to the username when there is no display name', () {
      final user = AppUser.fromJson({'id': 'u1', 'username': 'bartender1'});
      expect(user.label, 'bartender1');
      expect(user.isActive, isTrue);
      expect(user.hasPin, isFalse);
      expect(user.outlets, isEmpty);
    });

    test('parses outlets and PIN state', () {
      final user = AppUser.fromJson({
        'id': 'u2',
        'username': 'priya',
        'displayName': 'Priya',
        'isActive': false,
        'hasPin': true,
        'outlets': [
          {
            'outletId': 'o1',
            'outletName': 'Main outlet',
            'personaId': 'p1',
            'personaName': 'Manager',
            'isDefault': true,
          },
        ],
      });

      expect(user.label, 'Priya');
      expect(user.isActive, isFalse);
      expect(user.hasPin, isTrue);
      expect(user.outlets.single.personaName, 'Manager');
      expect(user.outlets.single.isDefault, isTrue);
    });

    test('outlet assignment input matches the PUT body', () {
      const input = OutletAssignmentInput(outletId: 'o1', personaId: 'p1', isDefault: true);
      expect(input.toJson(), {'outletId': 'o1', 'personaId': 'p1', 'isDefault': true});
    });
  });

  group('devices', () {
    test('device types have plain labels', () {
      expect(deviceTypeLabel('POS_TABLET'), 'POS tablet');
      expect(deviceTypeLabel('KDS'), 'Kitchen display (KDS)');
    });
  });

  group('AdminApiError', () {
    test('known codes map to friendly sentences', () {
      const inUse = AdminApiError(status: 409, code: 'PERSONA_IN_USE', message: 'raw');
      expect(inUse.friendly, contains('still assigned'));

      const tooSimple = AdminApiError(status: 400, code: 'PIN_TOO_SIMPLE', message: 'raw');
      expect(tooSimple.friendly, contains('too easy to guess'));
    });

    test('a 403 without a known code says there is no permission', () {
      const forbidden = AdminApiError(status: 403, message: 'raw');
      expect(forbidden.friendly, "You don't have permission to do that.");
    });

    test('unknown codes keep the server message', () {
      const other = AdminApiError(status: 500, code: 'SOMETHING', message: 'Server says no');
      expect(other.friendly, 'Server says no');
    });
  });

  test('listFrom accepts a bare array and a { data } envelope', () {
    expect(listFrom([
      {'id': 'a'},
    ]), [
      {'id': 'a'},
    ]);
    expect(listFrom({
      'data': [
        {'id': 'b'},
      ],
    }), [
      {'id': 'b'},
    ]);
  });
}
