import { Prisma } from '@prisma/client';
import {
  PricingDiscountInput,
  PricingInput,
  PricingLineInput,
  PricingResult,
  PricingTaxClass,
  priceOrder,
} from '../../common/pricing/pricing.engine';
import { PricingError } from '../../common/pricing/pricing.errors';
import { apiError } from '../../common/filters/api-error';

export const ZERO = new Prisma.Decimal(0);
export const D = (v: Prisma.Decimal | string | number) => new Prisma.Decimal(v);

/** Statuses in which an order can take items, be sent, billed and edited. */
export const EDITABLE_STATUSES = ['OPEN', 'SENT', 'BILLED', 'PENDING'];
/** Statuses in which an order can take payments. */
export const PAYABLE_STATUSES = ['OPEN', 'SENT', 'BILLED', 'PENDING', 'PARTIALLY_PAID'];
/** Statuses that still count as "open" on the floor and in day-close. */
export const OPEN_STATUSES = ['OPEN', 'SENT', 'BILLED'];

/** Tax rules frozen onto each order line when it is added, so later tax edits never change a bill. */
export interface TaxSnapshot {
  taxClassId: string | null;
  code: string;
  name: string;
  rate: string;
  inclusive: boolean;
  isLiquor: boolean;
  components: { name: string; rate: number }[];
}

/** Shape stored in OrderItem.taxBreakdown. */
export interface StoredLineTax {
  snapshot: TaxSnapshot;
  components: { name: string; rate: string; amount: string }[];
}

export interface TaxClassRow {
  id: string;
  code: string;
  name: string;
  rate: Prisma.Decimal;
  components: unknown;
  inclusive: boolean;
  isLiquor: boolean;
}

export function money(v: Prisma.Decimal | string | number | null | undefined): string {
  return D(v ?? 0).toFixed(2);
}

export function snapshotFromClass(tc: TaxClassRow): TaxSnapshot {
  return {
    taxClassId: tc.id,
    code: tc.code,
    name: tc.name,
    rate: D(tc.rate).toFixed(2),
    inclusive: tc.inclusive,
    isLiquor: tc.isLiquor,
    components: (tc.components as { name: string; rate: number }[]) ?? [],
  };
}

/** Legacy products (no tax class) are taxed at their own taxPercentage or the global rate, as in Phase 1. */
export function legacySnapshot(rate: Prisma.Decimal): TaxSnapshot {
  return {
    taxClassId: null,
    code: 'LEGACY',
    name: 'Tax',
    rate: D(rate).toFixed(2),
    inclusive: false,
    isLiquor: false,
    components: [{ name: 'TAX', rate: D(rate).toNumber() }],
  };
}

export function toPricingTaxClass(s: TaxSnapshot): PricingTaxClass {
  return {
    id: s.taxClassId ?? s.code,
    rate: D(s.rate),
    components: s.components,
    inclusive: s.inclusive,
    isLiquor: s.isLiquor,
  };
}

export function readStoredTax(json: unknown): StoredLineTax {
  const v = json as Partial<StoredLineTax> | null | undefined;
  if (v && v.snapshot) return { snapshot: v.snapshot, components: v.components ?? [] };
  return { snapshot: legacySnapshot(ZERO), components: [] };
}

export function serializeComponents(list: { name: string; rate: Prisma.Decimal | number; amount: Prisma.Decimal }[]) {
  return list.map((c) => ({ name: c.name, rate: money(c.rate), amount: money(c.amount) }));
}

/** Runs the pure engine and turns its PricingError into a 400 with the engine's code. */
export function runPricing(input: PricingInput): PricingResult {
  try {
    return priceOrder(input);
  } catch (e) {
    if (e instanceof PricingError) {
      throw apiError(400, e.code, e.message);
    }
    throw e;
  }
}

/**
 * Line input for an order line that is already priced. Its stored unit price is final
 * (markup and happy hour were applied when it was added), so re-pricing must not apply them again.
 */
export function frozenLineInput(item: {
  id: string;
  price: Prisma.Decimal;
  quantity: number;
  status: string;
  taxBreakdown: unknown;
}): PricingLineInput {
  return {
    id: item.id,
    baseUnitPrice: D(item.price),
    modifiersDelta: ZERO,
    quantity: item.quantity,
    taxClass: toPricingTaxClass(readStoredTax(item.taxBreakdown).snapshot),
    areaMarkupPercent: ZERO,
    happyHourPercent: null,
    voided: item.status === 'VOIDED',
  };
}

export interface DiscountRow {
  id: string;
  type: 'PERCENT' | 'FLAT';
  value: Prisma.Decimal;
  itemIds: string[];
}

/**
 * Discount inputs for the engine. Item-level discounts keep only the item ids that are still live
 * (not voided, still on the order); a discount left with no live items is dropped (amount 0).
 * Returns the engine input and, aligned by index, the discount row id each input came from.
 */
export function pricingDiscounts(rows: DiscountRow[], liveItemIds: Set<string>) {
  const inputs: PricingDiscountInput[] = [];
  const rowIds: string[] = [];
  for (const r of rows) {
    if (r.itemIds.length === 0) {
      inputs.push({ type: r.type, value: D(r.value), itemIds: [] });
      rowIds.push(r.id);
      continue;
    }
    const ids = r.itemIds.filter((id) => liveItemIds.has(id));
    if (ids.length === 0) continue;
    inputs.push({ type: r.type, value: D(r.value), itemIds: ids });
    rowIds.push(r.id);
  }
  return { inputs, rowIds };
}

/**
 * Per-discount amounts. The engine only reports the total discount, so the amount of discount k is
 * total(first k) minus total(first k-1). The amounts add up to the engine's discountTotal.
 */
export function discountAmounts(input: PricingInput): Prisma.Decimal[] {
  const out: Prisma.Decimal[] = [];
  let prev = ZERO;
  for (let k = 1; k <= input.discounts.length; k++) {
    const r = runPricing({ ...input, discounts: input.discounts.slice(0, k) });
    out.push(D(r.discountTotal).sub(prev));
    prev = D(r.discountTotal);
  }
  return out;
}

/** Percent-equivalent of a discount, used for the LIMITED check on sales.discount.give. */
export function percentEquivalent(type: 'PERCENT' | 'FLAT', value: Prisma.Decimal, discountableBase: Prisma.Decimal): Prisma.Decimal {
  if (type === 'PERCENT') return D(value);
  if (D(discountableBase).isZero()) return D(100);
  return D(value).div(discountableBase).mul(100);
}

export function serviceChargeFor(orderType: string, settings: { serviceChargePercent: Prisma.Decimal; serviceChargeTypes: string[] }) {
  return settings.serviceChargeTypes.includes(orderType) ? D(settings.serviceChargePercent) : ZERO;
}
