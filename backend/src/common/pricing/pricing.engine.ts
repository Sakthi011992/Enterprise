import { Prisma } from '@prisma/client';
import { round2 } from '../utils/money.util';
import { localParts } from './business-date';
import { PricingError } from './pricing.errors';

type Dec = Prisma.Decimal;

export interface PricingTaxClass {
  id: string;
  rate: Dec;
  components: { name: string; rate: number }[];
  inclusive: boolean;
  isLiquor: boolean;
}

export interface PricingLineInput {
  id: string; // order item id (or temp id)
  baseUnitPrice: Dec; // variant price, else product price, else combo price
  modifiersDelta: Dec; // sum of option priceDelta
  quantity: number;
  taxClass: PricingTaxClass;
  areaMarkupPercent: Dec; // 0 if none / not dine-in
  happyHourPercent: Dec | null;
  voided: boolean; // voided lines are priced at 0 and excluded
}

export interface PricingDiscountInput {
  type: 'PERCENT' | 'FLAT';
  value: Dec;
  itemIds: string[]; // empty = whole bill
}

export interface PricingInput {
  lines: PricingLineInput[];
  discounts: PricingDiscountInput[];
  serviceChargePercent: Dec; // 0 when the order type isn't in serviceChargeTypes
  roundingMode: 'NONE' | 'NEAREST_1';
}

export interface PricedLine {
  id: string;
  unitPrice: Dec;
  gross: Dec;
  discount: Dec;
  net: Dec;
  tax: Dec;
  taxBreakdown: { name: string; rate: number; amount: Dec }[];
  total: Dec;
}

export interface PricingResult {
  lines: PricedLine[];
  subtotal: Dec; // Σ gross (ex-tax)
  discountTotal: Dec;
  netSubtotal: Dec; // subtotal − discountTotal
  serviceCharge: Dec;
  taxTotal: Dec;
  taxBreakdown: { name: string; rate: number; amount: Dec }[]; // grouped by component name + rate
  roundOff: Dec;
  grandTotal: Dec;
  discountableBase: Dec; // Σ gross of non-liquor, non-voided lines before discounts
}

const D = (v: Dec | number | string): Dec => new Prisma.Decimal(v);
const ZERO = D(0);
const ONE = D(1);
const HUNDRED = D(100);

interface WorkLine {
  input: PricingLineInput;
  unitPrice: Dec;
  gross: Dec;
  discount: Dec;
  eligible: boolean; // non-liquor and not voided
}

/**
 * Prices a whole order. Pure: no Nest or Prisma calls. Every rounding step is round2 (half-up).
 * Rules: PLAN.md section 1.3.
 */
export function priceOrder(input: PricingInput): PricingResult {
  assertPercent(input.serviceChargePercent, 'serviceChargePercent', 0);

  const work = input.lines.map(toWorkLine);
  const byId = new Map<string, WorkLine>();
  for (const w of work) {
    if (byId.has(w.input.id)) throw new PricingError('DUPLICATE_LINE_ID', `Duplicate line ${w.input.id}`);
    byId.set(w.input.id, w);
  }

  for (const discount of input.discounts) applyDiscount(discount, work, byId);

  const lines = work.map(priceLine);

  const subtotal = sumOf(lines.map((l) => l.gross));
  const discountTotal = sumOf(lines.map((l) => l.discount));
  const netSubtotal = subtotal.sub(discountTotal);
  const taxTotal = sumOf(lines.map((l) => l.tax));
  const taxBreakdown = groupTaxBreakdown(lines);
  const serviceCharge = round2(netSubtotal.mul(input.serviceChargePercent).div(HUNDRED));

  const preRound = netSubtotal.add(serviceCharge).add(taxTotal);
  let grandTotal: Dec;
  let roundOff: Dec;
  if (input.roundingMode === 'NEAREST_1') {
    grandTotal = round2(preRound.toDecimalPlaces(0, Prisma.Decimal.ROUND_HALF_UP));
    roundOff = round2(grandTotal.sub(preRound));
  } else {
    grandTotal = round2(preRound);
    roundOff = ZERO;
  }

  const discountableBase = sumOf(work.filter((w) => w.eligible).map((w) => w.gross));

  return {
    lines,
    subtotal,
    discountTotal,
    netSubtotal,
    serviceCharge,
    taxTotal,
    taxBreakdown,
    roundOff,
    grandTotal,
    discountableBase,
  };
}

