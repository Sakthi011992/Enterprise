import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/procurement/data/procurement_models.dart';
import 'package:pos_billing/features/procurement/domain/grn_math.dart';

/// Fixture from the design example: Lager damaged 1 case, Keg over-invoiced,
/// Stout clean. Invoice total 66,900 = 10x950 + 5x7800 + 4x4600.
GrnView fixture() => GrnView.fromJson({
      'id': 'g1',
      'number': 'GRN-0007',
      'status': 'DRAFT',
      'poId': 'po1',
      'vendorInvoiceNo': 'INV-22',
      'invoiceValue': '66900.00',
      'payable': '59100.00',
      'mismatch': true,
      'lines': [
        {
          'id': 'l1',
          'stockItemId': 'lager',
          'name': 'Lager',
          'purchaseUnitName': 'Case of 12 bottles',
          'orderedQty': 10,
          'invoicedQty': 10,
          'receivedQty': 10,
          'damagedQty': 1,
          'rate': 950,
        },
        {
          'id': 'l2',
          'stockItemId': 'keg',
          'name': 'Keg',
          'purchaseUnitName': 'Keg',
          'orderedQty': 4,
          'invoicedQty': 5,
          'receivedQty': 4,
          'damagedQty': 0,
          'rate': 7800,
        },
        {
          'id': 'l3',
          'stockItemId': 'stout',
          'name': 'Stout',
          'purchaseUnitName': 'Case of 12 bottles',
          'orderedQty': 4,
          'invoicedQty': 4,
          'receivedQty': 4,
          'damagedQty': 0,
          'rate': 4600,
        },
      ],
    });

void main() {
  group('grnLineStatus', () {
    test('reports each line the way the server does, with the priority order', () {
      final lines = fixture().lines;
      expect(grnLineStatus(lines[0]), 'DAMAGED');
      expect(grnLineStatus(lines[1]), 'OVER_INVOICED');
      expect(grnLineStatus(lines[2]), 'OK');
    });

    test('over-invoiced beats damaged when both apply', () {
      final line = fixture().lines[0].copyWith(invoicedQty: 12);
      expect(grnLineStatus(line), 'OVER_INVOICED');
    });
  });

  group('grnTotals', () {
    test('sums stock, debit note, wastage and payable', () {
      final totals = grnTotals(fixture().lines, invoiceValue: 66900);

      expect(totals.stockByUnit, {'case': 13, 'keg': 4});
      expect(totals.debitNote, 7800);
      expect(totals.damagedValue, 950);
      expect(totals.invoiceValue, 66900);
      expect(totals.payable, 59100);
      expect(totals.mismatch, isTrue);
    });

    test('invoice value defaults to the invoiced lines when not given', () {
      final totals = grnTotals(fixture().lines);
      expect(totals.invoiceValue, 66900);
      expect(totals.payable, 59100);
    });

    test('a short delivery is a debit note, not wastage', () {
      final lines = [
        const GrnLine(
          stockItemId: 'stout',
          name: 'Stout',
          purchaseUnitName: 'Case of 12 bottles',
          orderedQty: 4,
          invoicedQty: 4,
          receivedQty: 3,
          damagedQty: 0,
          rate: 4600,
        ),
      ];
      final totals = grnTotals(lines);
      expect(totals.debitNote, 4600);
      expect(totals.damagedValue, 0);
      expect(totals.shortByUnit, ['case']);
    });
  });

  group('grnPreviewSentence', () {
    test('matches the design example exactly', () {
      final totals = grnTotals(fixture().lines, invoiceValue: 66900);
      expect(
        grnPreviewSentence(totals, locationName: 'Cellar'),
        'Posting creates: stock +13 cases +4 kegs in Cellar, a debit note of '
        '₹7,800 for the missing keg, and ₹950 wastage for the damaged case.',
      );
    });

    test('says nothing is created when every line is clean and complete', () {
      final lines = [
        const GrnLine(
          stockItemId: 'stout',
          name: 'Stout',
          purchaseUnitName: 'Case of 12 bottles',
          orderedQty: 0,
          invoicedQty: 0,
          receivedQty: 0,
          damagedQty: 0,
          rate: 0,
        ),
      ];
      final totals = grnTotals(lines);
      expect(
        grnPreviewSentence(totals, locationName: 'Cellar'),
        'Posting creates nothing to stock or credit yet.',
      );
    });
  });

  test('unitWord takes the lowercase first word of the purchase unit', () {
    expect(unitWord('Case of 12 bottles'), 'case');
    expect(unitWord('Keg'), 'keg');
    expect(unitWord('  '), 'unit');
  });
}
