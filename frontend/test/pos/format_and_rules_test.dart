import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/features/pos/data/pos_models.dart';
import 'package:pos_billing/features/pos/presentation/dialogs/discount_dialog.dart';
import 'package:pos_billing/features/pos/presentation/modifier_rules.dart';
import 'package:pos_billing/features/pos/presentation/pos_format.dart';

PosModifierGroup modGroup({required String id, required int min, required int max, int options = 3}) {
  return PosModifierGroup(
    id: id,
    name: 'Group $id',
    minSelect: min,
    maxSelect: max,
    options: [
      for (var i = 1; i <= options; i++)
        PosModifierOption(id: '$id-o$i', name: 'Option $i', priceDelta: i == 3 ? '40.00' : '0.00'),
    ],
  );
}

void main() {
  group('rupee formatting', () {
    test('groups Indian style and drops zero paise', () {
      expect(formatRupees(2034), '₹2,034');
      expect(formatRupees(100000), '₹1,00,000');
      expect(formatRupees(1234567), '₹12,34,567');
      expect(formatRupees(999), '₹999');
    });

    test('shows paise when there are some, or when forced', () {
      expect(formatRupees(2034.5), '₹2,034.50');
      expect(formatRupees(30, alwaysPaise: true), '₹30.00');
      expect(formatWire('1326.00'), '₹1,326');
      expect(formatWire('1326.05'), '₹1,326.05');
    });

    test('negative amounts keep the sign before the symbol', () {
      expect(formatRupees(-24.5), '-₹24.50');
    });

    test('clock text is 12-hour with am or pm', () {
      expect(formatClock(DateTime(2026, 11, 25, 20)), '8:00 pm');
      expect(formatClock(DateTime(2026, 11, 25, 0, 5)), '12:05 am');
      expect(formatClock(DateTime(2026, 11, 25, 12)), '12:00 pm');
    });

    test('hex colours parse with or without alpha', () {
      expect(parseHexColor('#B45309')?.value, 0xFFB45309);
      expect(parseHexColor('nope'), isNull);
    });

    test('rupee input accepts commas and symbols and falls back to zero', () {
      expect(parseRupeeInput('₹1,000'), 1000);
      expect(parseRupeeInput(''), 0);
      expect(parseRupeeInput('abc'), 0);
    });
  });

  group('modifier min and max', () {
    test('a required single-choice group needs exactly one option', () {
      final groups = [modGroup(id: 'g', min: 1, max: 1)];
      expect(isModifierSelectionValid(groups, {}), isFalse);
      expect(modifierErrors(groups, {}).values.single, 'Pick one for Group g');
      expect(isModifierSelectionValid(groups, {'g-o1'}), isTrue);
      expect(modifierErrors(groups, {'g-o1', 'g-o2'}).values.single, 'Pick only one for Group g');
    });

    test('a multi-choice group enforces its min and max', () {
      final groups = [modGroup(id: 'm', min: 2, max: 2)];
      expect(modifierErrors(groups, {'m-o1'}).values.single, 'Pick at least 2 for Group m');
      expect(isModifierSelectionValid(groups, {'m-o1', 'm-o2'}), isTrue);
      expect(modifierErrors(groups, {'m-o1', 'm-o2', 'm-o3'}).values.single, 'Pick up to 2 for Group m');
    });

    test('an optional group with max 1 accepts none or one', () {
      final groups = [modGroup(id: 'o', min: 0, max: 1)];
      expect(isModifierSelectionValid(groups, {}), isTrue);
      expect(isModifierSelectionValid(groups, {'o-o2'}), isTrue);
    });

    test('a single-choice tap swaps the option in', () {
      final g = modGroup(id: 'g', min: 1, max: 1);
      expect(toggleModifierOption(g, {'g-o1'}, 'g-o2'), {'g-o2'});
      expect(toggleModifierOption(g, {'g-o2'}, 'g-o2'), isEmpty);
    });

    test('a multi-choice tap is ignored once the max is reached', () {
      final g = modGroup(id: 'm', min: 0, max: 2);
      expect(toggleModifierOption(g, {'m-o1'}, 'm-o2'), {'m-o1', 'm-o2'});
      expect(toggleModifierOption(g, {'m-o1', 'm-o2'}, 'm-o3'), {'m-o1', 'm-o2'});
      expect(toggleModifierOption(g, {'m-o1', 'm-o2'}, 'm-o1'), {'m-o2'});
    });

    test('price delta adds the chosen options only', () {
      final groups = [modGroup(id: 'a', min: 0, max: 1), modGroup(id: 'b', min: 0, max: 2)];
      expect(modifierDelta(groups, {'a-o3', 'b-o3'}), 80);
      expect(modifierDelta(groups, {'a-o1'}), 0);
    });
  });

  group('discount approval rules', () {
    test('APPROVE and EDIT never need a manager', () {
      expect(
        discountNeedsApproval(level: AccessLevel.edit, percentEquivalent: 90, limit: 0),
        isFalse,
      );
      expect(
        discountNeedsApproval(level: AccessLevel.approve, percentEquivalent: 50, limit: null),
        isFalse,
      );
    });

    test('LIMITED applies up to its limit and asks above it', () {
      expect(
        discountNeedsApproval(level: AccessLevel.limited, percentEquivalent: 10, limit: 10),
        isFalse,
      );
      expect(
        discountNeedsApproval(level: AccessLevel.limited, percentEquivalent: 20, limit: 10),
        isTrue,
      );
    });

    test('REQUEST always needs a manager', () {
      expect(
        discountNeedsApproval(level: AccessLevel.request, percentEquivalent: 1, limit: 100),
        isTrue,
      );
    });

    test('a flat amount converts to a percent of the base', () {
      expect(discountPercentEquivalent(percent: true, value: 20, base: 1000), 20);
      expect(discountPercentEquivalent(percent: false, value: 150, base: 1000), 15);
      expect(discountPercentEquivalent(percent: false, value: 150, base: 0), 0);
    });
  });
}
