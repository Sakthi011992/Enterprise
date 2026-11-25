// Pure inventory rules (PLAN.md 1.7 Inventory and 1.3). No Prisma client calls, so the specs run without a database.
import { Prisma } from '@prisma/client';
import { round2 } from '../../common/utils/money.util';

export type StockRowStatus = 'OK' | 'BELOW_PAR' | 'VARIANCE' | 'EXPIRES' | 'NEGATIVE';

/** Wastage above this value needs a photo and notifies the purchase approvers (PLAN.md 1.6). */
export const WASTAGE_PHOTO_THRESHOLD = new Prisma.Decimal(2000);
/** A posted count line whose |variance value| reaches this amount flags the item as VARIANCE (PLAN.md 1.7). */
export const VARIANCE_FLAG_VALUE = new Prisma.Decimal(500);
/** A count line more than this share away from the expected quantity is an outlier (PLAN.md 1.7). */
export const OUTLIER_SHARE = new Prisma.Decimal('0.3');

export interface StatusFlags {
  negative: boolean;
  belowPar: boolean;
  variance: boolean;
  expiring: boolean;
  ok: boolean;
}

/** Highest-priority status wins: NEGATIVE, BELOW_PAR, VARIANCE, EXPIRES, then OK. */
export function statusFromFlags(f: Omit<StatusFlags, 'ok'>): StockRowStatus {
  if (f.negative) return 'NEGATIVE';
  if (f.belowPar) return 'BELOW_PAR';
  if (f.variance) return 'VARIANCE';
  if (f.expiring) return 'EXPIRES';
  return 'OK';
}

/** Outlier rule of PLAN.md 1.7: |counted − expected| > 30% of expected. A zero expectation is an outlier when anything was counted. */
export function countDifference(
  expected: Prisma.Decimal | null,
  counted: Prisma.Decimal | null,
): { differencePercent: string | null; outlier: boolean } {
  if (expected === null || counted === null) return { differencePercent: null, outlier: false };
  const diff = counted.minus(expected);
  if (expected.isZero()) return { differencePercent: null, outlier: !diff.isZero() };
  const percent = diff.div(expected.abs()).mul(100).toDecimalPlaces(1, Prisma.Decimal.ROUND_HALF_UP);
  return {
    differencePercent: percent.toFixed(1),
    outlier: diff.abs().gt(expected.abs().mul(OUTLIER_SHARE)),
  };
}

/** COUNT_ADJUST quantity for one counted line: counted − expected at submit (PLAN.md 1.7 stock count post). */
export function countAdjustment(expectedAtSubmit: Prisma.Decimal, counted: Prisma.Decimal): Prisma.Decimal {
  return counted.minus(expectedAtSubmit);
}

/** Wastage value: qty × average cost, 2 dp. */
export function wastageValue(qty: Prisma.Decimal, avgCost: Prisma.Decimal): Prisma.Decimal {
  return round2(qty.mul(avgCost));
}
