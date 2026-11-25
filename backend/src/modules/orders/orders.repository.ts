import { Injectable } from '@nestjs/common';
import { OrderStatus, Prisma, TableStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { OPEN_STATUSES } from './order-pricing';
import { OrderBundle, ViewContext } from './order-view';

export interface OutletSettingsView {
  serviceChargePercent: Prisma.Decimal;
  serviceChargeTypes: string[];
  roundingMode: 'NONE' | 'NEAREST_1';
  orderPrefix: string;
  invoicePrefix: string;
  countryCode: string;
}

const DEFAULT_SETTINGS: OutletSettingsView = {
  serviceChargePercent: new Prisma.Decimal(0),
  serviceChargeTypes: ['DINE_IN'],
  roundingMode: 'NEAREST_1',
  orderPrefix: 'A',
  invoicePrefix: 'INV',
  countryCode: 'IN',
};

/** Data access for orders, their lines, discounts, tickets and the tables they sit on. */
@Injectable()
export class OrdersRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  // ---------------------------------------------------------------------------
  // Legacy search (GET /orders)
  // ---------------------------------------------------------------------------

  findAll(where: Prisma.OrderWhereInput, skip: number, take: number) {
    return this.prisma.$transaction([
      this.prisma.order.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: 'desc' },
        include: { cashier: { select: { username: true } } },
      }),
      this.prisma.order.count({ where }),
    ]);
  }

  findProductsByIds(ids: string[]) {
    return this.prisma.product.findMany({
      where: { id: { in: ids }, deletedAt: null, isActive: true },
    });
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------

  /** The order with its lines, discounts and payments. Relation fields are not used: each is a scalar query. */
  async loadBundle(tx: Prisma.TransactionClient, orderId: string): Promise<OrderBundle | null> {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) return null;
    const [items, discounts, payments] = await Promise.all([
      tx.orderItem.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } }),
      tx.orderDiscount.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } }),
      tx.payment.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } }),
    ]);
    return { order, items, discounts, payments };
  }

  findOrderByOfflineId(tx: Prisma.TransactionClient, offlineId: string) {
    return tx.order.findUnique({ where: { offlineId } });
  }

  openOrders(outletId: string) {
    return this.prisma.order.findMany({
      where: { outletId, status: { in: OPEN_STATUSES as OrderStatus[] } },
      orderBy: { createdAt: 'asc' },
    });
  }

  createOrder(tx: Prisma.TransactionClient, data: Prisma.OrderUncheckedCreateInput) {
    return tx.order.create({ data });
  }

  updateOrder(tx: Prisma.TransactionClient, id: string, data: Prisma.OrderUncheckedUpdateInput) {
    return tx.order.update({ where: { id }, data });
  }

  /** Next order number for the outlet, e.g. "A-1044". Call inside the transaction that creates the order. */
  async nextOrderNumber(tx: Prisma.TransactionClient, outletId: string): Promise<string> {
    await tx.outletSettings.upsert({ where: { outletId }, create: { outletId }, update: {} });
    const s = await tx.outletSettings.update({
      where: { outletId },
      data: { lastOrderSeq: { increment: 1 } },
      select: { orderPrefix: true, lastOrderSeq: true },
    });
    return `${s.orderPrefix}-${s.lastOrderSeq}`;
  }

  async getOutletSettings(tx: Prisma.TransactionClient, outletId: string | null): Promise<OutletSettingsView> {
    if (!outletId) return DEFAULT_SETTINGS;
    const row = await tx.outletSettings.findUnique({ where: { outletId } });
    return row ? { ...row, serviceChargeTypes: row.serviceChargeTypes as string[] } : DEFAULT_SETTINGS;
  }

  async getOutletTimezone(outletId: string): Promise<string> {
    const outlet = await this.prisma.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
    return outlet?.timezone ?? 'Asia/Kolkata';
  }

  // ---------------------------------------------------------------------------
  // Lines and discounts
  // ---------------------------------------------------------------------------

  createItem(tx: Prisma.TransactionClient, data: Prisma.OrderItemUncheckedCreateInput) {
    return tx.orderItem.create({ data });
  }

  updateItem(tx: Prisma.TransactionClient, id: string, data: Prisma.OrderItemUncheckedUpdateInput) {
    return tx.orderItem.update({ where: { id }, data });
  }

  deleteItem(tx: Prisma.TransactionClient, id: string) {
    return tx.orderItem.delete({ where: { id } });
  }

  findTableById(tx: Prisma.TransactionClient, id: string) {
    return tx.diningTable.findUnique({ where: { id } });
  }

  moveItems(tx: Prisma.TransactionClient, itemIds: string[], toOrderId: string) {
    return tx.orderItem.updateMany({ where: { id: { in: itemIds } }, data: { orderId: toOrderId } });
  }

  moveAllItems(tx: Prisma.TransactionClient, fromOrderId: string, toOrderId: string) {
    return tx.orderItem.updateMany({ where: { orderId: fromOrderId }, data: { orderId: toOrderId } });
  }

  createDiscount(tx: Prisma.TransactionClient, data: Prisma.OrderDiscountUncheckedCreateInput) {
    return tx.orderDiscount.create({ data });
  }

  updateDiscount(tx: Prisma.TransactionClient, id: string, data: Prisma.OrderDiscountUncheckedUpdateInput) {
    return tx.orderDiscount.update({ where: { id }, data });
  }

  findDiscount(tx: Prisma.TransactionClient, id: string, orderId: string) {
    return tx.orderDiscount.findFirst({ where: { id, orderId } });
  }

  deleteDiscount(tx: Prisma.TransactionClient, id: string) {
    return tx.orderDiscount.delete({ where: { id } });
  }

  moveDiscounts(tx: Prisma.TransactionClient, ids: string[], toOrderId: string) {
    return tx.orderDiscount.updateMany({ where: { id: { in: ids } }, data: { orderId: toOrderId } });
  }

  moveAllDiscounts(tx: Prisma.TransactionClient, fromOrderId: string, toOrderId: string) {
    return tx.orderDiscount.updateMany({ where: { orderId: fromOrderId }, data: { orderId: toOrderId } });
  }

  // ---------------------------------------------------------------------------
  // Catalogue reads used when a line is added
  // ---------------------------------------------------------------------------

  findProduct(tx: Prisma.TransactionClient, id: string) {
    return tx.product.findFirst({ where: { id, isActive: true, deletedAt: null } });
  }

  findProductsFull(tx: Prisma.TransactionClient, ids: string[]) {
    return tx.product.findMany({ where: { id: { in: ids } } });
  }

  findVariant(tx: Prisma.TransactionClient, id: string, productId: string) {
    return tx.productVariant.findFirst({ where: { id, productId, isActive: true } });
  }

  async productModifierGroupIds(tx: Prisma.TransactionClient, productId: string): Promise<string[]> {
    const rows = await tx.productModifierGroup.findMany({ where: { productId }, orderBy: { sortOrder: 'asc' } });
    return rows.map((r) => r.groupId);
  }

  modifierGroupsWithOptions(tx: Prisma.TransactionClient, groupIds: string[]) {
    return tx.modifierGroup.findMany({
      where: { id: { in: groupIds }, isActive: true },
      include: { options: { where: { isActive: true } } },
    });
  }

  findCombo(tx: Prisma.TransactionClient, id: string) {
    return tx.combo.findFirst({ where: { id, isActive: true }, include: { items: true } });
  }

  findCategory(tx: Prisma.TransactionClient, id: string) {
    return tx.category.findFirst({ where: { id } });
  }

  findTaxClass(tx: Prisma.TransactionClient, id: string) {
    return tx.taxClass.findFirst({ where: { id, isActive: true } });
  }

  findActivePriceRules(tx: Prisma.TransactionClient, outletId: string) {
    return tx.priceRule.findMany({
      where: { isActive: true, OR: [{ outletId: null }, { outletId }] },
    });
  }

  // ---------------------------------------------------------------------------
  // Tables and areas
  // ---------------------------------------------------------------------------

  findTable(tx: Prisma.TransactionClient, id: string, outletId: string) {
    return tx.diningTable.findFirst({ where: { id, outletId, isActive: true } });
  }

  findArea(tx: Prisma.TransactionClient, id: string) {
    return tx.area.findFirst({ where: { id } });
  }

  /** Moves a table to `to` only if it is currently in one of `from`. Returns the number of rows changed (0 or 1). */
  async claimTable(
    tx: Prisma.TransactionClient,
    id: string,
    outletId: string,
    from: TableStatus[],
    to: TableStatus,
  ): Promise<number> {
    const res = await tx.diningTable.updateMany({
      where: { id, outletId, status: { in: from } },
      data: { status: to },
    });
    return res.count;
  }

  setTableStatus(tx: Prisma.TransactionClient, id: string, status: TableStatus) {
    return tx.diningTable.update({ where: { id }, data: { status } });
  }

  // ---------------------------------------------------------------------------
  // Tickets
  // ---------------------------------------------------------------------------

  createTicket(tx: Prisma.TransactionClient, data: Prisma.TicketUncheckedCreateInput) {
    return tx.ticket.create({ data });
  }

  countTicketsSince(tx: Prisma.TransactionClient, outletId: string, since: Date) {
    return tx.ticket.count({ where: { outletId, createdAt: { gte: since } } });
  }

  // ---------------------------------------------------------------------------
  // View context: routing, table, waiter and approver names
  // ---------------------------------------------------------------------------

  async viewContext(tx: Prisma.TransactionClient, b: OrderBundle): Promise<ViewContext> {
    const productIds = [...new Set(b.items.map((i) => i.productId))];
    const routing = await this.routingFor(tx, productIds);

    let table: ViewContext['table'] = null;
    if (b.order.tableId) {
      const t = await tx.diningTable.findUnique({ where: { id: b.order.tableId } });
      if (t) {
        const area = await tx.area.findUnique({ where: { id: t.areaId } });
        table = { id: t.id, name: t.name, areaName: area?.name ?? '' };
      }
    }

    const userIds = [
      ...new Set([b.order.waiterId, ...b.discounts.map((d) => d.approvedById)].filter((x): x is string => !!x)),
    ];
    const users = userIds.length
      ? await tx.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true, username: true } })
      : [];
    const userNames = new Map(users.map((u) => [u.id, u.displayName ?? u.username]));
    const waiter = b.order.waiterId && userNames.has(b.order.waiterId)
      ? { id: b.order.waiterId, name: userNames.get(b.order.waiterId)! }
      : null;

    return { routing, table, waiter, userNames };
  }

  /** productId -> station and ticket kind from the product's category. Missing products get the kitchen default. */
  async routingFor(tx: Prisma.TransactionClient, productIds: string[]) {
    const products = productIds.length
      ? await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, categoryId: true } })
      : [];
    const catIds = [...new Set(products.map((p) => p.categoryId).filter((x): x is string => !!x))];
    const cats = catIds.length
      ? await tx.category.findMany({ where: { id: { in: catIds } }, select: { id: true, station: true, ticketKind: true } })
      : [];
    const catById = new Map(cats.map((c) => [c.id, c]));
    const out = new Map<string, { station: string; ticketKind: string }>();
    for (const p of products) {
      const c = p.categoryId ? catById.get(p.categoryId) : undefined;
      out.set(p.id, { station: c?.station ?? 'KITCHEN', ticketKind: c?.ticketKind ?? 'KOT' });
    }
    return out;
  }
}
