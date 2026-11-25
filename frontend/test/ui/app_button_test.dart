import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/ui/ui.dart';

import 'test_harness.dart';

void main() {
  testWidgets('loading button shows a spinner and ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(testApp(
      child: AppButton(
        label: 'Saving…',
        variant: AppButtonVariant.primary,
        loading: true,
        onPressed: () => taps++,
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);

    await tester.tap(find.text('Saving…'));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('enabled button calls onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(testApp(
      child: AppButton(
        label: 'Save',
        variant: AppButtonVariant.primary,
        onPressed: () => taps++,
      ),
    ));

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('button height follows the density', (tester) async {
    await tester.pumpWidget(testApp(
      density: AppDensity.pos,
      child: AppButton(
        label: 'Pay',
        variant: AppButtonVariant.primary,
        onPressed: () {},
      ),
    ));
    expect(tester.getSize(find.byType(FilledButton)).height, 52);
  });
}
