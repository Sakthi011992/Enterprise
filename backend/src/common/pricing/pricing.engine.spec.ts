import { Prisma } from '@prisma/client';
import {
  PricingInput,
  PricingLineInput,
  PricingTaxClass,
  isWithinSchedule,
  priceOrder,
} from './pricing.engine';
import { PricingError } from './pricing.errors';
import { businessDateFor, toDateOnly } from './business-date';

const D = (v: string | number) => new Prisma.Decimal(v);
const fx = (v: Prisma.Decimal) => v.toFixed(2);

const GST5: PricingTaxClass = {
  id: 'gst5',
  rate: D(5),
  components: [{ name: 'CGST', rate: 2.5 }, { name: 'SGST', rate: 2.5 }],
  inclusive: false,
  isLiquor: false,
};
const GST5_INCLUSIVE: PricingTaxClass = { ...GST5, id: 'gst5-inc', inclusive: true };
const GST18_INCLUSIVE: PricingTaxClass = {
  id: 'gst18-inc',
  rate: D(18),
  components: [{ name: 'CGST', rate: 9 }, { name: 'SGST', rate: 9 }],
  inclusive: true,
  isLiquor: false,
};
const VAT20: PricingTaxClass = {
  id: 'vat20',
  rate: D(20),
  components: [{ name: 'VAT', rate: 20 }],
  inclusive: false,
  isLiquor: true,
};
const ZERO_RATE: PricingTaxClass = { id: 'zero', rate: D(0), components: [], inclusive: false, isLiquor: false };

function line(
  id: string,
  base: string | number,
  quantity: number,
  taxClass: PricingTaxClass,
  extra: Partial<PricingLineInput> = {},
): PricingLineInput {
  return {
    id,
    baseUnitPrice: D(base),
    modifiersDelta: D(0),
    quantity,
    taxClass,
    areaMarkupPercent: D(0),
    happyHourPercent: null,
    voided: false,
    ...extra,
  };
}

function order(lines: PricingLineInput[], extra: Partial<PricingInput> = {}): PricingInput {
  return {
    lines,
    discounts: [],
    serviceChargePercent: D(0),
    roundingMode: 'NONE',
    ...extra,
  };
}

function errorCodeOf(fn: () => unknown): string | undefined {
  try {
    fn();
  } catch (e) {
    return e instanceof PricingError ? e.code : 'OTHER';
  }
  return undefined;
}

describe('priceOrder: tax', () => {
  it('exclusive tax: gross is ex-tax, tax and total follow the rate', () => {
    const result = priceOrder(order([line('lager', 300, 2, VAT20)]));
    const [lager] = result.lines;
    expect(fx(lager.gross)).toBe('600.00');
    expect(fx(lager.tax)).toBe('120.00');
    expect(fx(lager.total)).toBe('720.00');
    expect(result.taxBreakdown).toEqual([
      expect.objectContaining({ name: 'VAT', rate: 20 }),
    ]);
    expect(fx(result.taxBreakdown[0].amount)).toBe('120.00');
  });

  it('inclusive tax: unit price includes tax, gross is stripped of it and total returns the unit price', () => {
    const result = priceOrder(order([line('x', 100, 1, GST5_INCLUSIVE)]));
    const [x] = result.lines;
    expect(fx(x.unitPrice)).toBe('100.00');
    expect(fx(x.gross)).toBe('95.24'); // 100 / 1.05 = 95.238… → 95.24
    expect(fx(x.tax)).toBe('4.76'); // 95.24 × 5%
    expect(fx(x.total)).toBe('100.00');
  });

  it('inclusive tax with an exact split and quantity 2', () => {
    const result = priceOrder(order([line('x', 118, 2, GST18_INCLUSIVE)]));
    const [x] = result.lines;
    expect(fx(x.gross)).toBe('200.00');
    expect(fx(x.tax)).toBe('36.00');
    expect(fx(x.total)).toBe('236.00');
  });

  it('splits tax across components and puts the rounding remainder on the last one', () => {
    const threeWay: PricingTaxClass = {
      id: 'three',
      rate: D(5),
      components: [{ name: 'A', rate: 1.5 }, { name: 'B', rate: 1.5 }, { name: 'C', rate: 2 }],
      inclusive: false,
      isLiquor: false,
    };
    const result = priceOrder(order([line('x', 33.33, 1, threeWay)]));
    const [x] = result.lines;
    expect(fx(x.tax)).toBe('1.67'); // 1.6665 → 1.67
    expect(x.taxBreakdown.map((t) => fx(t.amount))).toEqual(['0.50', '0.50', '0.67']);
    const sum = x.taxBreakdown.reduce((acc, t) => acc.add(t.amount), D(0));
    expect(fx(sum)).toBe(fx(x.tax));
  });

  it('throws when tax components do not sum to the rate', () => {
    const broken: PricingTaxClass = { ...GST5, id: 'broken', components: [{ name: 'CGST', rate: 2 }] };
    expect(errorCodeOf(() => priceOrder(order([line('x', 100, 1, broken)])))).toBe('TAX_COMPONENTS_MISMATCH');
  });
});

