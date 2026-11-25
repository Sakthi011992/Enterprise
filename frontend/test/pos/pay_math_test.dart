import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/pos/data/pos_models.dart';
import 'package:pos_billing/features/pos/presentation/pay_math.dart';

void main() {
  group('planTender', () {
    test('cash covers the due and gives change net of the tip', () {
      final plan = planTender(
        due: 1019,
        tipChoice: '5',
        cash: 1100,
        useUpi: false,
        useCard: false,
      );
      expect(plan.tip, 50.95);
      expect(plan.tipWire, '50.95');
      expect(plan.cashApplied, 1019);
      expect(plan.isCovered, isTrue);
      expect(plan.changeToGive, closeTo(30.05, 0.001));
    });

    test('cash below the due leaves the rest for UPI', () {
      final plan = planTender(
        due: 1019,
        tipChoice: 'none',
        cash: 500,
        useUpi: true,
        upi: 600,
        useCard: false,
      );
      expect(plan.cashApplied, 500);
      expect(plan.upiApplied, 519);
      expect(plan.isCovered, isTrue);
      expect(plan.changeToGive, 0);
    });

    test('card takes whatever cash and UPI leave', () {
      final plan = planTender(
        due: 1019,
        tipChoice: 'none',
        cash: 200,
        useUpi: true,
        upi: 300,
        useCard: true,
      );
      expect(plan.cashApplied, 200);
      expect(plan.upiApplied, 300);
      expect(plan.cardApplied, 519);
      expect(plan.applied, 1019);
    });

    test('without a card, a short tender is not covered', () {
      final plan = planTender(
        due: 1019,
        tipChoice: 'none',
        cash: 500,
        useUpi: false,
        useCard: false,
      );
      expect(plan.isCovered, isFalse);
      expect(plan.remaining, 519);
    });

    test('custom tip and 10% tip round to paise', () {
      expect(
        planTender(due: 333.33, tipChoice: '10', cash: 0, useUpi: false, useCard: true).tip,
        33.33,
      );
      expect(
        planTender(due: 100, tipChoice: 'custom', customTip: 25.5, cash: 0, useUpi: false, useCard: true).tip,
        25.5,
      );
    });

    test('a zero due is never covered', () {
      final plan = planTender(due: 0, tipChoice: 'none', cash: 0, useUpi: false, useCard: true);
      expect(plan.isCovered, isFalse);
    });
  });

  group('split shares display', () {
    SplitResult parse(List<Map<String, dynamic>> shares) =>
        SplitResult.fromJson({'shares': shares});

    test('parses shares and marks settled ones', () {
      final result = parse([
        {'label': 'Seat 1', 'seat': 1, 'itemIds': ['i1'], 'amount': '660.00', 'paid': '660.00', 'due': '0.00'},
        {'label': 'Seat 2', 'seat': 2, 'itemIds': ['i3', 'i2'], 'amount': '1019.00', 'paid': '0.00', 'due': '1019.00'},
      ]);
      expect(result.shares.length, 2);
      expect(result.shares.first.isSettled, isTrue);
      expect(result.shares.last.isSettled, isFalse);
      expect(result.shares.last.itemIds, ['i3', 'i2']);
      expect(result.shares.last.dueValue, 1019);
    });

    test('shares sum to the grand total', () {
      final result = parse([
        {'label': 'Share 1', 'amount': '663.00', 'paid': '0.00', 'due': '663.00'},
        {'label': 'Share 2', 'amount': '663.00', 'paid': '0.00', 'due': '663.00'},
        {'label': 'Share 3', 'amount': '663.00', 'paid': '0.00', 'due': '663.00'},
      ]);
      final sum = result.shares.fold<num>(0, (s, share) => s + share.amountValue);
      expect(sum, 1989);
    });

    test('a share with no seat has a null seat', () {
      final result = parse([
        {'label': 'Whole bill', 'amount': '1326.00', 'paid': '600.00', 'due': '726.00'},
      ]);
      expect(result.shares.single.seat, isNull);
      expect(result.shares.single.dueValue, 726);
    });
  });
}
