import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/ui/ui.dart';

import 'test_harness.dart';

void main() {
  testWidgets('renders the label as text for every tone', (tester) async {
    await tester.pumpWidget(testApp(
      child: Wrap(
        children: [
          for (final tone in StatusTone.values)
            StatusBadge(label: 'Status ${tone.name}', tone: tone),
        ],
      ),
    ));

    for (final tone in StatusTone.values) {
      expect(find.text('Status ${tone.name}'), findsOneWidget);
    }
  });

  testWidgets('shows the word in dark mode too', (tester) async {
    await tester.pumpWidget(testApp(
      brightness: Brightness.dark,
      child: const StatusBadge(label: 'Paid', tone: StatusTone.success),
    ));
    expect(find.text('Paid'), findsOneWidget);
  });
}
