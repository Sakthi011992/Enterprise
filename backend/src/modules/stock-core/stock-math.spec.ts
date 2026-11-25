import { Prisma } from '@prisma/client';
import { formatQty, movementValue, nextDocNumber, recipeQty, toBase, varianceRow, weightedAverage } from './stock-math';

const d = (v: string | number) => new Prisma.Decimal(v);

describe('formatQty (PLAN.md 1.1)', () => {
  it('shows packs and the remainder for bottle items', () => {
    expect(formatQty(8410, 'ML', 750, 'btl')).toBe('11 btl + 160 ml');
    expect(formatQty(8 * 750 + 410, 'ML', 750, 'btl')).toBe('8 btl + 410 ml');
  });

  it('drops a zero part', () => {
    expect(formatQty(2250, 'ML', 750, 'btl')).toBe('3 btl');
    expect(formatQty(410, 'ML', 750, 'btl')).toBe('410 ml');
  });

  it('shows 0 in the base unit when empty', () => {
    expect(formatQty(0, 'ML', 750, 'btl')).toBe('0 ml');
  });

  it('shows weighed items in grams without converting to kilograms', () => {
    expect(formatQty(1200, 'G', 1, 'pc')).toBe('1200 g');
    expect(formatQty(600, 'G', 1000, 'kg pack')).toBe('600 g');
  });

  it('shows piece counts with up to 3 decimals trimmed', () => {
    expect(formatQty(12, 'PC', 1, 'pc')).toBe('12 pc');
    expect(formatQty(1.5, 'PC', 1, 'pc')).toBe('1.5 pc');
    expect(formatQty(1.2345, 'PC', 1, 'pc')).toBe('1.235 pc');
  });

  it('puts one leading minus sign on the whole string for negatives', () => {
    expect(formatQty(-8410, 'ML', 750, 'btl')).toBe('−11 btl + 160 ml');
    expect(formatQty(-120, 'ML', 750, 'btl')).toBe('−120 ml');
    expect(formatQty(-5, 'PC', 1, 'pc')).toBe('−5 pc');
  });

  it('accepts Decimal and string input', () => {
    expect(formatQty(d('9000.000'), 'ML', d('750.000'), 'btl')).toBe('12 btl');
    expect(formatQty('410.000', 'ML', '750', 'btl')).toBe('410 ml');
  });
});

describe('weightedAverage (PLAN.md 1.2)', () => {
  it('takes the receipt cost when on hand is zero or less', () => {
    expect(weightedAverage(0, 4.16, 9000, 1.4667).toString()).toBe('1.4667');
    expect(weightedAverage(-50, 4.16, 9000, 1.4667).toString()).toBe('1.4667');
  });

  it('blends the old average with the receipt by quantity', () => {
    // (1000 × 4.16 + 1000 × 2) / 2000 = 3.08
    expect(weightedAverage(1000, 4.16, 1000, 2).toString()).toBe('3.08');
  });

  it('rounds to 6 dp', () => {
    // (2 × 1 + 1 × 2) / 3 = 1.333333...
    expect(weightedAverage(2, 1, 1, 2).toString()).toBe('1.333333');
  });
});

describe('movementValue, recipeQty, toBase', () => {
  it('values a movement to 2 dp', () => {
    expect(movementValue(d('-60'), d('4.16')).toString()).toBe('-249.6');
    expect(movementValue(d('3'), d('1.005')).toString()).toBe('3.02');
  });

  it('applies wastage and the order quantity with 3 dp', () => {
    // 30 ml with 2% wastage, two drinks
    expect(recipeQty(30, 2, 2).toString()).toBe('61.2');
    // 60 ml, 2%, one drink
    expect(recipeQty(60, 2, 1).toString()).toBe('61.2');
    expect(recipeQty(1, 0, 3).toString()).toBe('3');
  });

  it('converts purchase units to base units', () => {
    expect(toBase(10, 650).toString()).toBe('6500');
    expect(toBase(1.5, 9000).toString()).toBe('13500');
  });
});

describe('varianceRow (PLAN.md 1.3)', () => {
  it('computes expected and the count adjustment from the movements', () => {
    const row = varianceRow(
      [
        { type: 'RECEIPT', qty: 9000, unitCost: 1.4667 },
        { type: 'TRANSFER_IN', qty: 750, unitCost: 4.16 },
        { type: 'TRANSFER_OUT', qty: -300, unitCost: 4.16 },
        { type: 'SALE', qty: -2000, unitCost: 4.16 },
        { type: 'SALE_REVERSAL', qty: 60, unitCost: 4.16 },
        { type: 'WASTAGE', qty: -60, unitCost: 4.16 },
        { type: 'COUNT_ADJUST', qty: -100, unitCost: 4.16 },
      ],
      5000,
    );
    expect(row.opening.toString()).toBe('5000');
    expect(row.received.toString()).toBe('9000');
    expect(row.transfersIn.toString()).toBe('750');
    expect(row.transfersOut.toString()).toBe('300');
    expect(row.sold.toString()).toBe('1940'); // 2000 sold less 60 reversed
    expect(row.wastage.toString()).toBe('60');
    // 5000 + 9000 + 750 − 300 − 1940 − 60 = 12450
    expect(row.expected.toString()).toBe('12450');
    expect(row.countAdjust.toString()).toBe('-100');
    expect(row.counted!.toString()).toBe('12350');
    expect(row.variance.toString()).toBe('-100');
    expect(row.varianceValue.toString()).toBe('-416');
  });

  it('has no counted value when no count was posted', () => {
    const row = varianceRow([{ type: 'SALE', qty: -10, unitCost: 1 }], 100);
    expect(row.counted).toBeNull();
    expect(row.expected.toString()).toBe('90');
    expect(row.variance.toString()).toBe('0');
    expect(row.varianceValue.toString()).toBe('0');
  });
});

describe('nextDocNumber', () => {
  it('pads to four digits at least', () => {
    expect(nextDocNumber('PO', 318)).toBe('PO-0318');
    expect(nextDocNumber('GRN', 91)).toBe('GRN-0091');
    expect(nextDocNumber('DN', 12345)).toBe('DN-12345');
  });
});
