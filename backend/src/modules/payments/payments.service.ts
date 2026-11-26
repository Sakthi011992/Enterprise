import { Injectable, NotFoundException, Optional } from '@nestjs/common';
import { GuestHooks } from '../guest/guest-hooks.service';
import { OrderStatus, Payment, PaymentMethod, PaymentStatus, Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { PrintService } from '../printing/print.service';
import { InvoiceService } from '../invoice/invoice.service';
import { ApprovalsService } from '../approvals/approvals.service';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { PermissionsService } from '../personas/permissions.service';
import { TabsLimitService } from '../tabs/tabs-limit.service';
import { RealtimeService } from '../realtime/realtime.service';
import { outletEvent } from '../realtime/realtime.types';
import { OrderBundle, OrderView, paidAmount, toOrderView } from '../orders/order-view';
import { OrdersRepository } from '../orders/orders.repository';
import { OrderPricingService } from '../orders/order-pricing.service';
import { D, money, PAYABLE_STATUSES, ZERO } from '../orders/order-pricing';
import { buildShares, SplitShare } from './split';
import { CreatePaymentDto, PayOrderDto, PaymentLineDto, RefundDto, SplitQueryDto } from './dto/payment.dto';
import { PaymentsRepository } from './payments.repository';

const DINE_IN_TYPES = ['DINE_IN'];

interface Settled {
  view: OrderView;
  change: Prisma.Decimal;
  created: Payment[];
  hasCash: boolean;
  grand: Prisma.Decimal;
  paid: Prisma.Decimal;
}

/**
 * Takes payments (split tender in one call), settles the order on full payment, allocates the invoice
 * number, and handles the split view, close and refunds.
 */
@Injectable()
export class PaymentsService {
  constructor(
    private repo: PaymentsRepository,
    private orders: OrdersRepository,
    private pricing: OrderPricingService,
    private invoices: InvoiceService,
    private approvals: ApprovalsService,
    private audit: AuditTrailService,
    private permissions: PermissionsService,
    private print: PrintService,
    private tabs: TabsLimitService,
    private realtime: RealtimeService,
    @Optional() private guestHooks?: GuestHooks,
  ) {}

  // ===========================================================================
  // Pay
  // ===========================================================================

  /** POST /orders/:id/payments. Returns the order and the change to give back. */
  async pay(orderId: string, dto: PayOrderDto, auth: AuthUser) {
    const s = await this.repo.transaction((tx) => this.settle(tx, orderId, dto, auth));
    this.realtime.publish([outletEvent(auth.outletId, 'order.updated', { orderId, status: s.view.status })]);
    this.guestHooks?.orderChanged(orderId);
    if (s.hasCash) {
      try {
        await this.print.openDrawer(auth.outletId, 'Cash payment');
      } catch (e) {
        // A drawer fault must not undo a payment that is already recorded.
      }
    }
    return { order: s.view, change: money(s.change) };
  }

  /** Legacy POST /payments: one payment, legacy response shape. */
  async legacyCreate(dto: CreatePaymentDto, auth: AuthUser) {
    const line: PaymentLineDto = { method: dto.paymentMethod, amount: dto.amount };
    const s = await this.repo.transaction((tx) => this.settle(tx, dto.orderId, { payments: [line] }, auth));
    this.realtime.publish([outletEvent(auth.outletId, 'order.updated', { orderId: dto.orderId, status: s.view.status })]);
    if (s.hasCash) {
      try {
        await this.print.openDrawer(auth.outletId, 'Cash payment');
      } catch (e) {
        // See pay().
      }
    }
    return {
      payment: s.created[0],
      order: { id: s.view.id, status: s.view.status, paid: s.view.totals.paid, grandTotal: s.view.totals.grandTotal },
    };
  }

  private async settle(tx: Prisma.TransactionClient, orderId: string, dto: PayOrderDto, auth: AuthUser): Promise<Settled> {
    const loaded = await this.loadOwn(tx, orderId, auth);
    if (!PAYABLE_STATUSES.includes(loaded.order.status)) {
      throw apiError(409, 'ORDER_NOT_PAYABLE', 'This order cannot take payments', { status: loaded.order.status });
    }

    // Re-price first, so the due amount reflects every change made so far.
    const b = await this.pricing.recalc(tx, orderId);
    const grand = D(b.order.grandTotal);
    const paidSoFar = paidAmount(b.payments);
    const dueNow = grand.sub(paidSoFar).isNegative() ? ZERO : grand.sub(paidSoFar);

    const requested = dto.payments.reduce((sum, p) => sum.add(D(p.amount)), ZERO);
    if (requested.greaterThan(dueNow)) {
      throw apiError(400, 'PAYMENT_EXCEEDS_DUE', `Payment exceeds the balance due (${money(dueNow)})`, {
        due: money(dueNow),
      });
    }

    const tip = D(dto.tipAmount ?? 0);
    const cashIndex = dto.payments.findIndex((p) => p.method === PaymentMethod.CASH);
    const tipIndex = cashIndex >= 0 ? cashIndex : 0;

    let change = ZERO;
    const rows = dto.payments.map((p, i) => {
      const amount = D(p.amount);
      const tipHere = dto.tipAmount !== undefined && i === tipIndex ? tip : ZERO;
      if (p.method !== PaymentMethod.CASH) {
        return { line: p, amount, tipHere, tendered: null, changeGiven: null };
      }
      const owed = amount.add(tipHere);
      const tendered = p.tendered !== undefined ? D(p.tendered) : owed;
      if (tendered.lessThan(owed)) {
        throw apiError(400, 'TENDERED_TOO_LOW', `Cash given is less than the amount due (${money(owed)})`, {
          owed: money(owed),
        });
      }
      const given = tendered.sub(owed);
      change = change.add(given);
      return { line: p, amount, tipHere, tendered, changeGiven: given };
    });

    if (dto.completeSeat) {
      const seat = dto.payments[0].seat;
      if (!seat || dto.payments.some((p) => p.seat !== seat)) {
        throw apiError(400, 'SEAT_REQUIRED', 'Completing a seat needs every line to name that seat');
      }
      const seatPaid = this.paidBySeat(b.payments).get(seat) ?? ZERO;
      const shares = this.sharesFor(b, 'SEAT', undefined, this.paidBySeat(b.payments));
      const share = shares.find((s) => s.seat === seat);
      const seatDue = share ? share.amount.sub(seatPaid).sub(requested) : ZERO;
      if (seatDue.greaterThan(0)) {
        throw apiError(400, 'SEAT_NOT_FULLY_PAID', `Seat ${seat} still owes ${money(seatDue)}`, {
          seat,
          due: money(seatDue),
        });
      }
    }

    const created: Payment[] = [];
    for (const r of rows) {
      created.push(
        await this.repo.createPayment(tx, {
          orderId,
          amount: r.amount,
          paymentMethod: r.line.method,
          status: PaymentStatus.PAID,
          seat: r.line.seat ?? null,
          tipAmount: r.tipHere,
          tendered: r.tendered,
          changeGiven: r.changeGiven,
          reference: r.line.reference ?? null,
          createdById: auth.userId,
        }),
      );
    }

    const paidNow = paidSoFar.add(requested);
    const tipTotal = D(b.order.tipTotal).add(rows.reduce((s, r) => s.add(r.tipHere), ZERO));
    const settled = paidNow.greaterThanOrEqualTo(grand) && grand.greaterThan(0);

    if (settled) {
      const settings = await this.orders.getOutletSettings(tx, b.order.outletId);
      const invoiceNumber = b.order.invoiceNumber
        ? b.order.invoiceNumber
        : await this.invoices.issueForOrder(
            tx,
            {
              id: b.order.id,
              subtotal: b.order.subtotal,
              taxAmount: b.order.taxAmount,
              grandTotal: b.order.grandTotal,
              taxBreakdown: b.order.taxBreakdown,
            },
            { countryCode: settings.countryCode, invoicePrefix: settings.invoicePrefix },
          );
      const now = new Date();
      const dineIn = DINE_IN_TYPES.includes(b.order.type);
      await this.orders.updateOrder(tx, b.order.id, {
        status: dineIn ? OrderStatus.PAID : OrderStatus.CLOSED,
        paidAt: now,
        closedAt: dineIn ? null : now,
        invoiceNumber,
        tipTotal,
      });
      if (dineIn && b.order.tableId) await this.orders.setTableStatus(tx, b.order.tableId, 'CLEANING');
      // A bar tab on this order closes once the order is fully paid (PLAN 1.7 Orders integration).
      await this.tabs.onOrderPaid(tx, b.order.id, now);
    } else {
      await this.orders.updateOrder(tx, b.order.id, { tipTotal });
    }

    const saved = await this.orders.loadBundle(tx, orderId);
    const view = toOrderView(saved!, await this.orders.viewContext(tx, saved!));
    return {
      view,
      change,
      created,
      hasCash: rows.some((r) => r.line.method === PaymentMethod.CASH),
      grand,
      paid: paidNow,
    };
  }

  // ===========================================================================
  // Split
  // ===========================================================================

  /** GET /orders/:id/split: the shares for the pay screen. Amounts sum to the grand total. */
  async split(orderId: string, q: SplitQueryDto, auth: AuthUser) {
    return this.repo.transaction(async (tx) => {
      const b = await this.loadOwn(tx, orderId, auth);
      const shares = this.sharesFor(b, q.mode, { parts: q.parts, assign: q.assign }, this.paidBySeat(b.payments));
      return {
        grandTotal: money(b.order.grandTotal),
        shares: shares.map((s) => ({
          label: s.label,
          seat: s.seat,
          itemIds: s.itemIds,
          amount: money(s.amount),
          paid: money(s.paid),
          due: money(s.due),
        })),
      };
    });
  }

  private sharesFor(
    b: OrderBundle,
    mode: 'EQUAL' | 'SEAT' | 'ITEMS',
    opts: { parts?: number; assign?: string } | undefined,
    paidBySeat: Map<number, Prisma.Decimal>,
  ): SplitShare[] {
    const lines = b.items
      .filter((i) => i.status !== 'VOIDED')
      .map((i) => ({ id: i.id, seat: i.seat, total: D(i.lineTotal) }));
    return buildShares({
      mode,
      parts: opts?.parts,
      assign: opts?.assign,
      lines,
      grandTotal: D(b.order.grandTotal),
      extra: D(b.order.serviceCharge).add(D(b.order.roundOff)),
      paidBySeat,
    });
  }

  /** Money paid per seat (positive payments not refunded, plus refund rows against that seat). */
  private paidBySeat(payments: OrderBundle['payments']): Map<number, Prisma.Decimal> {
    const out = new Map<number, Prisma.Decimal>();
    for (const p of payments) {
      if (p.seat === null) continue;
      const amount = D(p.amount);
      if (amount.greaterThan(0) && p.status === PaymentStatus.REFUNDED) continue;
      out.set(p.seat, (out.get(p.seat) ?? ZERO).add(amount));
    }
    return out;
  }

  // ===========================================================================
  // Close
  // ===========================================================================

  /** Close the bill: PAID to CLOSED, table to CLEANING. */
  async close(orderId: string, auth: AuthUser): Promise<OrderView> {
    const view = await this.closeTx(orderId, auth);
    this.guestHooks?.orderChanged(orderId);
    return view;
  }

  private closeTx(orderId: string, auth: AuthUser): Promise<OrderView> {
    return this.repo.transaction(async (tx) => {
      const b = await this.loadOwn(tx, orderId, auth);
      if (b.order.status !== 'PAID') {
        throw apiError(409, 'ORDER_NOT_PAID', 'Only a paid order can be closed', { status: b.order.status });
      }
      await this.orders.updateOrder(tx, b.order.id, { status: 'CLOSED', closedAt: new Date() });
      if (b.order.tableId) await this.orders.setTableStatus(tx, b.order.tableId, 'CLEANING');
      const saved = await this.orders.loadBundle(tx, orderId);
      return toOrderView(saved!, await this.orders.viewContext(tx, saved!));
    });
  }

  // ===========================================================================
  // Refunds
  // ===========================================================================

  /**
   * Refund against a paid order: a negative payment row with status REFUNDED. A refund that takes the
   * order to zero paid marks it REFUNDED. Needs sales.void APPROVE, or an approved REFUND approval.
   */
  async refund(orderId: string, dto: RefundDto, auth: AuthUser): Promise<OrderView> {
    return this.repo.transaction(async (tx) => {
      const b = await this.loadOwn(tx, orderId, auth);
      if (b.order.status !== 'PAID' && b.order.status !== 'CLOSED') {
        throw apiError(409, 'ORDER_NOT_PAID', 'Only a paid order can be refunded', { status: b.order.status });
      }

      const payload = { amount: dto.amount, paymentId: dto.paymentId ?? null, reason: dto.reason };
      if (!this.permissions.check(auth, 'sales.void', 'APPROVE')) {
        if (!dto.approvalId) throw apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve this refund', { required: 'APPROVE' });
        await this.approvals.assertApproved(dto.approvalId, auth, 'REFUND', payload, orderId);
      }

      const requested = D(dto.amount);
      const paid = paidAmount(b.payments);
      if (requested.greaterThan(paid)) {
        throw apiError(400, 'REFUND_EXCEEDS_PAID', `Only ${money(paid)} can be refunded`, { paid: money(paid) });
      }

      let method: PaymentMethod = PaymentMethod.CASH;
      if (dto.paymentId) {
        const source = b.payments.find((p) => p.id === dto.paymentId && p.amount.greaterThan(0));
        if (!source) throw new NotFoundException('Payment not found on this order');
        if (requested.greaterThan(source.amount)) {
          throw apiError(400, 'REFUND_EXCEEDS_PAYMENT', `That payment is only ${money(source.amount)}`);
        }
        method = source.paymentMethod;
      } else {
        const last = [...b.payments].reverse().find((p) => p.amount.greaterThan(0) && p.status !== PaymentStatus.REFUNDED);
        if (last) method = last.paymentMethod;
      }

      await this.repo.createPayment(tx, {
        orderId,
        amount: requested.neg(),
        paymentMethod: method,
        status: PaymentStatus.REFUNDED,
        createdById: auth.userId,
        reference: dto.reason.slice(0, 100),
      });
      if (paid.sub(requested).lessThanOrEqualTo(0)) {
        await this.orders.updateOrder(tx, b.order.id, { status: 'REFUNDED' });
      }
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.refund',
        entity: 'Order',
        entityId: b.order.id,
        metadata: { amount: money(requested), reason: dto.reason, paymentId: dto.paymentId ?? null, approvalId: dto.approvalId ?? null },
      });

      const saved = await this.orders.loadBundle(tx, orderId);
      return toOrderView(saved!, await this.orders.viewContext(tx, saved!));
    });
  }

  /** Legacy POST /payments/:id/refund: marks the payment and its order REFUNDED. Kept for the old billing screen. */
  async legacyRefund(paymentId: string) {
    const payment = await this.repo.findPayment(paymentId);
    if (!payment) throw new NotFoundException('Payment not found');
    return this.repo.transaction(async (tx) => {
      const updated = await this.repo.markRefunded(tx, paymentId);
      await this.orders.updateOrder(tx, payment.orderId, { status: 'REFUNDED' });
      return updated;
    });
  }

  findByOrder(orderId: string) {
    return this.repo.findByOrder(orderId);
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /** Loads an order, checks it belongs to the caller's outlet, and returns the bundle. */
  private async loadOwn(tx: Prisma.TransactionClient, orderId: string, auth: AuthUser): Promise<OrderBundle> {
    const b = await this.orders.loadBundle(tx, orderId);
    if (!b || (b.order.outletId && b.order.outletId !== auth.outletId)) {
      throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');
    }
    return b;
  }
}
