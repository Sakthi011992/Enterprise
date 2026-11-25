import { Injectable, Logger } from '@nestjs/common';
import { Order, OrderItem, Prisma, Ticket, TicketKind } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { levelAtLeast, AccessLevel } from '../../common/permissions/catalog';
import { PermissionGrant } from '../../common/decorators/current-user.decorator';
import { PermissionsService } from '../personas/permissions.service';
import { businessDateFor } from '../../common/pricing/business-date';
import { ApprovalsService } from '../approvals/approvals.service';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { PrintService } from '../printing/print.service';
import { buildMeta } from '../../common/dto/pagination.dto';
import { dayWindow } from './business-day-window';
import {
  AddItemDto,
  AddItemsDto,
  BillDto,
  CreateOrderDto,
  DiscountDto,
  MergeOrderDto,
  MoveOrderDto,
  OrderQueryDto,
  TransferItemsDto,
  UpdateItemDto,
  VoidItemsDto,
  VoidOrderDto,
} from './dto/order.dto';
import {
  D,
  EDITABLE_STATUSES,
  money,
  OPEN_STATUSES,
  percentEquivalent,
  ZERO,
} from './order-pricing';
import { OrderPricingService } from './order-pricing.service';
import { LineContext, OrderLineResolver, ResolvedLine } from './order-line-resolver';
import { OrderBundle, OrderView, readModifiers, toOrderView } from './order-view';
import { OrdersRepository } from './orders.repository';
import { StockLedgerService, MovementContext } from '../stock-core/stock-ledger.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RealtimeEvent, outletEvent, stationEvent } from '../realtime/realtime.types';
import { TabsLimitService } from '../tabs/tabs-limit.service';
import { contextFromView, readTicketItems, toKdsTicket } from '../kds/kds-view';

const json = (v: unknown) => v as Prisma.InputJsonValue;

/**
 * What a mutation hands to the code that runs after its transaction commits: tickets to print, KDS rows
 * to publish, and realtime events queued by the stock ledger and the tab rules.
 */
interface Outbox {
  /** Tickets created by this mutation (cancellation tickets included, they are printed but not shown on the KDS). */
  created: Ticket[];
  /** Original tickets whose lines were voided. Their KDS cards are re-sent. */
  updated: Ticket[];
  events: RealtimeEvent[];
  orderChanged: boolean;
}

@Injectable()
export class OrdersService {
  private readonly logger = new Logger(OrdersService.name);

  constructor(
    private repo: OrdersRepository,
    private pricing: OrderPricingService,
    private lines: OrderLineResolver,
    private approvals: ApprovalsService,
    private audit: AuditTrailService,
    private permissions: PermissionsService,
    private print: PrintService,
    private stock: StockLedgerService,
    private realtime: RealtimeService,
    private tabs: TabsLimitService,
  ) {}

  // ===========================================================================
  // Legacy search
  // ===========================================================================

  async findAll(q: OrderQueryDto) {
    const where: Prisma.OrderWhereInput = {
      ...(q.search ? { invoiceNumber: { contains: q.search, mode: 'insensitive' } } : {}),
      ...(q.from || q.to
        ? { createdAt: { ...(q.from ? { gte: new Date(q.from) } : {}), ...(q.to ? { lte: new Date(q.to) } : {}) } }
        : {}),
    };
    const [data, total] = await this.repo.findAll(where, q.skip, q.limit);
    return { data, meta: buildMeta(total, q.page, q.limit) };
  }

  // ===========================================================================
  // Create
  // ===========================================================================

