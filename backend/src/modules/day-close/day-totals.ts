import { Prisma } from '@prisma/client';

const D = (v: Prisma.Decimal | number | string) => new Prisma.Decimal(v);
const money = (v: Prisma.Decimal) => v.toFixed(2);

/** Statuses of orders that took money at some point. */
const PAID_STATUSES = ['PAID', 'CLOSED', 'REFUNDED'];
const OPEN = ['OPEN', 'SENT', 'BILLED'];

export interface DayOrder {
  id: string;
  status: string;
  type: string;
  subtotal: Prisma.Decimal;
  discountTotal: Prisma.Decimal;
  serviceCharge: Prisma.Decimal;
  roundOff: Prisma.Decimal;
  grandTotal: Prisma.Decimal;
  taxBreakdown: unknown;
}

export interface DayPayment {
  orderId: string;
  paymentMethod: string;
  amount: Prisma.Decimal;
  tipAmount: Prisma.Decimal;
  status: string;
}

export interface DayItem {
  orderId: string;
  productId: string;
  quantity: number;
  net: Prisma.Decimal;
  status: string;
}

export interface DayDiscount {
  orderId: string;
  amount: Prisma.Decimal;
  createdById: string;
}

export interface DayFacts {
  businessDate: string;
  orders: DayOrder[];
  payments: DayPayment[];
  items: DayItem[];
  discounts: DayDiscount[];
  /** productId -> categoryId */
  categoryOfProduct: Map<string, string | null>;
  /** categoryId -> name */
  categoryNames: Map<string, string>;
  /** userId -> display name */
  userNames: Map<string, string>;
}

/** A payment row counts when it is a refund (negative) or a positive payment not marked REFUNDED. */
function countsAsPaid(p: DayPayment): boolean {
  return p.amount.isNegative() || p.status !== 'REFUNDED';
}

/**
 * Totals for the X and Z reports (PLAN.md 1.6). Pure: the caller loads the facts.
 * `net` is the grand total (sales including tax), so gross - discounts + service + tax + round-off = net.
 */
export function computeDayTotals(f: DayFacts) {
  const paid = f.orders.filter((o) => PAID_STATUSES.includes(o.status));
  const paidIds = new Set(paid.map((o) => o.id));

  const sum = (xs: Prisma.Decimal[]) => xs.reduce((a, b) => a.add(b), D(0));

  // Tax by component name and rate, summed over paid orders.
  const taxMap = new Map<string, { name: string; rate: string; amount: Prisma.Decimal }>();
  for (const o of paid) {
    for (const t of (o.taxBreakdown as { name: string; rate: string | number; amount: string }[]) ?? []) {
      const key = `${t.name}@${t.rate}`;
      const cur = taxMap.get(key) ?? { name: t.name, rate: String(t.rate), amount: D(0) };
      cur.amount = cur.amount.add(t.amount);
      taxMap.set(key, cur);
    }
  }

  const byPaymentMap = new Map<string, { method: string; count: number; amount: Prisma.Decimal }>();
  const payingRows = f.payments.filter(countsAsPaid);
  for (const p of payingRows) {
    const cur = byPaymentMap.get(p.paymentMethod) ?? { method: p.paymentMethod, count: 0, amount: D(0) };
    cur.count += 1;
    cur.amount = cur.amount.add(p.amount);
    byPaymentMap.set(p.paymentMethod, cur);
  }

  const byTypeMap = new Map<string, { type: string; count: number; amount: Prisma.Decimal }>();
  for (const o of paid) {
    const cur = byTypeMap.get(o.type) ?? { type: o.type, count: 0, amount: D(0) };
    cur.count += 1;
    cur.amount = cur.amount.add(o.grandTotal);
    byTypeMap.set(o.type, cur);
  }

  const byCategoryMap = new Map<string, { categoryId: string | null; name: string; quantity: number; amount: Prisma.Decimal }>();
  for (const it of f.items) {
    if (it.status === 'VOIDED' || !paidIds.has(it.orderId)) continue;
    const categoryId = f.categoryOfProduct.get(it.productId) ?? null;
    const key = categoryId ?? '__none';
    const cur = byCategoryMap.get(key) ?? {
      categoryId,
      name: categoryId ? f.categoryNames.get(categoryId) ?? 'Category' : 'Uncategorised',
      quantity: 0,
      amount: D(0),
    };
    cur.quantity += it.quantity;
    cur.amount = cur.amount.add(it.net);
    byCategoryMap.set(key, cur);
  }

  const voidOrders = f.orders.filter((o) => o.status === 'VOID');
  const refundRows = f.payments.filter((p) => p.amount.isNegative());
  const cashRows = f.payments.filter((p) => p.paymentMethod === 'CASH' && countsAsPaid(p));

  const staffMap = new Map<string, { userId: string; name: string; amount: Prisma.Decimal }>();
  for (const d of f.discounts) {
    const cur = staffMap.get(d.createdById) ?? {
      userId: d.createdById,
      name: f.userNames.get(d.createdById) ?? 'Staff',
      amount: D(0),
    };
    cur.amount = cur.amount.add(d.amount);
    staffMap.set(d.createdById, cur);
  }

  const tips = sum(payingRows.map((p) => p.tipAmount));
  const cashExpected = sum(cashRows.map((p) => p.amount.add(p.tipAmount)));

  return {
    businessDate: f.businessDate,
    orders: {
      count: f.orders.length,
      paid: paid.length,
      void: voidOrders.length,
      open: f.orders.filter((o) => OPEN.includes(o.status)).length,
    },
    gross: money(sum(paid.map((o) => o.subtotal))),
    discounts: money(sum(paid.map((o) => o.discountTotal))),
    serviceCharge: money(sum(paid.map((o) => o.serviceCharge))),
    tax: [...taxMap.values()].map((t) => ({ name: t.name, rate: t.rate, amount: money(t.amount) })),
    roundOff: money(sum(paid.map((o) => o.roundOff))),
    net: money(sum(paid.map((o) => o.grandTotal))),
    tips: money(tips),
    byPayment: [...byPaymentMap.values()].map((p) => ({ method: p.method, count: p.count, amount: money(p.amount) })),
    byType: [...byTypeMap.values()].map((t) => ({ type: t.type, count: t.count, amount: money(t.amount) })),
    byCategory: [...byCategoryMap.values()].map((c) => ({
      categoryId: c.categoryId,
      name: c.name,
      quantity: c.quantity,
      amount: money(c.amount),
    })),
    voids: { count: voidOrders.length, amount: money(sum(voidOrders.map((o) => o.grandTotal))) },
    refunds: {
      count: refundRows.length,
      amount: money(sum(refundRows.map((p) => p.amount.abs()))),
    },
    discountsByStaff: [...staffMap.values()].map((s) => ({ userId: s.userId, name: s.name, amount: money(s.amount) })),
    cashExpected: money(cashExpected),
  };
}

export type DayTotals = ReturnType<typeof computeDayTotals>;