describe('priceOrder: price adjustments', () => {
  it('happy hour applies after area markup, each step rounded', () => {
    const result = priceOrder(
      order([line('mojito', 350, 1, VAT20, { happyHourPercent: D(30) })]),
    );
    const [mojito] = result.lines;
    expect(fx(mojito.unitPrice)).toBe('245.00');
    expect(fx(mojito.gross)).toBe('245.00');
    expect(fx(mojito.tax)).toBe('49.00');
  });

  it('area markup raises the unit price (Rooftop +10%)', () => {
    const result = priceOrder(order([line('lager', 300, 1, VAT20, { areaMarkupPercent: D(10) })]));
    expect(fx(result.lines[0].unitPrice)).toBe('330.00');
    expect(fx(result.lines[0].gross)).toBe('330.00');
  });

  it('modifier deltas are added to the base unit price before markup', () => {
    const result = priceOrder(order([line('malt', 500, 1, VAT20, { modifiersDelta: D(40) })]));
    expect(fx(result.lines[0].unitPrice)).toBe('540.00');
  });
});

describe('priceOrder: discounts', () => {
  it('whole-bill percent discount skips liquor lines', () => {
    const result = priceOrder(
      order(
        [line('lager', 300, 2, VAT20), line('wings', 350, 1, GST5)],
        { discounts: [{ type: 'PERCENT', value: D(20), itemIds: [] }] },
      ),
    );
    const lager = result.lines.find((l) => l.id === 'lager')!;
    const wings = result.lines.find((l) => l.id === 'wings')!;
    expect(fx(lager.discount)).toBe('0.00');
    expect(fx(wings.discount)).toBe('70.00');
    expect(fx(wings.net)).toBe('280.00');
    expect(fx(wings.tax)).toBe('14.00');
    expect(fx(result.discountTotal)).toBe('70.00');
    expect(fx(result.discountableBase)).toBe('350.00');
  });

  it('flat discount splits across lines, remainder goes to the largest line', () => {
    const result = priceOrder(
      order(
        [line('a', 100, 1, GST5), line('b', 100, 1, GST5), line('c', 100, 1, GST5)],
        { discounts: [{ type: 'FLAT', value: D(100), itemIds: [] }] },
      ),
    );
    const byId = (id: string) => result.lines.find((l) => l.id === id)!;
    expect(fx(byId('a').discount)).toBe('33.34'); // 33.333… rounded, plus the 0.01 remainder
    expect(fx(byId('b').discount)).toBe('33.33');
    expect(fx(byId('c').discount)).toBe('33.33');
    expect(fx(result.discountTotal)).toBe('100.00');
  });

  it('flat discount is capped at the eligible gross and never touches liquor', () => {
    const result = priceOrder(
      order(
        [line('lager', 300, 1, VAT20), line('wings', 350, 1, GST5)],
        { discounts: [{ type: 'FLAT', value: D(1000), itemIds: [] }] },
      ),
    );
    expect(fx(result.lines.find((l) => l.id === 'wings')!.net)).toBe('0.00');
    expect(fx(result.lines.find((l) => l.id === 'lager')!.discount)).toBe('0.00');
    expect(fx(result.discountTotal)).toBe('350.00');
  });

  it('discount naming a liquor line throws LIQUOR_DISCOUNT_NOT_ALLOWED', () => {
    const input = order(
      [line('lager', 300, 1, VAT20), line('wings', 350, 1, GST5)],
      { discounts: [{ type: 'PERCENT', value: D(10), itemIds: ['lager'] }] },
    );
    expect(errorCodeOf(() => priceOrder(input))).toBe('LIQUOR_DISCOUNT_NOT_ALLOWED');
  });

  it('percent above 100 is rejected', () => {
    const input = order([line('wings', 350, 1, GST5)], {
      discounts: [{ type: 'PERCENT', value: D(120), itemIds: [] }],
    });
    expect(errorCodeOf(() => priceOrder(input))).toBe('INVALID_PERCENT');
  });
});

