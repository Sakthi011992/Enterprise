import { Injectable } from '@nestjs/common';
import { PricingLineInput } from '../../common/pricing/pricing.engine';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { OrderLineResolver } from '../orders/order-line-resolver';
import { D, money, runPricing, toPricingTaxClass, ZERO } from '../orders/order-pricing';
import { OrderPricingService } from '../orders/order-pricing.service';
import { paidAmount, readModifiers } from '../orders/order-view';
import { OrdersRepository } from '../orders/orders.repository';
import { readRoundItems, RoundItem } from './guest-round.types';
import { guestOrderStatus, GuestLineState, lineState, roundOnlyState, ticketStatusByLine } from './guest-status';
import { GuestRepository } from './guest.repository';

export interface GuestLineView {
  name: string;
  variant: string | null;
  modifiers: string[];
  qty: number;
  lineTotal: string;
  state: GuestLineState;
  updatedAt: string;
  estimate?: boolean;
}

export interface GuestRoundView {
  id: string;
  by: string;
  participantId: string | null;
  mine: boolean;
  status: 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'CANCELLED' | 'EXPIRED';
  rejectReason: string | null;
  createdAt: string;
  lines: GuestLineView[];
}

export interface GuestOrderView {
  orderId: string;
  table: string;
  status: 'OPEN' | 'BILLED' | 'PAID' | 'CLOSED';
  atTable: number;
  rounds: GuestRoundView[];
  totals: {
    subtotal: string;
    discount: string;
    serviceCharge: string;
    tax: string;
    roundOff: string;
    grandTotal: string;
    paid: string;
    due: string;
    /** True when pending rounds are included at today's price. */
    estimate: boolean;
    pendingEstimate: string;
  };
  checkout: { mode: 'WAITER' | 'ONLINE' | 'BOTH'; requested: boolean };
}

/**
 * GuestOrderView (PLAN 2.5). Guest-safe: no staff names, no costs. Line states are derived from the line,
 * its ticket (Ticket.items[].orderItemId) and the round. Totals come from the pricing engine over the order's
 * lines plus PENDING rounds priced at today's price (marked estimate).
 */
@Injectable()
export class GuestOrderViewService {
  constructor(
    private repo: GuestRepository,
    private orders: OrdersRepository,
    private pricing: OrderPricingService,
    private lines: OrderLineResolver,
    private config: GuestConfigService,
  ) {}

  /** For realtime (G-C GUEST_ORDER_VIEW builder): the view without a "mine" viewer. */
  build(orderId: string): Promise<GuestOrderView | null> {
    return this.forOrder(orderId, null);
  }

