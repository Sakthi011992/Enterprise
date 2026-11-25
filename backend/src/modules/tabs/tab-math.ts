import { Prisma } from '@prisma/client';

type Num = Prisma.Decimal | string | number;

const D = (v: Num) => new Prisma.Decimal(v);
const ZERO = new Prisma.Decimal(0);

/** spent ÷ limit as a percentage, one decimal place (a zero limit reads as 0). */
export function percentUsed(spent: Num, limit: Num): Prisma.Decimal {
  const l = D(limit);
  if (l.isZero()) return ZERO;
  return D(spent).mul(100).div(l).toDecimalPlaces(1, Prisma.Decimal.ROUND_HALF_UP);
}

/** True once spent reaches warnAtPercent of the limit (spent × 100 ≥ limit × warn). */
export function isNearLimit(spent: Num, limit: Num, warnAtPercent: number): boolean {
  return D(spent).mul(100).greaterThanOrEqualTo(D(limit).mul(warnAtPercent));
}

/** Whole-number percentage used for warning text (rounded down, so 94.9 reads as 94). */
export function wholePercent(spent: Num, limit: Num): number {
  const l = D(limit);
  if (l.isZero()) return 0;
  return D(spent).mul(100).div(l).toDecimalPlaces(0, Prisma.Decimal.ROUND_DOWN).toNumber();
}

/**
 * Cash deposit settlement. The deposit covers the bill up to the amount held. Whatever is left
 * over goes back to the guest.
 */
export function depositSplit(amountHeld: Num, grandTotal: Num): { applied: Prisma.Decimal; toReturn: Prisma.Decimal } {
  const held = D(amountHeld).isNegative() ? ZERO : D(amountHeld);
  const total = D(grandTotal).isNegative() ? ZERO : D(grandTotal);
  const applied = held.lessThan(total) ? held : total;
  const left = held.sub(applied);
  return { applied, toReturn: left.isNegative() ? ZERO : left };
}

/** Tab number: "T-" and at least two digits, e.g. T-07. */
export function tabNumber(seq: number): string {
  return `T-${String(seq).padStart(2, '0')}`;
}

export interface TabSecurityInput {
  ageChecked: boolean;
  security: 'CARD_PREAUTH' | 'CASH_DEPOSIT' | 'HOUSE_ACCOUNT' | 'NONE';
  cardLast4?: string;
  amountHeld?: number;
  houseAccount?: string;
}

/**
 * The checks made before a tab opens, in the order the plan lists them. Returns the error code, or null
 * when the tab may open.
 */
export function tabSecurityError(input: TabSecurityInput): 'AGE_CHECK_REQUIRED' | 'CARD_LAST4_REQUIRED' | 'DEPOSIT_REQUIRED' | 'HOUSE_ACCOUNT_REQUIRED' | null {
  if (!input.ageChecked) return 'AGE_CHECK_REQUIRED';
  if (input.security === 'CARD_PREAUTH' && !/^\d{4}$/.test(input.cardLast4 ?? '')) return 'CARD_LAST4_REQUIRED';
  if (input.security === 'CASH_DEPOSIT' && !((input.amountHeld ?? 0) > 0)) return 'DEPOSIT_REQUIRED';
  if (input.security === 'HOUSE_ACCOUNT' && !(input.houseAccount ?? '').trim()) return 'HOUSE_ACCOUNT_REQUIRED';
  return null;
}

/** Amount a tab holds on the guest's behalf. Only card pre-auth and cash deposits hold money. */
export function heldFor(security: TabSecurityInput['security'], amount: number | undefined): Prisma.Decimal {
  if (security === 'CARD_PREAUTH' || security === 'CASH_DEPOSIT') return D(amount ?? 0);
  return ZERO;
}