  /**
   * POST /orders. Idempotent on offlineId. Dine-in claims the table (FREE or RESERVED to OCCUPIED) and
   * allocates the order number in the same transaction. The legacy body (no `type`) returns the legacy
   * total fields as well.
   */
  async create(dto: CreateOrderDto, auth: AuthUser) {
    const legacy = dto.type === undefined;
    if (legacy && (!dto.items || dto.items.length === 0)) {
      throw apiError(400, 'ITEMS_REQUIRED', 'At least one item is required');
    }
    const type = dto.type ?? 'TAKEAWAY';
    if (type === 'DINE_IN' && !dto.tableId) throw apiError(400, 'TABLE_REQUIRED', 'Dine-in orders need a table');

    const view = await this.repo.transaction(async (tx) => {
      if (dto.offlineId) {
        const existing = await this.repo.findOrderByOfflineId(tx, dto.offlineId);
        if (existing) return this.viewOf(tx, await this.load(tx, existing.id, auth));
      }

      if (type === 'DINE_IN') {
        const table = await this.repo.findTable(tx, dto.tableId!, auth.outletId);
        if (!table) throw apiError(404, 'TABLE_NOT_FOUND', 'Table not found');
        const claimed = await this.repo.claimTable(tx, table.id, auth.outletId, ['FREE', 'RESERVED'], 'OCCUPIED');
        if (claimed === 0) throw apiError(409, 'TABLE_OCCUPIED', 'This table is already in use', { tableId: table.id });
      }

      const orderNumber = await this.repo.nextOrderNumber(tx, auth.outletId);
      const order = await this.repo.createOrder(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        orderNumber,
        type,
        status: 'OPEN',
        tableId: dto.tableId ?? null,
        covers: dto.covers ?? 1,
        waiterId: dto.waiterId ?? auth.userId,
        cashierId: auth.userId,
        note: dto.note ?? null,
        offlineId: dto.offlineId ?? null,
        subtotal: ZERO,
        taxAmount: ZERO,
        grandTotal: ZERO,
        invoiceNumber: null,
      });
      if (dto.items?.length) {
        await this.addLines(tx, order, dto.items, auth, new Date());
      }
      return this.viewOf(tx, await this.load(tx, order.id, auth));
    });

