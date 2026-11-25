// Pure stock and costing helpers (PLAN.md 1.1 to 1.3). No Nest or Prisma client imports, so the
// specs run without a database. Money and quantities are Prisma.Decimal, never JS floats.
import { Prisma } from '@prisma/client';

type Num = Prisma.Decimal | number | string;

const D = (v: Num): Prisma.Decimal => new Prisma.Decimal(v);
const HALF_UP = Prisma.Decimal.ROUND_HALF_UP;

/** U+2212, the minus sign used for negative quantities in display strings. */
export const MINUS_SIGN = '−';

/** Movement types as stored (string literals of the Prisma enum). */
export type MovementKind =
  | 'OPENING'
  | 'RECEIPT'
  | 'SALE'
  | 'SALE_REVERSAL'
  | 'WASTAGE'
  | 'TRANSFER_OUT'
  | 'TRANSFER_IN'
  | 'COUNT_ADJUST';

/** Up to 3 decimals, trailing zeros and a trailing point removed. */
function trimmed(v: Prisma.Decimal): string {
  const s = v.toFixed(3);
  return s.includes('.') ? s.replace(/0+$/, '').replace(/\.$/, '') : s;
}

/**
 * Display rule of PLAN.md 1.1 (frontend `formatStockQty` must match).
 * packSize > 1: "8 btl + 410 ml", "3 btl", "410 ml", "0 ml".
 * packSize 1: "1200 g", "12 pc".
 * Negative quantities get a leading minus sign on the whole string.
 */
export function formatQty(qty: Num, unit: string, packSize: Num, packName: string): string {
  const q = D(qty);
  const sign = q.lt(0) ? MINUS_SIGN : '';
  const a = q.abs();
  const unitLower = unit.toLowerCase();
  const pack = D(packSize);

  if (pack.gt(1)) {
    const rem = a.mod(pack);
    const packs = a.minus(rem).div(pack);
    const parts: string[] = [];
    if (!packs.isZero()) parts.push(`${trimmed(packs)} ${packName}`);
    if (!rem.isZero()) parts.push(`${trimmed(rem)} ${unitLower}`);
    if (parts.length === 0) parts.push(`0 ${unitLower}`);
    return sign + parts.join(' + ');
  }
  return `${sign}${trimmed(a)} ${unitLower}`;
}

/**
 * PLAN.md 1.2. `onHand` is the total on hand of the item across the tenant's locations before the
 * receipt. When it is zero or less the average is the receipt's own unit cost.
 */
export function weightedAverage(onHand: Num, avgCost: Num, qty: Num, unitCost: Num): Prisma.Decimal {
  const h = D(onHand);
  const c = D(unitCost);
  if (h.lte(0)) return c.toDecimalPlaces(6, HALF_UP);
  const q = D(qty);
  return h
    .mul(D(avgCost))
    .plus(q.mul(c))
    .div(h.plus(q))
    .toDecimalPlaces(6, HALF_UP);
}

/** Value of a movement: qty × unitCost, rounded to 2 dp. */
export function movementValue(qty: Num, unitCost: Num): Prisma.Decimal {
  return D(qty).mul(D(unitCost)).toDecimalPlaces(2, HALF_UP);
}

/** Recipe deduction per PLAN.md 1.4 step 2: lineQty × (1 + wastage% / 100) × orderItem quantity, 3 dp. */
export function recipeQty(lineQty: Num, wastagePercent: Num, quantity: Num): Prisma.Decimal {
  return D(lineQty)
    .mul(D(1).plus(D(wastagePercent).div(100)))
    .mul(D(quantity))
    .toDecimalPlaces(3, HALF_UP);
}

/** Purchase units to base units, 3 dp (PLAN.md 1.1). */
export function toBase(purchaseQty: Num, purchaseUnitQty: Num): Prisma.Decimal {
  return D(purchaseQty).mul(D(purchaseUnitQty)).toDecimalPlaces(3, HALF_UP);
}

/** "PO-0318": the number is zero-padded to 4 digits at least. */
export function nextDocNumber(prefix: string, n: number): string {
  return `${prefix}-${String(n).padStart(4, '0')}`;
}

export interface VarianceMovement {
  type: MovementKind;
  qty: Num; // signed, base units
  unitCost: Num;
}

export interface VarianceMath {
  opening: Prisma.Decimal;
  received: Prisma.Decimal;
  transfersIn: Prisma.Decimal;
  transfersOut: Prisma.Decimal; // positive when stock left
  sold: Prisma.Decimal; // positive when stock was sold
  wastage: Prisma.Decimal; // positive when stock was wasted
  expected: Prisma.Decimal;
  countAdjust: Prisma.Decimal;
  counted: Prisma.Decimal | null; // null when no count was posted in the range
  variance: Prisma.Decimal; // = countAdjust (negative = unaccounted loss)
  varianceValue: Prisma.Decimal; // sum of COUNT_ADJUST qty × unitCost, 2 dp
}

/**
 * Variance per PLAN.md 1.3. `movements` are the movements of the item and location inside the
 * range; `openingQty` is the sum of all movements before the range.
 */
export function varianceRow(movements: VarianceMovement[], openingQty: Num): VarianceMath {
  let received = D(0);
  let transfersIn = D(0);
  let transfersOutSigned = D(0);
  let soldSigned = D(0);
  let wastageSigned = D(0);
  let countAdjust = D(0);
  let varianceValue = D(0);
  let hasCount = false;

  for (const m of movements) {
    const q = D(m.qty);
    switch (m.type) {
      case 'RECEIPT':
        received = received.plus(q);
        break;
      case 'TRANSFER_IN':
        transfersIn = transfersIn.plus(q);
        break;
      case 'TRANSFER_OUT':
        transfersOutSigned = transfersOutSigned.plus(q);
        break;
      case 'SALE':
      case 'SALE_REVERSAL':
        soldSigned = soldSigned.plus(q);
        break;
      case 'WASTAGE':
        wastageSigned = wastageSigned.plus(q);
        break;
      case 'COUNT_ADJUST':
        hasCount = true;
        countAdjust = countAdjust.plus(q);
        varianceValue = varianceValue.plus(q.mul(D(m.unitCost)));
        break;
      case 'OPENING':
        break; // the opening quantity is passed in separately
    }
  }

  const opening = D(openingQty);
  const transfersOut = transfersOutSigned.neg();
  const sold = soldSigned.neg();
  const wastage = wastageSigned.neg();
  const expected = opening.plus(received).plus(transfersIn).minus(transfersOut).minus(sold).minus(wastage);

  return {
    opening,
    received,
    transfersIn,
    transfersOut,
    sold,
    wastage,
    expected,
    countAdjust,
    counted: hasCount ? expected.plus(countAdjust) : null,
    variance: countAdjust,
    varianceValue: varianceValue.toDecimalPlaces(2, HALF_UP),
  };
}
