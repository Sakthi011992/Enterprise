import { Order, OrderDiscount, OrderItem, Payment, Prisma } from '@prisma/client';
import { D, StoredLineTax, money, readStoredTax } from './order-pricing';

/** An order with everything that belongs to it, loaded without relation fields. */
export interface OrderBundle {
  order: Order;
  items: OrderItem[];
  discounts: OrderDiscount[];
  payments: Payment[];
}

/** Lookups the view needs beyond the bundle. Built by OrdersRepository.viewContext. */
export interface ViewContext {
  /** productId -> station and ticket kind of its category. */
  routing: Map<string, { station: string; ticketKind: string }>;
  table: { id: string; name: string; areaName: string } | null;
  waiter: { id: string; name: string } | null;
  userNames: Map<string, string>;
}

/** Payments that count towards the bill: positive, not refunded, plus negative refund rows. */
export function paidAmount(payments: { amount: Prisma.Decimal; status: string }[]): Prisma.Decimal {
  return payments.reduce((sum, p) => {
    const amount = D(p.amount);
    if (amount.isNegative()) return sum.add(amount);
    if (p.status === 'REFUNDED') return sum;
    return sum.add(amount);
  }, D(0));
}

export function toOrderView(b: OrderBundle, ctx: ViewContext) {
  const { order } = b;
  const paid = paidAmount(b.payments);
  const grand = D(order.grandTotal);
  const subtotal = D(order.subtotal);
  const discountTotal = D(order.discountTotal);

  return {
    id: order.id,
    orderNumber: order.orderNumber,
    type: order.type,
    status: order.status,
    table: ctx.table,
    covers: order.covers,
    waiter: ctx.waiter,
    openedAt: order.createdAt.toISOString(),
    heldAt: iso(order.heldAt),
    billedAt: iso(order.billedAt),
    paidAt: iso(order.paidAt),
    note: order.note,
    items: b.items.map((item) => {
        const tax: StoredLineTax = readStoredTax(item.taxBreakdown);
        const route = ctx.routing.get(item.productId) ?? { station: 'KITCHEN', ticketKind: 'KOT' };
        const gross = D(item.grossAmount);
        const discount = D(item.discountAmount);
        return {
          id: item.id,
          productId: item.productId,
          comboId: item.comboId,
          name: item.productName,
          variantName: item.variantName,
          seat: item.seat,
          quantity: item.quantity,
          status: item.status,
          modifiers: readModifiers(item.modifiers).map((m) => ({
            optionId: m.optionId,
            name: m.name,
            priceDelta: money(m.priceDelta),
          })),
          note: item.note,
          unitPrice: money(item.price),
          gross: money(gross),
          discount: money(discount),
          net: money(gross.sub(discount)),
          tax: money(item.taxAmount),
          total: money(item.lineTotal),
          happyHourPercent: item.happyHourPercent === null ? null : money(item.happyHourPercent),
          isLiquor: tax.snapshot.isLiquor,
          ticketKind: route.ticketKind,
          station: route.station,
          sentAt: iso(item.sentAt),
        };
      }),
    discounts: b.discounts.map((d) => ({
      id: d.id,
      type: d.type,
      value: money(d.value),
      itemIds: d.itemIds,
      amount: money(d.amount),
      reason: d.reason,
      approvedBy: d.approvedById ? ctx.userNames.get(d.approvedById) ?? null : null,
    })),
    payments: b.payments.map((p) => ({
      id: p.id,
      method: p.paymentMethod,
      amount: money(p.amount),
      tipAmount: money(p.tipAmount),
      tendered: p.tendered === null ? null : money(p.tendered),
      changeGiven: p.changeGiven === null ? null : money(p.changeGiven),
      reference: p.reference,
      seat: p.seat,
      status: p.status,
      createdAt: p.createdAt.toISOString(),
    })),
    totals: {
      subtotal: money(subtotal),
      discountTotal: money(discountTotal),
      netSubtotal: money(subtotal.sub(discountTotal)),
      serviceCharge: money(order.serviceCharge),
      taxTotal: money(order.taxAmount),
      taxBreakdown: (order.taxBreakdown as unknown as { name: string; rate: string; amount: string }[]) ?? [],
      roundOff: money(order.roundOff),
      grandTotal: money(grand),
      paid: money(paid),
      due: money(grand.sub(paid)),
      tipTotal: money(order.tipTotal),
    },
    invoiceNumber: order.invoiceNumber,
  };
}

export type OrderView = ReturnType<typeof toOrderView>;

/** Modifier snapshot stored on OrderItem.modifiers: [{ groupId, optionId, name, priceDelta }]. */
export interface ModifierSnapshot {
  groupId: string;
  optionId: string;
  name: string;
  priceDelta: string;
}

export function readModifiers(json: unknown): ModifierSnapshot[] {
  return Array.isArray(json) ? (json as ModifierSnapshot[]) : [];
}

function iso(d: Date | null | undefined): string | null {
  return d ? d.toISOString() : null;
}
