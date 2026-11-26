import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/guest/application/guest_controller.dart';
import 'package:pos_billing/features/guest/data/guest_models.dart';
import 'package:pos_billing/features/guest/data/guest_store.dart';
import 'package:pos_billing/features/guest/data/mock_guest_repository.dart';
import 'package:pos_billing/features/guest/presentation/guest_order_views.dart';
import 'package:pos_billing/features/guest/presentation/guest_widgets.dart';

import '../ui/test_harness.dart';
import 'guest_test_utils.dart';

void main() {
  testWidgets('welcome when seated', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository());
    expect(find.text('See menu & order'), findsOneWidget);
    expect(find.text('Call a waiter'), findsOneWidget);
    expect(find.text('View bill'), findsOneWidget);
    expect(find.textContaining('25 and over'), findsOneWidget);
  });

  testWidgets('not seated shows read-only menu', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository(seated: false));
    expect(find.text('Ask staff to seat you to start ordering.'), findsOneWidget);
    expect(find.text('Chicken Biryani'), findsOneWidget);
    expect(find.text('See menu & order'), findsNothing);
    expect(find.byType(AddButton), findsNothing);
  });

  testWidgets('details form validates name, phone and consent', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository());
    await tester.tap(find.byKey(const Key('guest-see-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guest-details-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
    expect(find.textContaining('Tick the box'), findsOneWidget);
    expect(find.text('Enter the code'), findsNothing);
  });

  test('phone and name validation rules', () {
    expect(normalisePhone('+91 98765 43210'), '9876543210');
    expect(normalisePhone('12345'), isNull);
    expect(normalisePhone('5876543210'), isNull);
    expect(validateGuestName('x' * 41), isNotNull);
    expect(validateGuestName('Deepa'), isNull);
  });

  testWidgets('6-digit code: wrong code shows tries left, then lockout', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository());
    await joinAs(tester, code: '111111');
    expect(find.byKey(const Key('guest-code-box-5')), findsOneWidget);
    expect(find.text("That code doesn't match · 4 tries left"), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byKey(const Key('guest-code-input')), '11111${i + 2}');
      await tester.pump();
      await tester.tap(find.byKey(const Key('guest-join-table')));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Too many wrong tries. Try again in'), findsOneWidget);
  });

  testWidgets('4-digit table PIN joins', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository(method: GuestVerifyMethod.tablePin));
    await joinAs(tester, code: '4817');
    expect(find.text("Ask your server for this table's 4-digit PIN"), findsNothing);
    expect(find.text('Menu'), findsOneWidget);
  });

  testWidgets('age gate before alcohol, then choices sheet rules, then cart', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository());
    await joinAs(tester);
    await tester.tap(find.bySemanticsLabel('Add Classic Mojito'));
    await tester.pumpAndSettle();
    expect(find.text('Are you 25 or over?'), findsOneWidget);
    await tester.tap(find.text("Yes, I'm 25 or over"));
    await tester.pumpAndSettle();
    expect(find.text('Pick one for Ice'), findsOneWidget);
    await tester.tap(find.text('On the rocks'));
    await tester.pump();
    expect(find.text('Add · ₹245'), findsOneWidget);
    await tester.tap(find.text('Add · ₹245'));
    await tester.pumpAndSettle();
    expect(find.text('1 item · ₹245'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guest-cart-bar')));
    await tester.pumpAndSettle();
    expect(find.text('Your waiter confirms before it goes to the kitchen.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guest-place-order')));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for waiter'), findsWidgets);
  });

  testWidgets('direct routing message', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository(routing: GuestRouting.direct));
    await joinAs(tester);
    await tester.tap(find.bySemanticsLabel('Add Chicken Biryani'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guest-cart-bar')));
    await tester.pumpAndSettle();
    expect(find.text('Goes straight to the kitchen.'), findsOneWidget);
  });

  testWidgets('every line state chip label', (tester) async {
    await tester.pumpWidget(testApp(
      child: Column(children: [
        for (final s in GuestLineState.values) LineStateChip(s),
      ]),
    ));
    for (final label in [
      'Waiting for waiter', 'Sent to kitchen', 'Cooking', 'Ready to serve', 'Served', 'Cancelled',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('rejected round shows the reason', (tester) async {
    await tester.pumpWidget(testApp(
      child: const RoundCard(
        round: GuestRound(
          id: 'r1',
          by: 'Deepa',
          status: GuestRoundStatus.rejected,
          rejectReason: 'Mojito is out of mint',
          lines: [GuestLine(name: 'Classic Mojito', qty: 2, lineTotal: 490, state: GuestLineState.cancelled)],
        ),
      ),
    ));
    expect(find.text("Your waiter couldn't take this round: Mojito is out of mint"), findsOneWidget);
  });

  testWidgets('desktop at 1280 px shows three columns', (tester) async {
    await pumpGuest(tester, repo: MockGuestRepository(), size: const Size(1280, 800));
    await joinAs(tester);
    expect(find.byKey(const Key('guest-category-rail')), findsOneWidget);
    expect(find.byKey(const Key('guest-menu-column')), findsOneWidget);
    expect(find.byKey(const Key('guest-side-panel')), findsOneWidget);
  });

  test('refresh rejoins with the stored token', () async {
    final repo = MockGuestRepository();
    final store = MemoryGuestStore(deviceKey: 'dev-1');
    final first = GuestController(qrToken: 'R4', repo: repo, store: store);
    await pumpEventQueue();
    await first.submitDetails(name: 'Deepa', phone: '9876543210', consent: true);
    await first.submitCode('246810');
    expect(first.state.stage, GuestStage.ordering);
    first.dispose();
    repo.token = null;

    final second = GuestController(qrToken: 'R4', repo: repo, store: store);
    await pumpEventQueue();
    expect(second.state.stage, GuestStage.ordering);
    expect(second.state.guest?.name, 'Deepa');
    expect((await store.guestFor('R4'))?.token, isNotNull);
    second.dispose();
  });
}
