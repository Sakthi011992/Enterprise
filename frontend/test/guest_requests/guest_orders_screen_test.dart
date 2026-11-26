import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/guest_requests/data/guest_models.dart';
import 'package:pos_billing/features/guest_requests/data/mock_guest_requests_repository.dart';
import 'package:pos_billing/features/guest_requests/presentation/guest_orders_screen.dart';

import 'guest_test_helpers.dart';

Finder inCard(String id, Finder f) => find.descendant(of: find.byKey(ValueKey('round-$id')), matching: f);

Future<void> pumpScreen(WidgetTester tester, MockGuestRequestsRepository repo) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(guestTestApp(repo: repo, child: const GuestOrdersScreen()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('round card shows table, guest, masked mobile, lines, total and actions', (tester) async {
    await pumpScreen(tester, demoRepo());
    expect(inCard('gr-r4', find.text('R4')), findsOneWidget);
    expect(inCard('gr-r4', find.text('Deepa')), findsOneWidget);
    expect(inCard('gr-r4', find.text('+91 98•••••210')), findsOneWidget);
    expect(inCard('gr-r4', find.text('Classic Mojito · On the rocks')), findsOneWidget);
    expect(inCard('gr-r4', find.text('₹490')), findsOneWidget);
    expect(inCard('gr-r4', find.text('₹220')), findsOneWidget);
    expect(inCard('gr-r4', find.text('1 min')), findsOneWidget);
    for (final a in ['Reject', 'Claim', 'Confirm']) {
      expect(inCard('gr-r4', find.text(a)), findsOneWidget);
    }
  });

  testWidgets('a round claimed by someone else shows "Ravi is on it" and no actions', (tester) async {
    await pumpScreen(tester, demoRepo());
    expect(inCard('gr-t7', find.text('Ravi is on it')), findsOneWidget);
    expect(inCard('gr-t7', find.text('Claim')), findsNothing);
    expect(inCard('gr-t7', find.text('Confirm')), findsNothing);
  });

  testWidgets('Claim hides the Claim button for the claiming waiter', (tester) async {
    final repo = demoRepo();
    await pumpScreen(tester, repo);
    await tester.tap(inCard('gr-r4', find.text('Claim')));
    await tester.pumpAndSettle();
    expect(inCard('gr-r4', find.text('Claim')), findsNothing);
    expect(inCard('gr-r4', find.text('Confirm')), findsOneWidget);
    expect(inCard('gr-r4', find.textContaining('is on it')), findsNothing);
  });

  testWidgets('edit sheet changes qty, removes a line and confirms the edited items', (tester) async {
    final repo = demoRepo();
    await pumpScreen(tester, repo);
    await tester.tap(inCard('gr-r4', find.text('Confirm')));
    await tester.pumpAndSettle();

    expect(find.text('R4 · Deepa'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Alcohol in this round. Check ID if unsure.'), findsOneWidget);
    expect(find.byKey(const ValueKey('round-total')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('round-total'))).data, '₹710');

    await tester.tap(find.byTooltip('One more Classic Mojito'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove Virgin Colada'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('round-total'))).data, '₹735');

    await tester.tap(find.text('Confirm & send'));
    await tester.pumpAndSettle();

    final sent = repo.lastConfirm!;
    expect(sent.id, 'gr-r4');
    expect(sent.items, hasLength(1));
    expect(sent.items!.single.productId, 'p-mojito');
    expect(sent.items!.single.quantity, 3);
    expect(sent.items!.single.toConfirmJson()['modifiers'], [
      {'groupId': 'g-ice', 'optionId': 'o-rocks'}
    ]);
    // Confirmed rounds leave the list.
    expect(find.byKey(const ValueKey('round-gr-r4')), findsNothing);
  });

  testWidgets('confirm without edits sends no items (as placed)', (tester) async {
    final repo = demoRepo();
    await pumpScreen(tester, repo);
    await tester.tap(inCard('gr-r4', find.text('Confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & send'));
    await tester.pumpAndSettle();
    expect(repo.lastConfirm!.items, isNull);
  });

  testWidgets('reject requires a reason', (tester) async {
    final repo = demoRepo();
    await pumpScreen(tester, repo);
    await tester.tap(inCard('gr-r4', find.text('Reject')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reject round'));
    await tester.pumpAndSettle();
    expect(find.text('Deepa sees this reason. Enter one to reject.'), findsOneWidget);
    expect(repo.lastReject, isNull);

    await tester.enterText(find.byType(TextField), 'Mojito is sold out');
    await tester.tap(find.text('Reject round'));
    await tester.pumpAndSettle();
    expect(repo.lastReject, (id: 'gr-r4', reason: 'Mojito is sold out'));
    expect(find.byKey(const ValueKey('round-gr-r4')), findsNothing);
  });

  testWidgets('service request Ack then Done', (tester) async {
    final repo = demoRepo();
    await pumpScreen(tester, repo);
    final r2 = find.byKey(const ValueKey('service-sr-r2'));
    expect(find.descendant(of: r2, matching: find.text('Bill please')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('service-sr-b5')), matching: find.text('Call waiter')),
        findsOneWidget);

    await tester.tap(find.descendant(of: r2, matching: find.text('Ack')));
    await tester.pumpAndSettle();
    expect(repo.acked, ['sr-r2']);
    expect(find.descendant(of: r2, matching: find.text('Done')), findsOneWidget);

    await tester.tap(find.descendant(of: r2, matching: find.text('Done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-sr-r2')), findsNothing);
  });

  testWidgets('empty state when nothing is waiting', (tester) async {
    await pumpScreen(tester, MockGuestRequestsRepository(requests: [], serviceRequests: []));
    expect(find.text('No guest orders waiting'), findsOneWidget);
  });

  test('GuestRequest parses the staff API shape defensively', () {
    final r = GuestRequest.fromJson({
      'id': 'x',
      'table': {'id': 't1', 'name': 'R4'},
      'participant': {'name': 'Deepa', 'phone': '+919876543210'},
      'items': [
        {'productId': 'p', 'name': 'Mojito', 'quantity': 2, 'lineTotal': '490.00', 'isAlcohol': true}
      ],
      'claimedBy': {'id': 'u-ravi', 'displayName': 'Ravi'},
      'createdAt': '2026-11-26T10:00:00Z',
    });
    expect(r.tableName, 'R4');
    expect(r.phoneMasked, '+91 98•••••210');
    expect(r.total, 490);
    expect(r.lines.single.unitPrice, 245);
    expect(r.claimedByName, 'Ravi');
  });
}
