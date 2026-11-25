import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/inventory/data/stock_format.dart';

/// Same cases as the backend `formatQty` spec (PLAN 1.1). The minus sign is U+2212.
void main() {
  group('formatStockQty', () {
    test('packs plus open millilitres', () {
      expect(formatStockQty(6410, 'ML', 750, 'btl'), '8 btl + 410 ml');
    });

    test('whole packs drop the zero part', () {
      expect(formatStockQty(6000, 'ML', 750, 'btl'), '8 btl');
    });

    test('less than one pack shows only the open part', () {
      expect(formatStockQty(410, 'ML', 750, 'btl'), '410 ml');
    });

    test('zero shows the unit only', () {
      expect(formatStockQty(0, 'ML', 750, 'btl'), '0 ml');
    });

    test('negative quantities get one leading minus on the whole string', () {
      expect(formatStockQty(-410, 'ML', 750, 'btl'), '−410 ml');
      expect(formatStockQty(-6410, 'ML', 750, 'btl'), '−8 btl + 410 ml');
    });

    test('kegs of 30 L', () {
      expect(formatStockQty(30000, 'ML', 30000, 'keg'), '1 keg');
      expect(formatStockQty(42400, 'ML', 30000, 'keg'), '1 keg + 12400 ml');
    });

    test('pack size 1 shows the quantity with up to 3 decimals, trimmed', () {
      expect(formatStockQty(1200, 'G', 1, 'pc'), '1200 g');
      expect(formatStockQty(1.5, 'G', 1, 'pc'), '1.5 g');
      expect(formatStockQty(5, 'PC', 1, 'pc'), '5 pc');
      expect(formatStockQty(0.0004, 'G', 1, 'pc'), '0 g');
    });

    test('mixed packs for weighed packs', () {
      expect(formatStockQty(600, 'G', 1000, 'kg pack'), '600 g');
      expect(formatStockQty(2250, 'ML', 750, 'btl'), '3 btl');
    });
  });

  group('parseStockInput', () {
    test('bottles times pack size plus open millilitres', () {
      expect(parseStockInput(8, 410, 750), 6410);
      expect(parseStockInput(0, 250, 750), 250);
    });
  });
}
