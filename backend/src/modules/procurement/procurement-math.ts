// Pure procurement rules (PLAN.md 1.7 Procurement, GRN post rules). No Prisma client calls: the specs run without a database.
import { Prisma, PurchaseOrderStatus } from '@prisma/client';
import { round2 } from '../../common/utils/money.util';
import { toBase } from '../stock-core/stock-math';

const ZERO = new Prisma.Decimal(0);
const ONE = new Prisma.Decimal(1);
/** decimal.js rounding modes, spelled as numbers: ROUND_CEIL = 2, ROUND_FLOOR = 3. */
const ROUND_CEIL = 2;

/** Invoice value and total must agree within this amount (PLAN.md 1.7 mismatch rule). */
export const INVOICE_TOLERANCE = new Prisma.Decimal(1);

export type GrnLineStatus = 'OK' | 'SHORT' | 'OVER_INVOICED' | 'DAMAGED';

export interface GrnCalcLine {
  name: string;
  /** True when the line is linked to a PO line; only those lines are compared with the ordered quantity. */
  hasPoLine: boolean;
  orderedQty: Prisma.Decimal;
  invoicedQty: Prisma.Decimal;
  receivedQty: Prisma.Decimal;
  damagedQty: Prisma.Decimal;
  rate: Prisma.Decimal;
  purchaseUnitQty: Prisma.Decimal;
}

export interface GrnCalc {
  receivedValue: Prisma.Decimal;
  damagedValue: Prisma.Decimal;
  debitNoteAmount: Prisma.Decimal;
  invoicedValue: Prisma.Decimal;
  invoiceValue: Prisma.Decimal;
  payable: Prisma.Decimal;
  mismatch: boolean;
  lineStatus: GrnLineStatus[];
  /** Quantity added to stock per line, in purchase units: received minus damaged. */
  stockAddedQty: Prisma.Decimal[];
  /** Quantity added to stock in base units per line. */
  stockAddedBase: Prisma.Decimal[];
  shortLines: { index: number; name: string; qty: Prisma.Decimal; value: Prisma.Decimal }[];
  damagedLines: { index: number; name: string; qty: Prisma.Decimal; value: Prisma.Decimal }[];
}

/** Line status (PLAN.md 1.7 view): damaged first, then invoiced above received, then short of the order. */
export function lineStatus(l: GrnCalcLine): GrnLineStatus {
  if (l.damagedQty.gt(0)) return 'DAMAGED';
  if (l.invoicedQty.gt(l.receivedQty)) return 'OVER_INVOICED';
  if (l.hasPoLine && l.receivedQty.lt(l.orderedQty)) return 'SHORT';
  return 'OK';
}

/**
 * GRN totals and flags (PLAN.md 1.7 GRN post steps 2 to 3). `invoiceValueInput` is the invoice value
 * as entered or stored; null uses the sum of invoiced quantity × rate.
 */
export function calculateGrn(lines: GrnCalcLine[], invoiceValueInput: Prisma.Decimal | null): GrnCalc {
  let receivedValue = ZERO;
  let damagedValue = ZERO;
  let debitNoteAmount = ZERO;
  let invoicedValue = ZERO;
  let mismatch = false;
  const shortLines: GrnCalc['shortLines'] = [];
  const damagedLines: GrnCalc['damagedLines'] = [];
  const stockAddedQty: Prisma.Decimal[] = [];
  const stockAddedBase: Prisma.Decimal[] = [];
  const statuses: GrnLineStatus[] = [];

  lines.forEach((l, index) => {
    receivedValue = receivedValue.plus(l.receivedQty.mul(l.rate));
    damagedValue = damagedValue.plus(l.damagedQty.mul(l.rate));
    invoicedValue = invoicedValue.plus(l.invoicedQty.mul(l.rate));

    const short = l.invoicedQty.gt(l.receivedQty) ? l.invoicedQty.minus(l.receivedQty) : ZERO;
    if (short.gt(0)) {
      const value = short.mul(l.rate);
      debitNoteAmount = debitNoteAmount.plus(value);
      shortLines.push({ index, name: l.name, qty: short, value });
    }
    if (l.damagedQty.gt(0)) {
      damagedLines.push({ index, name: l.name, qty: l.damagedQty, value: l.damagedQty.mul(l.rate) });
    }

    const net = l.receivedQty.minus(l.damagedQty);
    stockAddedQty.push(net);
    stockAddedBase.push(toBase(net, l.purchaseUnitQty));
    statuses.push(lineStatus(l));

    if (l.hasPoLine && !l.invoicedQty.eq(l.orderedQty)) mismatch = true;
  });

  const invoiceValue = round2(invoiceValueInput ?? invoicedValue);
  if (invoiceValue.minus(invoicedValue).abs().gt(INVOICE_TOLERANCE)) mismatch = true;

  return {
    receivedValue: round2(receivedValue),
    damagedValue: round2(damagedValue),
    debitNoteAmount: round2(debitNoteAmount),
    invoicedValue: round2(invoicedValue),
    invoiceValue,
    payable: round2(invoiceValue.minus(round2(debitNoteAmount))),
    mismatch,
    lineStatus: statuses,
    stockAddedQty,
    stockAddedBase,
    shortLines,
    damagedLines,
  };
}

/** The debit note reason lists each short line, e.g. "1 × Wheat beer keg 30 L invoiced, not received" (PLAN.md 1.7). */
export function debitNoteReason(shortLines: { name: string; qty: Prisma.Decimal }[]): string {
  return shortLines.map((s) => `${s.qty.toString()} × ${s.name} invoiced, not received`).join('; ');
}

/** PO status after a GRN post (PLAN.md 1.7 GRN post step 4). */
export function purchaseOrderStatusAfterReceipt(
  lines: { qty: Prisma.Decimal; receivedQty: Prisma.Decimal }[],
  mismatch: boolean,
): PurchaseOrderStatus {
  if (mismatch) return 'INVOICE_MISMATCH';
  return lines.every((l) => l.receivedQty.gte(l.qty)) ? 'RECEIVED' : 'PARTLY_RECEIVED';
}

/** Reorder quantity in purchase units: ceil((par − onHand) ÷ purchaseUnitQty), at least 1 (PLAN.md 1.7). */
export function suggestedPurchaseQty(
  parLevel: Prisma.Decimal,
  onHand: Prisma.Decimal,
  purchaseUnitQty: Prisma.Decimal,
): Prisma.Decimal {
  const shortBy = parLevel.minus(onHand);
  const units = shortBy.div(purchaseUnitQty).toDecimalPlaces(0, ROUND_CEIL);
  return units.lt(ONE) ? ONE : units;
}

/** Line total: qty × rate, 2 dp. */
export function lineTotal(qty: Prisma.Decimal, rate: Prisma.Decimal): Prisma.Decimal {
  return round2(qty.mul(rate));
}

/** Outstanding quantity on a PO line (purchase units): qty − receivedQty, never below zero. */
export function outstandingQty(qty: Prisma.Decimal, receivedQty: Prisma.Decimal): Prisma.Decimal {
  const left = qty.minus(receivedQty);
  return left.gt(0) ? left : ZERO;
}
