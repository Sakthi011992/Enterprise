import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/ui/ui.dart';

import 'test_harness.dart';

void main() {
  testWidgets('calls onCompleted at the full length, then clears', (tester) async {
    final pins = <String>[];
    await tester.pumpWidget(testApp(
      child: PinPad(length: 4, onCompleted: (pin) => pins.add(pin)),
    ));

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(pins, ['1234']);

    // Cleared: the next four digits make a second, separate PIN.
    for (final digit in ['5', '6', '7', '8']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(pins, ['1234', '5678']);
  });

  testWidgets('backspace removes the last digit', (tester) async {
    final pins = <String>[];
    await tester.pumpWidget(testApp(
      child: PinPad(length: 4, onCompleted: (pin) => pins.add(pin)),
    ));

    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    for (final digit in ['2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(pins, ['1234']);
  });
}
