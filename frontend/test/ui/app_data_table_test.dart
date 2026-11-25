import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/ui/ui.dart';

import 'test_harness.dart';

void main() {
  testWidgets('bulk bar appears when rows are selected', (tester) async {
    await tester.pumpWidget(testApp(child: const _SelectionHarness()));

    expect(find.text('1 selected'), findsNothing);

    // Checkbox 0 is the select-all in the header; 1 and 2 are the rows.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });
}

/// Holds the selection in state, the way a screen would.
class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness();

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AppDataTable<String>(
      columns: [
        AppColumn<String>(label: 'Name', cell: (row) => Text(row)),
      ],
      rows: const ['Alpha', 'Beta'],
      selected: _selected,
      onSelectionChanged: (s) => setState(() => _selected = s),
      bulkActions: [
        AppButton(label: 'Deactivate', onPressed: () {}),
      ],
    );
  }
}