    if (!legacy) return view;
    return {
      ...view,
      subtotal: view.totals.subtotal,
      taxAmount: view.totals.taxTotal,
      grandTotal: view.totals.grandTotal,
    };
  }

  async findOne(id: string, auth: AuthUser): Promise<OrderView> {
    return this.repo.transaction(async (tx) => this.viewOf(tx, await this.load(tx, id, auth)));
  }

  /** Open orders of the outlet (OPEN, SENT, BILLED), light list for the POS floor. */
  async openOrders(auth: AuthUser) {
    const rows = await this.repo.openOrders(auth.outletId);
    return {
      data: rows.map((o) => ({
        id: o.id,
        orderNumber: o.orderNumber,
        type: o.type,
        status: o.status,
        tableId: o.tableId,
        covers: o.covers,
        grandTotal: money(o.grandTotal),
        openedAt: o.createdAt.toISOString(),
        heldAt: o.heldAt ? o.heldAt.toISOString() : null,
      })),
    };
  }

  // ===========================================================================
  // Items
  // ===========================================================================

  async addItems(id: string, dto: AddItemsDto, auth: AuthUser): Promise<OrderView> {
    const now = new Date();
    const { view, after } = await this.mutateWithOutbox(id, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      const spentBefore = D(b.order.grandTotal);
      await this.addLines(tx, b.order, dto.items, auth, now);
      await this.reopenBilled(tx, b.order, auth);
      box.orderChanged = b.order.status === 'BILLED';
      // Throws TAB_LIMIT_REACHED, which rolls the whole addition back.
      box.events.push(...(await this.tabs.enforce(tx, b.order.id, spentBefore, now)));
    });
    await after();
    return view;
  }

  async updateItem(orderId: string, itemId: string, dto: UpdateItemDto, auth: AuthUser): Promise<OrderView> {
    const now = new Date();
    const { view, after } = await this.mutateWithOutbox(orderId, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      const spentBefore = D(b.order.grandTotal);
      const item = this.itemOf(b, itemId);
      if (item.status !== 'NEW') throw apiError(409, 'ITEM_ALREADY_SENT', 'This item was already sent to the kitchen');

      const data: Prisma.OrderItemUncheckedUpdateInput = {};
      if (dto.quantity !== undefined) data.quantity = dto.quantity;
      if (dto.seat !== undefined) data.seat = dto.seat;
      if (dto.note !== undefined) data.note = dto.note;

      if (dto.modifierOptionIds !== undefined) {
        // Modifiers change the unit price, so the line is priced again from the catalogue.
        const ctx = await this.lines.context(tx, b.order, new Date());
        const fresh = await this.lines.resolve(tx, this.asAddItem(item, dto.modifierOptionIds), ctx);
        Object.assign(data, this.lineFields(fresh));
      }
      await this.repo.updateItem(tx, item.id, data);
      await this.pricing.recalc(tx, b.order.id);
      box.events.push(...(await this.tabs.enforce(tx, b.order.id, spentBefore, now)));
    });
    await after();
    return view;
  }

  async removeItem(orderId: string, itemId: string, auth: AuthUser): Promise<OrderView> {
    const { view } = await this.mutate(orderId, auth, async (tx, b) => {
      this.assertEditable(b.order);
      const item = this.itemOf(b, itemId);
      if (item.status !== 'NEW') {
        throw apiError(409, 'ITEM_ALREADY_SENT', 'Sent items must be voided, not removed');
      }
      await this.repo.deleteItem(tx, item.id);
      await this.pricing.recalc(tx, b.order.id);
    });
    return view;
  }

  // ===========================================================================
  // Send, hold, bill
  // ===========================================================================

  /** Sends every NEW line: one ticket per station and kind, items to SENT, order to SENT. */
  async send(orderId: string, auth: AuthUser) {
    const now = new Date();
    const { view, box, after } = await this.mutateWithOutbox(orderId, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      const pending = b.items.filter((i) => i.status === 'NEW');
      if (pending.length === 0) throw apiError(400, 'NOTHING_TO_SEND', 'No new items to send');

      const tickets = await this.createTickets(tx, b, pending, auth, false, now);
      for (const item of pending) await this.repo.updateItem(tx, item.id, { status: 'SENT', sentAt: now });
      if (b.order.status !== 'SENT') await this.repo.updateOrder(tx, b.order.id, { status: 'SENT' });

      // Recipe deduction at the station of each line (PLAN 1.4). Ledger events go into the outbox.
      const routing = await this.repo.routingFor(tx, [...new Set(pending.map((i) => i.productId))]);
      await this.stock.deductForSentItems(
        tx,
        this.stockContext(auth, now, box.events),
        pending.map((item) => ({
          orderItemId: item.id,
          productId: item.productId,
          variantId: item.variantId,
          quantity: item.quantity,
          modifiers: readModifiers(item.modifiers),
          station: routing.get(item.productId ?? '')?.station ?? 'KITCHEN',
        })),
      );

      box.created.push(...tickets);
      box.orderChanged = true;
    });
    await after();
    return {
      order: view,
      tickets: box.created.map((t) => ({ id: t.id, kind: t.kind, station: t.station, seq: t.seq })),
    };
  }

  async setHold(orderId: string, hold: boolean, auth: AuthUser): Promise<OrderView> {
    const { view } = await this.mutate(orderId, auth, async (tx, b) => {
      this.assertEditable(b.order);
      await this.repo.updateOrder(tx, b.order.id, { heldAt: hold ? new Date() : null });
    });
    return view;
  }

  /** Prints the pre-payment bill. Needs every line sent first. Dine-in table moves to BILL_PRINTED. */
  async bill(orderId: string, dto: BillDto, auth: AuthUser) {
    const { view, after } = await this.mutateWithOutbox(orderId, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      const live = b.items.filter((i) => i.status !== 'VOIDED');
      if (live.length === 0) throw apiError(400, 'NOTHING_TO_BILL', 'The order has no items');
      const unsent = live.filter((i) => i.status === 'NEW').length;
      if (unsent > 0) throw apiError(409, 'UNSENT_ITEMS', 'Send the new items before printing the bill', { count: unsent });

      await this.repo.updateOrder(tx, b.order.id, { status: 'BILLED', billedAt: new Date() });
      if (b.order.type === 'DINE_IN' && b.order.tableId) {
        await this.repo.setTableStatus(tx, b.order.tableId, 'BILL_PRINTED');
      }
      box.orderChanged = true;
    });
    await this.print.queueBill(orderId, { copies: dto.copies ?? 1 });
    await after();
    return view;
  }

  // ===========================================================================
  // Discounts
  // ===========================================================================

  async addDiscount(orderId: string, dto: DiscountDto, auth: AuthUser): Promise<OrderView> {
    const { view } = await this.mutate(orderId, auth, async (tx, b) => {
      this.assertEditable(b.order);
      if (dto.type === 'PERCENT' && dto.value > 100) {
        throw apiError(400, 'INVALID_PERCENT', 'A percent discount cannot exceed 100');
      }
      const itemIds = [...new Set(dto.itemIds ?? [])];
      const live = new Set(b.items.filter((i) => i.status !== 'VOIDED').map((i) => i.id));
      const unknown = itemIds.filter((id) => !live.has(id));
      if (unknown.length) throw apiError(400, 'ITEM_NOT_FOUND', 'Some items are not on this order', { itemIds: unknown });

      const value = D(dto.value);
      const base = await this.pricing.discountableBase(tx, b);
      const percentEq = percentEquivalent(dto.type, value, base);
      const grant: PermissionGrant = auth.permissions['sales.discount.give'] ?? { level: 'NONE' as AccessLevel, limit: null };
      const direct =
        levelAtLeast(grant.level, 'APPROVE') ||
        (grant.level === 'LIMITED' && grant.limit !== null && percentEq.lessThanOrEqualTo(grant.limit));

      let approvedById: string | null = null;
      if (!direct) {
        if (!dto.approvalId) {
          throw apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve this discount', {
            limit: grant.limit,
          });
        }
        const approval = await this.approvals.assertApproved(
          dto.approvalId,
          auth,
          'DISCOUNT',
          { type: dto.type, value: dto.value, itemIds, reason: dto.reason },
          b.order.id,
        );
        approvedById = approval.approverId;
      }

      const discount = await this.repo.createDiscount(tx, {
        orderId: b.order.id,
        type: dto.type,
        value,
        itemIds,
        amount: ZERO,
        reason: dto.reason,
        createdById: auth.userId,
        approvedById,
      });
      // Re-pricing throws LIQUOR_DISCOUNT_NOT_ALLOWED (400) for an item-level discount on a liquor line.
      await this.pricing.recalc(tx, b.order.id);

      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: approvedById ? 'discount.approved' : 'discount.applied',
        entity: 'Order',
        entityId: b.order.id,
        metadata: { discountId: discount.id, type: dto.type, value: dto.value, itemIds, reason: dto.reason, approvedById },
      });
    });
    return view;
  }

  async removeDiscount(orderId: string, discountId: string, auth: AuthUser): Promise<OrderView> {
    const { view } = await this.mutate(orderId, auth, async (tx, b) => {
      this.assertEditable(b.order);
      const discount = await this.repo.findDiscount(tx, discountId, b.order.id);
      if (!discount) throw apiError(404, 'DISCOUNT_NOT_FOUND', 'Discount not found');
      await this.repo.deleteDiscount(tx, discount.id);
      await this.pricing.recalc(tx, b.order.id);
    });
    return view;
  }

  // ===========================================================================
  // Voids
  // ===========================================================================

  /** Voiding a SENT item prints a cancellation ticket at its station and logs the wastage. */
  async voidItems(orderId: string, dto: VoidItemsDto, auth: AuthUser) {
    const now = new Date();
    const { view, after } = await this.mutateWithOutbox(orderId, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      const targets = dto.itemIds.map((id) => {
        const item = b.items.find((i) => i.id === id);
        if (!item || item.status === 'VOIDED') throw apiError(400, 'ITEM_NOT_FOUND', 'Item not found on this order', { itemId: id });
        return item;
      });
      await this.authoriseVoid(auth, dto.approvalId, { itemIds: [...new Set(dto.itemIds)] }, b.order.id);

      const sent = targets.filter((i) => i.status === 'SENT' || i.status === 'SERVED');
      for (const item of targets) {
        await this.repo.updateItem(tx, item.id, { status: 'VOIDED', voidedAt: now, voidReason: dto.reason });
      }
      if (sent.length) {
        box.created.push(...(await this.createTickets(tx, b, sent, auth, true, now)));
        // Reverses the recipe deduction of each sent line (SALE_REVERSAL + WASTAGE, PLAN 1.4).
        await this.stock.reverseSale(tx, this.stockContext(auth, now, box.events), sent.map((i) => i.id), dto.reason);
        box.updated.push(...(await this.originalsTouching(tx, b.order.id, sent.map((i) => i.id))));
        await this.audit.record(tx, {
          tenantId: auth.tenantId,
          actorId: auth.userId,
          action: 'wastage',
          entity: 'OrderItem',
          entityId: null,
          metadata: { orderId: b.order.id, reason: dto.reason, items: sent.map((i) => i.productName) },
        });
      }
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.void_items',
        entity: 'Order',
        entityId: b.order.id,
        metadata: { itemIds: dto.itemIds, reason: dto.reason, approvalId: dto.approvalId ?? null },
      });
      await this.pricing.recalc(tx, b.order.id);
      box.orderChanged = true;
    });
    await after();
    return view;
  }

  /** Whole-order void. Only without payments. Order to VOID, table to FREE. */
  async voidOrder(orderId: string, dto: VoidOrderDto, auth: AuthUser) {
    const now = new Date();
    const { view, after } = await this.mutateWithOutbox(orderId, auth, async (tx, b, box) => {
      this.assertEditable(b.order);
      if (b.payments.some((p) => !p.amount.isZero())) {
        throw apiError(409, 'ORDER_HAS_PAYMENTS', 'Refund the payments before voiding this order');
      }
      await this.authoriseVoid(auth, dto.approvalId, { itemIds: 'order' }, b.order.id);

      const sent = b.items.filter((i) => i.status === 'SENT' || i.status === 'SERVED');
      if (sent.length) {
        box.created.push(...(await this.createTickets(tx, b, sent, auth, true, now)));
        await this.stock.reverseSale(tx, this.stockContext(auth, now, box.events), sent.map((i) => i.id), dto.reason);
        box.updated.push(...(await this.originalsTouching(tx, b.order.id, sent.map((i) => i.id))));
      }
      await this.repo.updateOrder(tx, b.order.id, { status: 'VOID', voidedAt: now, voidReason: dto.reason });
      if (b.order.tableId) await this.repo.setTableStatus(tx, b.order.tableId, 'FREE');
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.void',
        entity: 'Order',
        entityId: b.order.id,
        metadata: { reason: dto.reason, approvalId: dto.approvalId ?? null, sentItems: sent.length },
      });
      box.orderChanged = true;
    });
    await after();
    return view;
  }

  // ===========================================================================
  // Table moves, merges, transfers
  // ===========================================================================

  async move(orderId: string, dto: MoveOrderDto, auth: AuthUser): Promise<OrderView> {
    const { view } = await this.mutate(orderId, auth, async (tx, b) => {
      this.assertEditable(b.order);
      if (b.order.type !== 'DINE_IN') throw apiError(400, 'NOT_DINE_IN', 'Only dine-in orders have a table');
      const target = await this.repo.findTable(tx, dto.toTableId, auth.outletId);
      if (!target) throw apiError(404, 'TABLE_NOT_FOUND', 'Table not found');
      if (target.id === b.order.tableId) throw apiError(400, 'SAME_TABLE', 'The order is already on this table');
      if (target.seats < b.order.covers && !dto.force) {
        throw apiError(400, 'TABLE_TOO_SMALL', `${target.name} has ${target.seats} seats but there are ${b.order.covers} guests`, {
          seats: target.seats,
          covers: b.order.covers,
        });
      }
      const claimed = await this.repo.claimTable(tx, target.id, auth.outletId, ['FREE', 'RESERVED'], 'OCCUPIED');
      if (claimed === 0) throw apiError(409, 'TABLE_OCCUPIED', `${target.name} is in use`, { tableId: target.id });

      const from = b.order.tableId;
      if (from) await this.repo.setTableStatus(tx, from, 'FREE');
      await this.repo.updateOrder(tx, b.order.id, { tableId: target.id });
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.move',
        entity: 'Order',
        entityId: b.order.id,
        metadata: { fromTableId: from, toTableId: target.id, force: dto.force ?? false },
      });
    });
    return view;
  }

  /** Items and discounts of `fromOrderId` move here; the source order is voided and its table freed. */
  async merge(orderId: string, dto: MergeOrderDto, auth: AuthUser): Promise<OrderView> {
    if (dto.fromOrderId === orderId) throw apiError(400, 'SAME_ORDER', 'Cannot merge an order into itself');
    const { view } = await this.mutate(orderId, auth, async (tx, target) => {
      this.assertEditable(target.order);
      const source = await this.load(tx, dto.fromOrderId, auth);
      if (!OPEN_STATUSES.includes(source.order.status)) {
        throw apiError(409, 'ORDER_NOT_OPEN', 'The order to merge is not open', { status: source.order.status });
      }
      if (source.payments.some((p) => !p.amount.isZero())) {
        throw apiError(409, 'ORDER_HAS_PAYMENTS', 'Orders with payments cannot be merged');
      }

      await this.repo.moveAllItems(tx, source.order.id, target.order.id);
      await this.repo.moveAllDiscounts(tx, source.order.id, target.order.id);
      await this.repo.updateOrder(tx, source.order.id, {
        status: 'VOID',
        voidedAt: new Date(),
        voidReason: `merged into ${target.order.orderNumber}`,
      });
      if (source.order.tableId && source.order.tableId !== target.order.tableId) {
        await this.repo.setTableStatus(tx, source.order.tableId, 'FREE');
      }
      await this.pricing.recalc(tx, source.order.id);
      await this.pricing.recalc(tx, target.order.id);
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.merge',
        entity: 'Order',
        entityId: target.order.id,
        metadata: { fromOrderId: source.order.id, fromOrderNumber: source.order.orderNumber },
      });
    });
    return view;
  }

  /** Moves chosen lines to another open order, or to a new order on a free table. */
  async transferItems(orderId: string, dto: TransferItemsDto, auth: AuthUser): Promise<OrderView> {
    if (!dto.toOrderId && !dto.toTableId) throw apiError(400, 'TARGET_REQUIRED', 'Give toOrderId or toTableId');
    if (dto.toOrderId === orderId) throw apiError(400, 'SAME_ORDER', 'Items are already on this order');

    const { view } = await this.mutate(orderId, auth, async (tx, src) => {
      this.assertEditable(src.order);
      const moving = dto.itemIds.map((id) => {
        const item = src.items.find((i) => i.id === id);
        if (!item || item.status === 'VOIDED') throw apiError(400, 'ITEM_NOT_FOUND', 'Item not found on this order', { itemId: id });
        return item;
      });

      let dst: OrderBundle;
      if (dto.toOrderId) {
        dst = await this.load(tx, dto.toOrderId, auth);
        this.assertEditable(dst.order);
      } else {
        const claimed = await this.repo.claimTable(tx, dto.toTableId!, auth.outletId, ['FREE', 'RESERVED'], 'OCCUPIED');
        if (claimed === 0) throw apiError(409, 'TABLE_OCCUPIED', 'The target table is in use', { tableId: dto.toTableId });
        const orderNumber = await this.repo.nextOrderNumber(tx, auth.outletId);
        const created = await this.repo.createOrder(tx, {
          tenantId: auth.tenantId,
          outletId: auth.outletId,
          orderNumber,
          type: 'DINE_IN',
          status: 'OPEN',
          tableId: dto.toTableId!,
          covers: 1,
          waiterId: auth.userId,
          cashierId: auth.userId,
          subtotal: ZERO,
          taxAmount: ZERO,
          grandTotal: ZERO,
        });
        dst = await this.load(tx, created.id, auth);
      }

      const movedIds = moving.map((i) => i.id);
      await this.repo.moveItems(tx, movedIds, dst.order.id);
      // A line-level discount moves with its lines only when every line it names moved.
      const movingSet = new Set(movedIds);
      const discountIds = src.discounts
        .filter((d) => d.itemIds.length > 0 && d.itemIds.every((id) => movingSet.has(id)))
        .map((d) => d.id);
      if (discountIds.length) await this.repo.moveDiscounts(tx, discountIds, dst.order.id);

      await this.pricing.recalc(tx, src.order.id);
      await this.pricing.recalc(tx, dst.order.id);
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'order.transfer_items',
        entity: 'Order',
        entityId: src.order.id,
        metadata: { itemIds: movedIds, toOrderId: dst.order.id },
      });
    });
    return view;
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  /** Runs a mutation in one transaction, then returns the order view. */
  private async mutate(
    orderId: string,
    auth: AuthUser,
    fn: (tx: Prisma.TransactionClient, b: OrderBundle) => Promise<unknown>,
  ): Promise<{ view: OrderView }> {
    const view = await this.repo.transaction(async (tx) => {
      const b = await this.load(tx, orderId, auth);
      await fn(tx, b);
      return this.viewOf(tx, await this.load(tx, orderId, auth));
    });
    return { view };
  }

  /**
   * Like mutate, but collects an outbox. Tickets are printed and realtime messages sent only after the
   * transaction has committed. A rollback (for example TAB_LIMIT_REACHED) sends nothing.
   */
  private async mutateWithOutbox(
    orderId: string,
    auth: AuthUser,
    fn: (tx: Prisma.TransactionClient, b: OrderBundle, box: Outbox) => Promise<void>,
  ) {
    const box: Outbox = { created: [], updated: [], events: [], orderChanged: false };
    const view = await this.repo.transaction(async (tx) => {
      const b = await this.load(tx, orderId, auth);
      await fn(tx, b, box);
      return this.viewOf(tx, await this.load(tx, orderId, auth));
    });
    const after = async () => {
      for (const t of box.created) await this.printTicket(t);
      this.publishOutbox(auth, view, box, new Date());
    };
    return { view, box, after };
  }

  /** Sends the realtime side of an outbox: KDS cards, the stock and tab events, and the order status. */
  private publishOutbox(auth: AuthUser, view: OrderView, box: Outbox, now: Date): void {
    const ctx = contextFromView(view);
    const events: RealtimeEvent[] = [...box.events];
    for (const t of box.created) {
      if (!t.isCancellation) {
        events.push(stationEvent(auth.outletId, t.station, 'kds.ticket.created', toKdsTicket(t, ctx, now)));
      }
    }
    for (const t of box.updated) {
      events.push(stationEvent(auth.outletId, t.station, 'kds.ticket.updated', toKdsTicket(t, ctx, now)));
    }
    if (box.orderChanged) {
      events.push(outletEvent(auth.outletId, 'order.updated', { orderId: view.id, status: view.status }));
    }
    this.realtime.publish(events);
  }

  /** Context for the stock ledger. Its events are collected into the caller's outbox. */
  private stockContext(auth: AuthUser, now: Date, events: RealtimeEvent[]): MovementContext {
    return { tenantId: auth.tenantId, outletId: auth.outletId, userId: auth.userId, now, events };
  }

  /** Original tickets that carry any of the given order lines. */
  private async originalsTouching(tx: Prisma.TransactionClient, orderId: string, itemIds: string[]): Promise<Ticket[]> {
    const wanted = new Set(itemIds);
    const tickets = await this.repo.findOriginalTickets(tx, orderId);
    return tickets.filter((t) => readTicketItems(t.items).some((i) => wanted.has(i.orderItemId)));
  }

  private async printTicket(ticket: Ticket) {
    try {
      await this.print.queueTicket(ticket);
    } catch (e) {
      this.logger.warn(`Ticket ${ticket.id} could not be queued for printing: ${(e as Error).message}`);
    }
  }

  private async load(tx: Prisma.TransactionClient, orderId: string, auth: AuthUser): Promise<OrderBundle> {
    const b = await this.repo.loadBundle(tx, orderId);
    if (!b || (b.order.outletId && b.order.outletId !== auth.outletId)) {
      throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');
    }
    return b;
  }

  private async viewOf(tx: Prisma.TransactionClient, b: OrderBundle): Promise<OrderView> {
    return toOrderView(b, await this.repo.viewContext(tx, b));
  }

  private assertEditable(order: Order) {
    if (!EDITABLE_STATUSES.includes(order.status)) {
      throw apiError(409, 'ORDER_NOT_OPEN', 'This order is no longer open', { status: order.status });
    }
  }

  private itemOf(b: OrderBundle, itemId: string): OrderItem {
    const item = b.items.find((i) => i.id === itemId && i.status !== 'VOIDED');
    if (!item) throw apiError(404, 'ITEM_NOT_FOUND', 'Item not found on this order');
    return item;
  }

  /** Adds lines, prices them, and moves a billed order back to SENT and a billed table back to OCCUPIED. */
  private async addLines(tx: Prisma.TransactionClient, order: Order, items: AddItemDto[], auth: AuthUser, now: Date) {
    const ctx: LineContext = await this.lines.context(tx, order, now);
    const resolved: ResolvedLine[] = [];
    for (const dto of items) resolved.push(await this.lines.resolve(tx, dto, ctx));

    for (const line of resolved) {
      await this.repo.createItem(tx, {
        orderId: order.id,
        ...this.lineFields(line),
        quantity: line.quantity,
        seat: line.seat,
        note: line.note,
        status: 'NEW',
        createdById: auth.userId,
      } as Prisma.OrderItemUncheckedCreateInput);
    }
    await this.pricing.recalc(tx, order.id);
  }

  private async reopenBilled(tx: Prisma.TransactionClient, order: Order, auth: AuthUser) {
    if (order.status === 'BILLED') {
      await this.repo.updateOrder(tx, order.id, { status: 'SENT' });
      if (order.type === 'DINE_IN' && order.tableId) {
        await this.repo.claimTable(tx, order.tableId, auth.outletId, ['BILL_PRINTED'], 'OCCUPIED');
      }
    }
  }

  /** Fields a priced line stores. Shared by create, modifier edits and the legacy path. */
  private lineFields(line: ResolvedLine) {
    return {
      productId: line.productId,
      productName: line.productName,
      comboId: line.comboId,
      variantId: line.variantId,
      variantName: line.variantName,
      price: line.unitPrice,
      taxPercentage: D(line.snapshot.rate),
      taxAmount: ZERO,
      lineTotal: ZERO,
      grossAmount: ZERO,
      discountAmount: ZERO,
      modifiers: json(line.modifiers),
      happyHourPercent: line.happyHourPercent,
      taxClassId: line.taxClassId,
      taxBreakdown: json({ snapshot: line.snapshot, components: [] }),
    };
  }

  /** Rebuilds an AddItem for an existing line, keeping its product, variant, seat and note. */
  private asAddItem(item: OrderItem, modifierOptionIds: string[]): AddItemDto {
    return {
      productId: item.comboId ? undefined : (item.productId ?? undefined),
      comboId: item.comboId ?? undefined,
      variantId: item.variantId ?? undefined,
      quantity: item.quantity,
      seat: item.seat ?? undefined,
      note: item.note ?? undefined,
      modifierOptionIds,
    };
  }

  /** Approvers with APPROVE on sales.void go straight through. Others need an approved VOID for these items. */
  private async authoriseVoid(auth: AuthUser, approvalId: string | undefined, payload: { itemIds: string[] | 'order' }, orderId: string) {
    if (this.permissions.check(auth, 'sales.void', 'APPROVE')) return;
    if (!approvalId) {
      throw apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve this void', { required: 'APPROVE' });
    }
    await this.approvals.assertApproved(approvalId, auth, 'VOID', payload as Record<string, unknown>, orderId);
  }

  /**
   * One ticket per (kind, station) for the given lines. The sequence is per outlet per business day,
   * with the day starting at the 05:00 cut-off.
   */
  private async createTickets(
    tx: Prisma.TransactionClient,
    b: OrderBundle,
    items: OrderItem[],
    auth: AuthUser,
    cancellation: boolean,
    now: Date,
  ): Promise<Ticket[]> {
    const outletId = b.order.outletId ?? auth.outletId;
    const routing = await this.repo.routingFor(tx, [...new Set(items.map((i) => i.productId))]);
    const groups = new Map<string, { kind: TicketKind; station: string; items: OrderItem[] }>();
    for (const item of items) {
      const r = routing.get(item.productId ?? '') ?? { station: 'KITCHEN', ticketKind: 'KOT' };
      const key = `${r.ticketKind}|${r.station}`;
      const g = groups.get(key) ?? { kind: r.ticketKind as TicketKind, station: r.station, items: [] };
      g.items.push(item);
      groups.set(key, g);
    }

    const tz = await this.repo.getOutletTimezone(outletId);
    const dayStart = dayWindow(businessDateFor(now, tz, '05:00'), tz).start;
    let seq = await this.repo.countTicketsSince(tx, outletId, dayStart);

    const tickets: Ticket[] = [];
    for (const g of groups.values()) {
      seq += 1;
      tickets.push(
        await this.repo.createTicket(tx, {
          tenantId: auth.tenantId,
          outletId,
          orderId: b.order.id,
          kind: g.kind,
          station: g.station,
          seq,
          isCancellation: cancellation,
          items: json(
            g.items.map((i) => ({
              orderItemId: i.id,
              name: i.productName,
              variantName: i.variantName,
              quantity: i.quantity,
              modifiers: readModifiers(i.modifiers).map((m) => m.name),
              note: i.note,
              seat: i.seat,
            })),
          ),
          createdById: auth.userId,
        }),
      );
    }
    return tickets;
  }
}

