// Display and mapping helpers shared by the inventory and procurement views. Pure: no Prisma client calls.
import { Prisma, StockUnit } from '@prisma/client';
import { round2 } from '../../common/utils/money.util';
import { formatQty } from '../stock-core/stock-math';

export const ZERO = new Prisma.Decimal(0);
export const HALF_UP = Prisma.Decimal.ROUND_HALF_UP;

export interface UnitInfo {
  baseUnit: StockUnit;
  packSize: Prisma.Decimal;
  packName: string;
}

/** Stock quantities: strings with 3 dp (PLAN.md 1.7). */
export const qty3 = (d: Prisma.Decimal): string => d.toDecimalPlaces(3, HALF_UP).toFixed(3);
/** Money: strings with 2 dp. */
export const money2 = (d: Prisma.Decimal): string => round2(d).toFixed(2);
/** Unit costs: strings with 6 dp. */
export const cost6 = (d: Prisma.Decimal): string => d.toDecimalPlaces(6, HALF_UP).toFixed(6);

export const qtyDisplay = (d: Prisma.Decimal, unit: UnitInfo): string =>
  formatQty(d, unit.baseUnit, unit.packSize, unit.packName);

export const ymd = (d: Date): string => d.toISOString().slice(0, 10);

/** "₹3,120" with Indian digit grouping, computed on the decimal string (no floats). */
export function inr(d: Prisma.Decimal): string {
  const fixed = round2(d).toFixed(2);
  const negative = fixed.startsWith('-');
  const [intPart, frac] = fixed.replace('-', '').split('.');
  const grouped = indianGroup(intPart);
  const body = frac === '00' ? grouped : `${grouped}.${frac}`;
  return `${negative ? '−' : ''}₹${body}`;
}

function indianGroup(digits: string): string {
  if (digits.length <= 3) return digits;
  const head = digits.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',');
  return `${head},${digits.slice(-3)}`;
}

/** "₹3,120 / btl" for a stock item: the value of one pack, or of one base unit when there are no packs. */
export function unitCostDisplay(avgCost: Prisma.Decimal, item: UnitInfo): string {
  const perPack = item.packSize.gt(1);
  const price = perPack ? avgCost.mul(item.packSize) : avgCost;
  const unit = perPack ? item.packName : item.baseUnit.toLowerCase();
  return `${inr(price)} / ${unit}`;
}

export function userName(u: { displayName: string | null; username: string } | null | undefined): string | null {
  if (!u) return null;
  return u.displayName ?? u.username;
}

/** Level cells by stock item, then location: the shape every inventory view reads. */
export interface LevelCell {
  onHand: Prisma.Decimal;
  parLevel: Prisma.Decimal;
}
export type LevelIndex = Map<string, Map<string, LevelCell>>;

export function indexLevels(
  levels: { locationId: string; stockItemId: string; onHand: Prisma.Decimal; parLevel: Prisma.Decimal }[],
): LevelIndex {
  const index: LevelIndex = new Map();
  for (const lv of levels) {
    let byLocation = index.get(lv.stockItemId);
    if (!byLocation) {
      byLocation = new Map();
      index.set(lv.stockItemId, byLocation);
    }
    byLocation.set(lv.locationId, { onHand: lv.onHand, parLevel: lv.parLevel });
  }
  return index;
}
