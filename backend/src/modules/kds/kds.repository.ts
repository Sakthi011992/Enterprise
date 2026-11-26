import { Injectable } from '@nestjs/common';
import { KdsStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { KdsOrderContext } from './kds-view';

type Db = Prisma.TransactionClient;

const ACTIVE: KdsStatus[] = [KdsStatus.NEW, KdsStatus.PREPARING, KdsStatus.READY];

/** Data access for the kitchen display: tickets, the order facts on each card, and the KDS writes. */
@Injectable()
export class KdsRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  async outletTimezone(outletId: string): Promise<string> {
    const outlet = await this.prisma.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
    return outlet?.timezone ?? 'Asia/Kolkata';
  }

  findTicket(tx: Db, id: string, outletId: string) {
    return tx.ticket.findFirst({ where: { id, outletId, isCancellation: false } });
  }

  /** Cards on the board: NEW, PREPARING and READY tickets, oldest first. */
  activeTickets(outletId: string, station?: string) {
    return this.prisma.ticket.findMany({
      where: { outletId, isCancellation: false, kdsStatus: { in: ACTIVE }, ...(station ? { station } : {}) },
      orderBy: { createdAt: 'asc' },
    });
  }

  /** Done cards: SERVED tickets served since `since`. */
  servedSince(outletId: string, since: Date, station?: string) {
    return this.prisma.ticket.findMany({
      where: {
        outletId,
        isCancellation: false,
        kdsStatus: 'SERVED',
        servedAt: { gte: since },
        ...(station ? { station } : {}),
      },
      orderBy: { servedAt: 'desc' },
    });
  }

  /** Every ticket of a business day, for the all-day totals and the average. */
  dayTickets(outletId: string, start: Date, end: Date, station?: string) {
    return this.prisma.ticket.findMany({
      where: { outletId, isCancellation: false, createdAt: { gte: start, lt: end }, ...(station ? { station } : {}) },
    });
  }

  readyTickets(outletId: string) {
    return this.prisma.ticket.findMany({
      where: { outletId, isCancellation: false, kdsStatus: 'READY' },
      orderBy: { readyAt: 'asc' },
    });
  }

  /**
   * Order facts for the cards of these orders: table, waiter, tab number and each line's status.
   * Pass a transaction client when reading inside one.
   */
  async loadContext(orderIds: string[], db: Db = this.prisma): Promise<Map<string, KdsOrderContext>> {
    const unique = [...new Set(orderIds)];
    const out = new Map<string, KdsOrderContext>();
    if (unique.length === 0) return out;

    const orders = await db.order.findMany({
      where: { id: { in: unique } },
      include: { table: true, waiter: { select: { displayName: true, username: true } } },
    });
    const items = await db.orderItem.findMany({
      where: { orderId: { in: unique } },
      select: { id: true, orderId: true, status: true },
    });
    const tabs = await db.barTab.findMany({
      where: { orderId: { in: unique } },
      select: { orderId: true, number: true },
    });

    const itemStatus = new Map<string, Map<string, string>>();
    for (const i of items) {
      const m = itemStatus.get(i.orderId) ?? new Map<string, string>();
      m.set(i.id, i.status);
      itemStatus.set(i.orderId, m);
    }
    const tabNumber = new Map(tabs.map((t) => [t.orderId, t.number]));

    for (const o of orders) {
      out.set(o.id, {
        id: o.id,
        orderNumber: o.orderNumber,
        type: o.type,
        covers: o.covers,
        tableName: o.table?.name ?? null,
        tabNumber: tabNumber.get(o.id) ?? null,
        waiterId: o.waiterId,
        waiterName: o.waiter ? o.waiter.displayName ?? o.waiter.username : null,
        itemStatus: itemStatus.get(o.id) ?? new Map<string, string>(),
        source: o.source,
      });
    }
    return out;
  }

  updateTicket(tx: Db, id: string, data: Prisma.TicketUncheckedUpdateInput) {
    return tx.ticket.update({ where: { id }, data });
  }

  /** Lines of a served ticket move from SENT to SERVED. Voided lines are not touched. */
  markItemsServed(tx: Db, itemIds: string[]) {
    if (itemIds.length === 0) return Promise.resolve({ count: 0 });
    return tx.orderItem.updateMany({ where: { id: { in: itemIds }, status: 'SENT' }, data: { status: 'SERVED' } });
  }

  createNotification(tx: Db, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }

  /** READY tickets bumped before `before` that have not been alerted yet. All outlets (the overdue job). */
  overdueReady(before: Date) {
    return this.prisma.ticket.findMany({
      where: { kdsStatus: 'READY', readyAt: { lt: before }, overdueAlertedAt: null, isCancellation: false },
      take: 200,
    });
  }

  markOverdueAlerted(tx: Db, id: string, at: Date) {
    return tx.ticket.update({ where: { id }, data: { overdueAlertedAt: at } });
  }

  /** Distinct station values of the tenant's active categories. */
  async categoryStations(tenantId: string): Promise<string[]> {
    const rows = await this.prisma.category.findMany({
      where: { tenantId, isActive: true },
      distinct: ['station'],
      select: { station: true },
      orderBy: { station: 'asc' },
    });
    return rows.map((r) => r.station);
  }
}
