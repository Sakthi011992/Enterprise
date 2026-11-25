import { Prisma } from '@prisma/client';
import {
  GrnCalcLine,
  calculateGrn,
  debitNoteReason,
  lineStatus,
  purchaseOrderStatusAfterReceipt,
  suggestedPurchaseQty,
} from './procurement-math';

const D = (v: number | string) => new Prisma.Decimal(v);

/**
 * PLAN.md 1.7 design example. Lager 10 cs (1 case damaged, ₹950 a case), keg 4 received, invoiced 5 at ₹7,800,
 * stout 4 cs at ₹4,600. Invoice ₹66,900. Debit note ₹7,800 for the keg not received, wastage ₹950, payable ₹59,100.
 */
const lines = (): GrnCalcLine[] => [
  {
    name: 'Premium Lager 650 ml',
    hasPoLine: true,
    orderedQty: D(10),
    invoicedQty: D(10),
    receivedQty: D(10),
    damagedQty: D(1),
    rate: D(950),
    purchaseUnitQty: D(7800),
  },
  {
    name: 'Wheat beer keg 30 L',
    hasPoLine: true,
    orderedQty: D(4),
    invoicedQty: D(5),
    receivedQty: D(4),
    damagedQty: D(0),
    rate: D(7800),
    purchaseUnitQty: D(1),
  },
  {
    name: 'Stout 500 ml',
    hasPoLine: true,
    orderedQty: D(4),
    invoicedQty: D(4),
    receivedQty: D(4),
    damagedQty: D(0),
    rate: D(4600),
    purchaseUnitQty: D(12),
  },
];

describe('calculateGrn (PLAN.md 1.7 design example)', () => {
  it('computes the debit note, wastage, invoice and payable', () => {
    const calc = calculateGrn(lines(), null);
    expect(calc.invoiceValue.toFixed(2)).toBe('66900.00');
    expect(calc.debitNoteAmount.toFixed(2)).toBe('7800.00');
    expect(calc.damagedValue.toFixed(2)).toBe('950.00');
    expect(calc.payable.toFixed(2)).toBe('59100.00');
    expect(calc.receivedValue.toFixed(2)).toBe('59100.00');
  });

  it('marks the receipt as a mismatch because the keg was invoiced 5 against 4 ordered', () => {
    expect(calculateGrn(lines(), null).mismatch).toBe(true);
  });

  it('adds received minus damaged to stock: 13 cases and 4 kegs', () => {
    const calc = calculateGrn(lines(), null);
    expect(calc.stockAddedQty.map((q) => q.toFixed(3))).toEqual(['9.000', '4.000', '4.000']);
    expect(calc.stockAddedBase[0].toFixed(3)).toBe('70200.000');
  });

  it('lists the short line in the debit note reason', () => {
    const calc = calculateGrn(lines(), null);
    expect(debitNoteReason(calc.shortLines)).toBe('1 × Wheat beer keg 30 L invoiced, not received');
  });

  it('uses the entered invoice value when given and flags a difference over ₹1', () => {
    const calc = calculateGrn(
      [
        {
          name: 'Soda',
          hasPoLine: false,
          orderedQty: D(0),
          invoicedQty: D(2),
          receivedQty: D(2),
          damagedQty: D(0),
          rate: D(100),
          purchaseUnitQty: D(1),
        },
      ],
      D(250),
    );
    expect(calc.invoiceValue.toFixed(2)).toBe('250.00');
    expect(calc.mismatch).toBe(true);
  });

  it('does not compare lines without a PO line to the ordered quantity', () => {
    const calc = calculateGrn(
      [
        {
          name: 'Limes',
          hasPoLine: false,
          orderedQty: D(0),
          invoicedQty: D(3),
          receivedQty: D(3),
          damagedQty: D(0),
          rate: D(10),
          purchaseUnitQty: D(1),
        },
      ],
      null,
    );
    expect(calc.mismatch).toBe(false);
  });
});

describe('lineStatus', () => {
  const base: GrnCalcLine = {
    name: 'x',
    hasPoLine: true,
    orderedQty: D(4),
    invoicedQty: D(4),
    receivedQty: D(4),
    damagedQty: D(0),
    rate: D(1),
    purchaseUnitQty: D(1),
  };

  it('is OK when everything agrees', () => {
    expect(lineStatus(base)).toBe('OK');
  });

  it('is DAMAGED before any other state', () => {
    expect(lineStatus({ ...base, damagedQty: D(1), invoicedQty: D(5) })).toBe('DAMAGED');
  });

  it('is OVER_INVOICED when invoiced above received', () => {
    expect(lineStatus({ ...base, invoicedQty: D(5) })).toBe('OVER_INVOICED');
  });

  it('is SHORT when received is below the ordered quantity', () => {
    expect(lineStatus({ ...base, receivedQty: D(3), invoicedQty: D(3) })).toBe('SHORT');
  });
});

describe('suggestedPurchaseQty (reorder rounding)', () => {
  it('rounds up to whole purchase units', () => {
    // (18000 - 3000) / 9000 = 1.67, so 2 cases
    expect(suggestedPurchaseQty(D(18000), D(3000), D(9000)).toFixed(0)).toBe('2');
  });

  it('is at least one purchase unit', () => {
    // (1000 - 500) / 9000 = 0.06, so 1
    expect(suggestedPurchaseQty(D(1000), D(500), D(9000)).toFixed(0)).toBe('1');
  });

  it('takes a negative on hand into account', () => {
    // (6000 - -3000) / 9000 = 1.0 exactly, so 1
    expect(suggestedPurchaseQty(D(6000), D(-3000), D(9000)).toFixed(0)).toBe('1');
  });
});

describe('purchaseOrderStatusAfterReceipt', () => {
  it('is INVOICE_MISMATCH whenever the receipt mismatches', () => {
    expect(purchaseOrderStatusAfterReceipt([{ qty: D(4), receivedQty: D(4) }], true)).toBe('INVOICE_MISMATCH');
  });

  it('is RECEIVED when every line is received in full', () => {
    expect(purchaseOrderStatusAfterReceipt([{ qty: D(4), receivedQty: D(4) }], false)).toBe('RECEIVED');
  });

  it('is PARTLY_RECEIVED when a line is still outstanding', () => {
    expect(
      purchaseOrderStatusAfterReceipt(
        [
          { qty: D(4), receivedQty: D(4) },
          { qty: D(10), receivedQty: D(6) },
        ],
        false,
      ),
    ).toBe('PARTLY_RECEIVED');
  });
});
