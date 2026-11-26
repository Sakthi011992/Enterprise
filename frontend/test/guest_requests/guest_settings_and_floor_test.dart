import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/shell/mobile_nav.dart';
import 'package:pos_billing/core/shell/nav_registry.dart';
import 'package:pos_billing/features/floor/data/floor_repository.dart';
import 'package:pos_billing/features/guest_requests/data/guest_models.dart';
import 'package:pos_billing/features/guest_requests/presentation/floor_guest_widgets.dart';
import 'package:pos_billing/features/guest_requests/presentation/kds_qr_label.dart';
import 'package:pos_billing/features/kds/data/kds_models.dart';
import 'package:pos_billing/features/settings/presentation/guest_ordering_settings_screen.dart';

import 'guest_test_helpers.dart';

final adminSession = testSession(persona: 'admin', permissions: {
  Perm.adminSettings: grant(AccessLevel.edit),
  Perm.guestsOrdersConfirm: grant(AccessLevel.edit),
  Perm.salesOrdersTake: grant(AccessLevel.edit),
});

Future<void> bigView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Settings › Guest ordering', () {
    testWidgets('routing switch saves DIRECT and shows a toast', (tester) async {
      await bigView(tester);
      final repo = demoRepo();
      await tester.pumpWidget(guestTestApp(
          repo: repo, session: adminSession, child: const GuestOrderingSettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Direct to kitchen'), findsOneWidget);
      expect(find.text('A waiter checks and confirms each round first.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('routing-direct')));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect((await repo.config()).routing, GuestRouting.direct);
      expect(find.textContaining('Guest ordering saved'), findsOneWidget);
    });

    testWidgets('Set new code validates digits and match, then is sent on save', (tester) async {
      await bigView(tester);
      final repo = demoRepo();
      await tester.pumpWidget(guestTestApp(
          repo: repo, session: adminSession, child: const GuestOrderingSettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('••••••', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Set new code'));
      await tester.pumpAndSettle();
      final newField = find.descendant(of: find.byKey(const ValueKey('otp-new')), matching: find.byType(TextField));
      final again = find.descendant(of: find.byKey(const ValueKey('otp-again')), matching: find.byType(TextField));

      await tester.enterText(newField, '12a');
      await tester.tap(find.text('Set code'));
      await tester.pump();
      expect(find.text('Enter 6 digits'), findsOneWidget);

      await tester.enterText(newField, '135790');
      await tester.enterText(again, '135791');
      await tester.tap(find.text('Set code'));
      await tester.pump();
      expect(find.text("The codes don't match"), findsOneWidget);

      await tester.enterText(again, '135790');
      await tester.tap(find.text('Set code'));
      await tester.pumpAndSettle();
      expect(find.text('Set code'), findsNothing);

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(repo.lastNewStaticOtp, '135790');
    });

    testWidgets('SMS OTP and Pay online are disabled "Coming soon"', (tester) async {
      await bigView(tester);
      final repo = demoRepo();
      await tester.pumpWidget(guestTestApp(
          repo: repo, session: adminSession, child: const GuestOrderingSettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('verify-sms')));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect((await repo.config()).method, GuestVerifyMethods.staticOtp);
    });

    testWidgets('invalid minimum age and expiry block save', (tester) async {
      await bigView(tester);
      final repo = demoRepo();
      await tester.pumpWidget(guestTestApp(
          repo: repo, session: adminSession, child: const GuestOrderingSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Minimum age 25'), findsOneWidget);

      await tester.enterText(
          find.descendant(of: find.byKey(const ValueKey('min-age')), matching: find.byType(TextField)), '12');
      await tester.enterText(
          find.descendant(of: find.byKey(const ValueKey('ttl')), matching: find.byType(TextField)), '0');
      await tester.tap(find.byKey(const ValueKey('routing-direct')));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an age from 18 to 99'), findsOneWidget);
      expect(find.text('Enter 1 to 120 minutes'), findsOneWidget);
      expect((await repo.config()).routing, GuestRouting.waiter);
    });
  });

  group('Floor plan badges', () {
    Widget badges(String id, String status) =>
        guestTestApp(repo: demoRepo(), child: TableGuestBadges(tableId: id, status: status));

    testWidgets('new round badge', (tester) async {
      await tester.pumpWidget(badges('t-r4', TableStatus.occupied));
      await tester.pumpAndSettle();
      expect(find.text('QR · 1 new round'), findsOneWidget);
    });

    testWidgets('bill asked badge', (tester) async {
      await tester.pumpWidget(badges('t-r2', TableStatus.occupied));
      await tester.pumpAndSettle();
      expect(find.text('Bill asked'), findsOneWidget);
    });

    testWidgets('PIN shows only on a seated table', (tester) async {
      await tester.pumpWidget(badges('t-b2', TableStatus.occupied));
      await tester.pumpAndSettle();
      expect(find.text('4817'), findsOneWidget);

      await tester.pumpWidget(badges('t-b2', TableStatus.free));
      await tester.pumpAndSettle();
      expect(find.text('4817'), findsNothing);
    });
  });

  testWidgets('Rotate QR asks first, then calls the API', (tester) async {
    await bigView(tester);
    final repo = demoRepo();
    const area = FloorArea(id: 'a', name: 'Rooftop');
    const table = FloorTable(
        id: 't-r4', name: 'R4', areaId: 'a', seats: 4, shape: 'SQUARE', posX: 0, posY: 0, status: 'FREE');
    await tester.pumpWidget(guestTestApp(
        repo: repo, session: adminSession, child: const FloorQrActions(area: area, tables: [table])));
    await tester.pumpAndSettle();
    expect(find.text('Print QR sheet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rotate-t-r4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('open guest session'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Rotate QR')));
    await tester.pumpAndSettle();
    expect(repo.rotated, ['t-r4']);
  });

  group('Footer tabs', () {
    final visible = [
      for (final i in navItems)
        if (['floor', 'pos', 'orders', 'guest-orders', 'ready', 'bar-tabs'].contains(i.id)) i
    ];

    test('waiter and captain get Guest orders instead of Orders', () {
      for (final persona in ['waiter', 'captain']) {
        final ids = mobileTabs(testSession(persona: persona), visible).map((i) => i.id).toList();
        expect(ids, contains('guest-orders'), reason: persona);
        expect(ids, isNot(contains('orders')), reason: persona);
      }
    });

    test('a waiter without the guest permission keeps Orders', () {
      final ids = mobileTabs(testSession(),
              [for (final i in visible) if (i.id != 'guest-orders') i])
          .map((i) => i.id)
          .toList();
      expect(ids, contains('orders'));
    });

    testWidgets('the Guest orders tab shows the live count', (tester) async {
      final session = testSession();
      await tester.pumpWidget(guestTestApp(
        repo: demoRepo(),
        session: session,
        child: Consumer(
          builder: (_, __, ___) => Align(
            alignment: Alignment.bottomCenter,
            child: MobileNavBar(visible: visible, location: '/floor', session: session),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Guest orders'), findsOneWidget);
      expect(find.text('Orders'), findsNothing);
      // 2 pending rounds + 2 unacknowledged service requests.
      expect(find.byKey(const ValueKey('guest-orders-badge')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  test('KDS label reads QR source and guest name defensively', () {
    KdsTicket ticket(Map<String, dynamic> order, [List<Map<String, dynamic>> items = const []]) =>
        KdsTicket.fromJson({'id': 'k', 'label': 'KOT 214', 'order': order, 'items': items});
    expect(kdsQrLabel(ticket({'id': 'o', 'tableName': 'R4'})), isNull);
    expect(kdsQrLabel(ticket({'id': 'o', 'source': 'GUEST_QR', 'guestName': 'Arun'})), 'QR · Arun');
    expect(
        kdsQrLabel(ticket({'id': 'o', 'source': 'GUEST_QR'}, [
          {'orderItemId': 'i', 'name': 'Wings', 'guestName': 'Arun'}
        ])),
        'QR · Arun');
  });
}
