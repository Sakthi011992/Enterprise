import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/personas/data/persona_models.dart';
import 'package:pos_billing/features/personas/presentation/permission_cell_editor.dart';
import 'package:pos_billing/features/personas/presentation/persona_changes_bar.dart';
import 'package:pos_billing/features/personas/presentation/persona_matrix.dart';

import '../ui/test_harness.dart';

const _discount = CatalogEntry(
  key: 'sales.discount.give',
  group: 'Sales',
  label: 'Give discount',
  limitUnit: 'percent',
  sortOrder: 1,
);

const _manager = Persona(
  id: 'p-manager',
  key: 'manager',
  name: 'Manager',
  homeRoute: '/dashboard',
  loginMethod: LoginMethod.password,
  isSystem: false,
  userCount: 2,
);

void main() {
  group('sanitizeLimitInput', () {
    test('keeps digits and a single decimal point', () {
      expect(sanitizeLimitInput('1a2.5.3'), '12.53');
      expect(sanitizeLimitInput('abc'), '');
    });

    test('caps a percent limit at 100', () {
      expect(sanitizeLimitInput('250', max: 100), '100');
      expect(sanitizeLimitInput('99', max: 100), '99');
    });

    test('leaves rupee limits open-ended', () {
      expect(sanitizeLimitInput('250000', max: null), '250000');
    });
  });

  testWidgets('cell editor clamps the limit field to digits and 100 percent', (tester) async {
    const current = PersonaGrant(key: 'sales.discount.give', level: AccessLevel.limited, limit: 10);
    await tester.pumpWidget(testApp(
      child: Builder(
        builder: (context) => AppButton(
          label: 'Open',
          onPressed: () => showPermissionCellEditor(context, entry: _discount, current: current),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '');

    await tester.enterText(field, '250');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '100');
  });

  testWidgets('read-only matrix does not open the cell editor', (tester) async {
    var edits = 0;
    const grant = PersonaGrant(key: 'sales.discount.give', level: AccessLevel.edit);

    Widget matrix({required bool readOnly}) => testApp(
          child: PersonaMatrix(
            personas: const [_manager],
            catalog: const [_discount],
            grantOf: (_, __) => grant,
            isChanged: (_, __) => false,
            selectedId: null,
            readOnly: readOnly,
            onSelectPersona: (_) {},
            onEditCell: (_, __) => edits++,
          ),
        );

    await tester.pumpWidget(matrix(readOnly: true));
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(edits, 0);

    await tester.pumpWidget(matrix(readOnly: false));
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(edits, 1);
  });

  testWidgets('read-only changes bar hides Save', (tester) async {
    Widget bar({required bool readOnly}) => testApp(
          child: PersonaChangesBar(
            changeCount: 2,
            affectedUsers: 3,
            readOnly: readOnly,
            saving: false,
            onCancel: () {},
            onSave: () {},
          ),
        );

    await tester.pumpWidget(bar(readOnly: true));
    expect(find.text('Save'), findsNothing);

    await tester.pumpWidget(bar(readOnly: false));
    expect(find.text('Save'), findsOneWidget);
    expect(
      find.textContaining('You changed 2 permissions. They apply to all 3 users'),
      findsOneWidget,
    );
  });
}