describe('priceOrder: voids, service charge, rounding', () => {
  it('voided line is priced at zero and excluded from totals and the discount base', () => {
    const result = priceOrder(
      order(
        [line('wings', 350, 1, GST5), line('lager', 300, 2, VAT20, { voided: true })],
        { discounts: [{ type: 'PERCENT', value: D(10), itemIds: [] }] },
      ),
    );
    const lager = result.lines.find((l) => l.id === 'lager')!;
    expect(fx(lager.gross)).toBe('0.00');
    expect(fx(lager.total)).toBe('0.00');
    expect(fx(result.subtotal)).toBe('350.00');
    expect(fx(result.discountableBase)).toBe('350.00');
    expect(fx(result.discountTotal)).toBe('35.00');
  });

  it('service charge is a percent of the net subtotal and is not taxed', () => {
    const result = priceOrder(
      order([line('wings', 350, 1, GST5)], { serviceChargePercent: D(5) }),
    );
    expect(fx(result.serviceCharge)).toBe('17.50');
    expect(fx(result.taxTotal)).toBe('17.50');
    expect(fx(result.grandTotal)).toBe('385.00');
  });

  it('NEAREST_1 rounds half-up to whole rupees and reports the round-off', () => {
    const down = priceOrder(order([line('food', 1000.4, 1, ZERO_RATE)], { roundingMode: 'NEAREST_1' }));
    expect(fx(down.grandTotal)).toBe('1000.00');
    expect(fx(down.roundOff)).toBe('-0.40');

    const half = priceOrder(order([line('food', 1000.5, 1, ZERO_RATE)], { roundingMode: 'NEAREST_1' }));
    expect(fx(half.grandTotal)).toBe('1001.00');
    expect(fx(half.roundOff)).toBe('0.50');
  });

  it('NONE leaves the total at two decimals with no round-off', () => {
    const result = priceOrder(order([line('food', 1000.4, 1, ZERO_RATE)], { roundingMode: 'NONE' }));
    expect(fx(result.grandTotal)).toBe('1000.40');
    expect(fx(result.roundOff)).toBe('0.00');
  });

  it('rejects a non-positive quantity', () => {
    expect(errorCodeOf(() => priceOrder(order([line('x', 100, 0, GST5)])))).toBe('INVALID_QUANTITY');
  });
});

describe('priceOrder: POS board ticket (exit test)', () => {
  // Lager 2 × ₹300 (BOT), wings ₹350 (KOT), mojito ₹350 with happy hour 30%, 60 ml single malt ₹500
  // with soda +₹40. Service 5% (dine-in). GST 5% food/soft, VAT 20% liquor. Rounding to whole rupees.
  const ticketLines = (): PricingLineInput[] => [
    line('lager', 300, 2, VAT20),
    line('wings', 350, 1, GST5),
    line('mojito', 350, 1, VAT20, { happyHourPercent: D(30) }),
    line('malt', 500, 1, VAT20, { modifiersDelta: D(40) }),
  ];

  it('prices the board ticket to the paisa', () => {
    const result = priceOrder(
      order(ticketLines(), { serviceChargePercent: D(5), roundingMode: 'NEAREST_1' }),
    );
    expect(fx(result.subtotal)).toBe('1735.00');
    expect(fx(result.serviceCharge)).toBe('86.75');
    expect(fx(result.taxTotal)).toBe('294.50');
    expect(fx(result.roundOff)).toBe('-0.25');
    expect(fx(result.grandTotal)).toBe('2116.00');

    const vat = result.taxBreakdown.find((t) => t.name === 'VAT')!;
    const cgst = result.taxBreakdown.find((t) => t.name === 'CGST')!;
    const sgst = result.taxBreakdown.find((t) => t.name === 'SGST')!;
    expect(fx(vat.amount)).toBe('277.00');
    expect(fx(cgst.amount)).toBe('8.75');
    expect(fx(sgst.amount)).toBe('8.75');
  });

  it('is internally consistent: lines + service + round-off = grand total', () => {
    const result = priceOrder(
      order(ticketLines(), { serviceChargePercent: D(5), roundingMode: 'NEAREST_1' }),
    );
    const sumLines = result.lines.reduce((acc, l) => acc.add(l.total), D(0));
    expect(fx(sumLines)).toBe('2029.50');
    expect(fx(sumLines.add(result.serviceCharge).add(result.roundOff))).toBe(fx(result.grandTotal));
    expect(fx(result.netSubtotal.add(result.taxTotal))).toBe(fx(sumLines));
  });

  it('with a 20% whole-bill discount only the wings take it, and the totals still agree', () => {
    const result = priceOrder(
      order(ticketLines(), {
        discounts: [{ type: 'PERCENT', value: D(20), itemIds: [] }],
        serviceChargePercent: D(5),
        roundingMode: 'NEAREST_1',
      }),
    );
    expect(fx(result.discountTotal)).toBe('70.00');
    expect(fx(result.netSubtotal)).toBe('1665.00');
    expect(fx(result.taxTotal)).toBe('291.00');
    expect(fx(result.serviceCharge)).toBe('83.25');
    expect(fx(result.grandTotal)).toBe('2039.00');
    const sumLines = result.lines.reduce((acc, l) => acc.add(l.total), D(0));
    expect(fx(sumLines.add(result.serviceCharge).add(result.roundOff))).toBe(fx(result.grandTotal));
  });
});

