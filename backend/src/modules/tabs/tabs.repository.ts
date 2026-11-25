import { Injectable } from '@nestjs/common';
import { BarTab, Prisma, TabStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { TabRows } from './tab-view';

type Db = Prisma.TransactionClient;

/** Data access for bar tabs. Also reads the order, table and user rows a TabView needs. */
@Injectable()
export class TabsRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  findTab(id: string, outletId: string, db: Db = this.prisma): Promise<BarTab | null> {
    return db.barTab.findFirst({ where: { id, outletId } });
  }

  /** The OPEN tab that sits on this order, or null. Orders without an open tab skip the limit rules. */
  findOpenTabByOrder(tx: Db, orderId: string): Promise<BarTab | null> {
    return tx.barTab.findFirst({ where: { orderId, status: TabStatus.OPEN } });
  }

  listTabs(outletId: string, where: { status?: TabStatus; businessDate?: Date; openedById?: string }): Promise<BarTab[]> {
    return this.prisma.barTab.findMany({
      where: {
        outletId,
        ...(where.status ? { status: where.status } : {}),
        ...(where.businessDate ? { businessDate: where.businessDate } : {}),
        ...(where.openedById ? { openedById: where.openedById } : {}),
      },
      orderBy: { openedAt: 'asc' },
    });
  }

  countTabsOn(tx: Db, outletId: string, businessDate: Date): Promise<number> {
    return tx.barTab.count({ where: { outletId, businessDate } });
  }

  createTab(tx: Db, data: Prisma.BarTabUncheckedCreateInput): Promise<BarTab> {
    return tx.barTab.create({ data });
  }

  updateTab(tx: Db, id: string, data: Prisma.BarTabUncheckedUpdateInput): Promise<BarTab> {
    return tx.barTab.update({ where: { id }, data });
  }

  /** Grand total of the tab's order as it stands inside this transaction. */
  async orderGrandTotal(tx: Db, orderId: string): Promise<Prisma.Decimal | null> {
    const row = await tx.order.findUnique({ where: { id: orderId }, select: { grandTotal: true } });
    return row ? row.grandTotal : null;
  }

  createNotification(tx: Db, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }

  /** TabRows read outside a transaction. */
  rowsFor(tabs: BarTab[]): Promise<TabRows[]> {
    return this.loadRows(this.prisma, tabs);
  }

  /** Orders, lines, tables and openers for a set of tabs, shaped for toTabView. Tabs without an order are dropped. */
  async loadRows(db: Db, tabs: BarTab[]): Promise<TabRows[]> {
    if (tabs.length === 0) return [];
    const orderIds = tabs.map((t) => t.orderId);

    const orders = await db.order.findMany({ where: { id: { in: orderIds } } });
    const orderById = new Map(orders.map((o) => [o.id, o]));

    const lines = await db.orderItem.findMany({
      where: { orderId: { in: orderIds }, status: { not: 'VOIDED' } },
      select: { orderId: true },
    });
    const counts = new Map<string, number>();
    for (const line of lines) counts.set(line.orderId, (counts.get(line.orderId) ?? 0) + 1);

    const tableIds = [...new Set(orders.map((o) => o.tableId).filter((x): x is string => !!x))];
    const tables = tableIds.length
      ? await db.diningTable.findMany({ where: { id: { in: tableIds } }, select: { id: true, name: true } })
      : [];
    const tableById = new Map(tables.map((t) => [t.id, t]));

    const userIds = [...new Set(tabs.map((t) => t.openedById))];
    const users = await db.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, displayName: true, username: true },
    });
    const userById = new Map(users.map((u) => [u.id, u.displayName ?? u.username]));

    return tabs.flatMap((tab) => {
      const order = orderById.get(tab.orderId);
      if (!order) return [];
      const table = order.tableId ? tableById.get(order.tableId) ?? null : null;
      const name = userById.get(tab.openedById);
      return [
        {
          tab,
          order,
          table,
          opener: name !== undefined ? { id: tab.openedById, name } : null,
          itemCount: counts.get(tab.orderId) ?? 0,
        },
      ];
    });
  }
}
