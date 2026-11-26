import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/features/guest/data/guest_repository.dart';
import 'package:pos_billing/features/guest/data/guest_store.dart';
import 'package:pos_billing/features/guest/data/mock_guest_repository.dart';
import 'package:pos_billing/features/guest/presentation/guest_screen.dart';

import '../ui/test_harness.dart';

Future<void> pumpGuest(
  WidgetTester tester, {
  required MockGuestRepository repo,
  GuestStore? store,
  String qr = 'R4',
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      guestRepositoryProvider.overrideWithValue(repo),
      guestStoreProvider.overrideWithValue(store ?? MemoryGuestStore(deviceKey: 'dev-1')),
      guestPollIntervalProvider.overrideWithValue(null),
    ],
    child: TokenTheme(
      tokens: testTokens.light,
      child: MaterialApp(
        theme: AppTheme.from(testTokens.light, Brightness.light),
        home: GuestScreen(qrToken: qr),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Welcome → details → code → menu.
Future<void> joinAs(WidgetTester tester, {String name = 'Deepa', String code = '246810'}) async {
  await tester.tap(find.byKey(const Key('guest-see-menu')));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byKey(const Key('guest-name')), matching: find.byType(TextField)), name);
  await tester.enterText(find.descendant(of: find.byKey(const Key('guest-phone')), matching: find.byType(TextField)), '9876543210');
  await tester.tap(find.byKey(const Key('guest-consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('guest-details-continue')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('guest-code-input')), code);
  await tester.pump();
  await tester.tap(find.byKey(const Key('guest-join-table')));
  await tester.pumpAndSettle();
}