describe('isWithinSchedule', () => {
  const KOLKATA = 'Asia/Kolkata'; // UTC+05:30
  const WEDNESDAY = 3; // 2026-11-25 is a Wednesday

  it('handles a window that crosses midnight (22:00 to 02:00) with the weekday of the window start', () => {
    const days = [WEDNESDAY];
    // 22:30 IST Wednesday: inside, evening part of Wednesday.
    expect(isWithinSchedule(new Date('2026-11-25T17:00:00Z'), KOLKATA, days, '22:00', '02:00')).toBe(true);
    // 01:30 IST Thursday: after-midnight part of Wednesday's window.
    expect(isWithinSchedule(new Date('2026-11-25T20:00:00Z'), KOLKATA, days, '22:00', '02:00')).toBe(true);
    // 01:30 IST Friday: after-midnight part of Thursday, which is not in the days list.
    expect(isWithinSchedule(new Date('2026-11-26T20:00:00Z'), KOLKATA, days, '22:00', '02:00')).toBe(false);
    // 02:30 IST Thursday: past the end.
    expect(isWithinSchedule(new Date('2026-11-25T21:00:00Z'), KOLKATA, days, '22:00', '02:00')).toBe(false);
  });

  it('same-day window: start inclusive, end exclusive', () => {
    const all = [0, 1, 2, 3, 4, 5, 6];
    // 18:30 IST
    expect(isWithinSchedule(new Date('2026-11-25T13:00:00Z'), KOLKATA, all, '17:00', '20:00')).toBe(true);
    // 20:00 IST exactly
    expect(isWithinSchedule(new Date('2026-11-25T14:30:00Z'), KOLKATA, all, '17:00', '20:00')).toBe(false);
  });

  it('checks the day list and treats null times as all day', () => {
    const now = new Date('2026-11-25T13:00:00Z'); // Wednesday
    expect(isWithinSchedule(now, KOLKATA, [0], null, null)).toBe(false);
    expect(isWithinSchedule(now, KOLKATA, [3], null, null)).toBe(true);
  });

  it('equal start and end never matches', () => {
    expect(isWithinSchedule(new Date('2026-11-25T13:00:00Z'), KOLKATA, [3], '17:00', '17:00')).toBe(false);
  });

  it('rejects a malformed time', () => {
    expect(errorCodeOf(() => isWithinSchedule(new Date(), KOLKATA, [3], '5pm', '20:00'))).toBe('INVALID_TIME');
  });
});

describe('business date', () => {
  it('uses the local date, shifted back before the day start', () => {
    const at0130Ist = new Date('2026-11-25T20:00:00Z'); // 01:30 on 2026-11-26 in Kolkata
    expect(businessDateFor(at0130Ist, 'Asia/Kolkata', '00:00')).toBe('2026-11-26');
    expect(businessDateFor(at0130Ist, 'Asia/Kolkata', '04:00')).toBe('2026-11-25');
  });

  it('toDateOnly gives UTC midnight', () => {
    expect(toDateOnly('2026-11-25').toISOString()).toBe('2026-11-25T00:00:00.000Z');
  });
});
