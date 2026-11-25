import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/session.dart';

Map<String, dynamic> sampleSessionJson() => {
      'user': {'id': 'u1', 'username': 'priya', 'displayName': 'Priya', 'email': 'priya@example.com'},
      'tenant': {'id': 't1', 'name': 'Your Venue'},
      'outlet': {'id': 'o1', 'name': 'Main outlet', 'code': 'MAIN'},
      'persona': {'id': 'p1', 'key': 'manager', 'name': 'Manager', 'homeRoute': '/dashboard'},
      'permissions': {
        'menu.edit': {'level': 'EDIT', 'limit': null},
        'sales.discount.give': {'level': 'LIMITED', 'limit': 30},
        'admin.users': {'level': 'NONE', 'limit': null},
      },
      'outlets': [
        {
          'id': 'o1',
          'name': 'Main outlet',
          'code': 'MAIN',
          'persona': {'key': 'manager', 'name': 'Manager'},
          'isDefault': true,
        },
      ],
      'role': 'USER',
    };

void main() {
  group('AccessLevel', () {
    test('ordering follows NONE < VIEW < REQUEST < LIMITED < APPROVE < EDIT', () {
      final order = AccessLevel.values;
      expect(order, [
        AccessLevel.none,
        AccessLevel.view,
        AccessLevel.request,
        AccessLevel.limited,
        AccessLevel.approve,
        AccessLevel.edit,
      ]);
      expect(AccessLevel.edit.atLeast(AccessLevel.view), isTrue);
      expect(AccessLevel.view.atLeast(AccessLevel.view), isTrue);
      expect(AccessLevel.request.atLeast(AccessLevel.limited), isFalse);
      expect(AccessLevel.none.atLeast(AccessLevel.view), isFalse);
    });

    test('fromWire maps wire strings and falls back to NONE', () {
      expect(AccessLevel.fromWire('LIMITED'), AccessLevel.limited);
      expect(AccessLevel.fromWire('bogus'), AccessLevel.none);
      expect(AccessLevel.fromWire(null), AccessLevel.none);
    });
  });

  group('Session', () {
    test('fromJson reads every field', () {
      final s = Session.fromJson(sampleSessionJson());
      expect(s.user.label, 'Priya');
      expect(s.tenant.name, 'Your Venue');
      expect(s.outlet.code, 'MAIN');
      expect(s.persona.homeRoute, '/dashboard');
      expect(s.permissions['sales.discount.give']!.level, AccessLevel.limited);
      expect(s.permissions['sales.discount.give']!.limit, 30);
      expect(s.outlets.single.isDefault, isTrue);
      expect(s.outlets.single.persona.name, 'Manager');
      expect(s.role, 'USER');
      expect(s.isAdmin, isFalse);
    });

    test('a missing permission key is NONE', () {
      final s = Session.fromJson(sampleSessionJson());
      expect(s.levelOf('stock.count'), AccessLevel.none);
      expect(s.levelOf('menu.edit'), AccessLevel.edit);
    });

    test('toJson then fromJson round-trips', () {
      final original = sampleSessionJson();
      final once = Session.fromJson(original).toJson();
      expect(jsonEncode(once), jsonEncode(original));
      final again = Session.fromJson(once);
      expect(again.persona.key, 'manager');
      expect(again.permissions.length, 3);
      expect(again.permissions['sales.discount.give']!.limit, 30);
    });

    test('a user without a display name falls back to the username', () {
      final json = sampleSessionJson();
      json['user'] = <String, dynamic>{...(json['user'] as Map), 'displayName': null};
      expect(Session.fromJson(json).user.label, 'priya');
    });
  });
}