  async forOrder(orderId: string, participantId: string | null, now = new Date()): Promise<GuestOrderView | null> {
    const state = await this.repo.orderState(orderId);
    if (!state || !state.guestSessionId) return null;
    const sessionId = state.guestSessionId;

    const [requests, tickets, table, atTable, bill, cfg] = await Promise.all([
      this.repo.requestsForOrder(orderId),
      this.repo.ticketsForOrder(orderId),
      state.tableId ? this.repo.findTable(state.tableId) : Promise.resolve(null),
      this.repo.countParticipants(sessionId),
      this.repo.findOpenServiceRequest(sessionId, 'BILL'),
      this.config.get(state.tenantId),
    ]);

    const result = await this.orders.transaction(async (tx) => {
      const b = await this.orders.loadBundle(tx, orderId);
      if (!b) return null;
      const { input } = await this.pricing.inputFor(tx, b);

      // Price pending rounds at today's price, as extra lines in the same engine run.
      const pending = requests.filter((r) => r.status === 'PENDING');
      const extra: PricingLineInput[] = [];
      if (pending.length) {
        const ctx = await this.lines.context(tx, b.order, now);
        for (const r of pending) {
          for (const [k, it] of readRoundItems(r.items).entries()) {
            try {
              const line = await this.lines.resolve(tx, toAddItem(it), ctx);
              extra.push({
                id: `pending:${r.id}:${k}`,
                baseUnitPrice: line.unitPrice,
                modifiersDelta: ZERO,
                quantity: it.quantity,
                taxClass: toPricingTaxClass(line.snapshot),
                areaMarkupPercent: ZERO,
                happyHourPercent: null,
                voided: false,
              });
            } catch {
              // Item no longer available: left out of the estimate.
            }
          }
        }
      }
      const priced = runPricing({ ...input, lines: [...input.lines, ...extra] });
      const base = runPricing(input);
      return { b, priced, base, pendingTotals: new Map(priced.lines.map((l) => [l.id, l.total])) };
    });
    if (!result) return null;
    const { b, priced, base, pendingTotals } = result;

    const ticketOf = ticketStatusByLine(tickets);
    const byRequest = new Map<string, typeof b.items>();
    const staffLines: typeof b.items = [];
    for (const item of b.items) {
      if (item.guestRequestId) {
        const list = byRequest.get(item.guestRequestId) ?? [];
        list.push(item);
        byRequest.set(item.guestRequestId, list);
      } else staffLines.push(item);
    }

    const orderLine = (item: (typeof b.items)[number]): GuestLineView => {
      const t = ticketOf.get(item.id);
      const at = item.voidedAt ?? t?.at ?? item.sentAt ?? item.createdAt;
      return {
        name: item.productName,
        variant: item.variantName,
        modifiers: readModifiers(item.modifiers).map((m) => m.name),
        qty: item.quantity,
        lineTotal: money(item.status === 'VOIDED' ? 0 : item.lineTotal),
        state: lineState(item.status, t?.status),
        updatedAt: at.toISOString(),
      };
    };

    const rounds: GuestRoundView[] = requests.map((r) => {
      const confirmed = r.status === 'CONFIRMED';
      const lines: GuestLineView[] = confirmed
        ? (byRequest.get(r.id) ?? []).map(orderLine)
        : readRoundItems(r.items).map((it, k) => ({
            name: it.name ?? '',
            variant: it.variantName ?? null,
            modifiers: it.modifierNames ?? [],
            qty: it.quantity,
            lineTotal: money(r.status === 'PENDING' ? pendingTotals.get(`pending:${r.id}:${k}`) ?? it.lineTotal ?? 0 : 0),
            state: roundOnlyState(r.status),
            updatedAt: (r.decidedAt ?? r.createdAt).toISOString(),
            ...(r.status === 'PENDING' ? { estimate: true } : {}),
          }));
      return {
        id: r.id,
        by: r.participant.name,
        participantId: r.participantId,
        mine: participantId !== null && r.participantId === participantId,
        status: r.status,
        rejectReason: r.rejectReason,
        createdAt: r.createdAt.toISOString(),
        lines,
      };
    });
    if (staffLines.length) {
      rounds.push({
        id: 'staff',
        by: 'Added by staff',
        participantId: null,
        mine: false,
        status: 'CONFIRMED',
        rejectReason: null,
        createdAt: staffLines[0].createdAt.toISOString(),
        lines: staffLines.map(orderLine),
      });
    }

    const paid = paidAmount(b.payments);
    const hasPending = requests.some((r) => r.status === 'PENDING');
    return {
      orderId,
      table: table?.name ?? '',
      status: guestOrderStatus(b.order.status),
      atTable,
      rounds,
      totals: {
        subtotal: money(priced.subtotal),
        discount: money(priced.discountTotal),
        serviceCharge: money(priced.serviceCharge),
        tax: money(priced.taxTotal),
        roundOff: money(priced.roundOff),
        grandTotal: money(priced.grandTotal),
        paid: money(paid),
        due: money(D(priced.grandTotal).sub(paid)),
        estimate: hasPending,
        pendingEstimate: money(D(priced.grandTotal).sub(base.grandTotal)),
      },
      checkout: { mode: cfg.checkout, requested: !!bill },
    };
  }
}

export function toAddItem(it: RoundItem) {
  return {
    productId: it.productId,
    variantId: it.variantId ?? undefined,
    quantity: it.quantity,
    note: it.note ?? undefined,
    modifierOptionIds: (it.modifiers ?? []).map((m) => m.optionId),
  };
}