/**
 * True when `now` falls inside the schedule in the given IANA timezone.
 * `days`: 0 = Sunday. `start`/`end`: "HH:MM"; both null = all day. A window whose end is before its
 * start crosses midnight: the late-evening part belongs to today's weekday, the after-midnight part
 * to the previous weekday. start === end never matches.
 */
export function isWithinSchedule(
  now: Date,
  timeZone: string,
  days: number[],
  start: string | null,
  end: string | null,
): boolean {
  const p = localParts(now, timeZone);
  const weekday = weekdayOf(p.year, p.month, p.day);
  const minutes = p.hour * 60 + p.minute;

  if (start === null || end === null) return days.includes(weekday);

  const s = toMinutes(start);
  const e = toMinutes(end);
  if (s === e) return false;
  if (s < e) return days.includes(weekday) && minutes >= s && minutes < e;
  if (minutes >= s) return days.includes(weekday);
  if (minutes < e) return days.includes((weekday + 6) % 7);
  return false;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function toWorkLine(line: PricingLineInput): WorkLine {
  if (line.voided) {
    return { input: line, unitPrice: ZERO, gross: ZERO, discount: ZERO, eligible: false };
  }
  if (!Number.isInteger(line.quantity) || line.quantity < 1) {
    throw new PricingError('INVALID_QUANTITY', `Line ${line.id} quantity must be a positive integer`);
  }
  assertPercent(line.areaMarkupPercent, 'areaMarkupPercent', 0);

  const tc = line.taxClass;
  // 1. Unit price: base + modifiers, area markup, then happy hour. Each step rounds.
  let unit = round2(line.baseUnitPrice.add(line.modifiersDelta));
  unit = round2(unit.mul(ONE.add(line.areaMarkupPercent.div(HUNDRED))));
  if (line.happyHourPercent !== null) {
    assertPercent(line.happyHourPercent, 'happyHourPercent', 0, 100);
    unit = round2(unit.mul(ONE.sub(line.happyHourPercent.div(HUNDRED))));
  }

  // 2. Gross is always ex-tax. Inclusive classes strip the tax out of the unit price first.
  const gross = tc.inclusive
    ? round2(round2(unit.div(ONE.add(tc.rate.div(HUNDRED)))).mul(line.quantity))
    : round2(unit.mul(line.quantity));

  return { input: line, unitPrice: unit, gross, discount: ZERO, eligible: !tc.isLiquor };
}

/**
 * 3. Discounts apply only to eligible (non-liquor, non-voided) lines. Each discount is applied in
 * order against what is left of each line, so a line's total discount never exceeds its gross.
 */
function applyDiscount(d: PricingDiscountInput, work: WorkLine[], byId: Map<string, WorkLine>): void {
  if (d.value.isNegative()) throw new PricingError('INVALID_DISCOUNT', 'Discount value must not be negative');
  if (d.type === 'PERCENT') assertPercent(d.value, 'discount', 0, 100);

  for (const id of d.itemIds) {
    const target = byId.get(id);
    if (!target) throw new PricingError('UNKNOWN_DISCOUNT_ITEM', `Unknown item ${id} in discount`);
    if (target.input.taxClass.isLiquor) {
      throw new PricingError('LIQUOR_DISCOUNT_NOT_ALLOWED', `Line ${id} is liquor and cannot be discounted`);
    }
  }

  const targets = work.filter(
    (w) => w.eligible && (d.itemIds.length === 0 || d.itemIds.includes(w.input.id)),
  );
  const capacities = targets.map((w) => maxZero(w.gross.sub(w.discount)));
  const totalCapacity = sumOf(capacities);
  if (totalCapacity.lte(0)) return;

  if (d.type === 'PERCENT') {
    targets.forEach((w, i) => {
      const wanted = round2(w.gross.mul(d.value).div(HUNDRED));
      w.discount = w.discount.add(minDec(wanted, capacities[i]));
    });
    return;
  }

  // FLAT: split in proportion to what each line can still take; rounding remainder to the largest line.
  const amount = minDec(round2(d.value), totalCapacity);
  const shares = capacities.map((c) => round2(amount.mul(c).div(totalCapacity)));
  const remainder = amount.sub(sumOf(shares));
  if (!remainder.isZero()) {
    let largest = 0;
    capacities.forEach((c, i) => {
      if (c.gt(capacities[largest])) largest = i;
    });
    shares[largest] = shares[largest].add(remainder);
  }
  targets.forEach((w, i) => {
    w.discount = w.discount.add(shares[i]);
  });
}

/** 4. Net, tax and per-component tax (remainder on the last component so components sum to tax). */
function priceLine(w: WorkLine): PricedLine {
  const id = w.input.id;
  const tc = w.input.taxClass;
  const components = componentsFor(tc);

  if (w.input.voided) {
    return {
      id,
      unitPrice: ZERO,
      gross: ZERO,
      discount: ZERO,
      net: ZERO,
      tax: ZERO,
      taxBreakdown: components.map((c) => ({ name: c.name, rate: c.rate, amount: ZERO })),
      total: ZERO,
    };
  }

  const net = w.gross.sub(w.discount);
  const tax = round2(net.mul(tc.rate).div(HUNDRED));

  const amounts: Dec[] = [];
  let running = ZERO;
  components.forEach((c, i) => {
    if (i === components.length - 1) {
      amounts.push(tax.sub(running));
    } else {
      const amount = round2(net.mul(c.rateDec).div(HUNDRED));
      amounts.push(amount);
      running = running.add(amount);
    }
  });

  return {
    id,
    unitPrice: w.unitPrice,
    gross: w.gross,
    discount: w.discount,
    net,
    tax,
    taxBreakdown: components.map((c, i) => ({ name: c.name, rate: c.rate, amount: amounts[i] })),
    total: round2(net.add(tax)),
  };
}

function componentsFor(tc: PricingTaxClass): { name: string; rate: number; rateDec: Dec }[] {
  const list = tc.components.length > 0 ? tc.components : [{ name: 'TAX', rate: tc.rate.toNumber() }];
  const sum = list.reduce((acc, c) => acc.add(D(c.rate)), ZERO);
  if (!sum.eq(tc.rate)) {
    throw new PricingError('TAX_COMPONENTS_MISMATCH', `Tax class ${tc.id}: components do not sum to ${tc.rate.toString()}`);
  }
  return list.map((c) => ({ name: c.name, rate: c.rate, rateDec: D(c.rate) }));
}

function groupTaxBreakdown(lines: PricedLine[]): { name: string; rate: number; amount: Dec }[] {
  const groups = new Map<string, { name: string; rate: number; amount: Dec }>();
  for (const line of lines) {
    for (const t of line.taxBreakdown) {
      const key = `${t.name}@${t.rate}`;
      const existing = groups.get(key);
      if (existing) {
        existing.amount = existing.amount.add(t.amount);
      } else {
        groups.set(key, { name: t.name, rate: t.rate, amount: t.amount });
      }
    }
  }
  return [...groups.values()];
}

function assertPercent(value: Dec, field: string, min: number, max?: number): void {
  const belowMin = value.lt(min);
  const aboveMax = max !== undefined && value.gt(max);
  if (belowMin || aboveMax) {
    throw new PricingError('INVALID_PERCENT', `${field} must be >= ${min}${max !== undefined ? ` and <= ${max}` : ''}`);
  }
}

function toMinutes(value: string): number {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value);
  if (!m) throw new PricingError('INVALID_TIME', `Invalid time "${value}", expected HH:MM`);
  return Number(m[1]) * 60 + Number(m[2]);
}

function weekdayOf(year: number, month: number, day: number): number {
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

function sumOf(values: Dec[]): Dec {
  return values.reduce((acc, v) => acc.add(v), ZERO);
}

function maxZero(v: Dec): Dec {
  return v.isNegative() ? ZERO : v;
}

function minDec(a: Dec, b: Dec): Dec {
  return a.lt(b) ? a : b;
}
