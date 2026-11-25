import 'package:flutter_test/flutter_test.dart';
import 'package:pos_billing/features/tax/data/tax_repository.dart';
import 'package:pos_billing/features/tax/domain/tax_rules.dart';

void main() {
  const gst5 = [
    TaxComponent(name: 'CGST', rate: 2.5),
    TaxComponent(name: 'SGST', rate: 2.5),
  ];

  test('CGST 2.5 and SGST 2.5 add up to a 5% rate', () {
    expect(componentsMatchRate(5, gst5), isTrue);
    expect(taxComponentsError(5, gst5), isNull);
  });

  test('components that miss the rate show the sums in the message', () {
    const short = [TaxComponent(name: 'CGST', rate: 2.5)];
    expect(componentsMatchRate(5, short), isFalse);
    expect(
      taxComponentsError(5, short),
      'Components add up to 2.50%, but the rate is 5.00%.',
    );
  });

  test('a rate with no components is rejected', () {
    expect(componentsMatchRate(5, const []), isFalse);
    expect(taxComponentsError(5, const []), isNotNull);
  });

  test('float drift does not break a valid split such as 0.1 + 0.2 against 0.3', () {
    const parts = [TaxComponent(name: 'A', rate: 0.1), TaxComponent(name: 'B', rate: 0.2)];
    expect(componentsMatchRate(0.3, parts), isTrue);
  });

  test('components must equal the rate, not just come close to it', () {
    const over = [
      TaxComponent(name: 'CGST', rate: 9),
      TaxComponent(name: 'SGST', rate: 9),
    ];
    expect(componentsMatchRate(18, over), isTrue);
    expect(componentsMatchRate(5, over), isFalse);
  });

  test('invoice preview uses the financial year that started in April', () {
    expect(invoicePreview('INV', DateTime(2026, 11, 25)), 'INV/2026-27/000001');
    expect(invoicePreview('INV', DateTime(2027, 2, 1)), 'INV/2026-27/000001');
    expect(invoicePreview('INV', DateTime(2027, 4, 1)), 'INV/2027-28/000001');
  });

  test('a blank invoice prefix falls back to INV', () {
    expect(invoicePreview('  ', DateTime(2026, 11, 25)), 'INV/2026-27/000001');
  });
}
