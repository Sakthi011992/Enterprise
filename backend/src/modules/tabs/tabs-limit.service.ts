import { Injectable } from '@nestjs/common';
import { BarTab, Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { RealtimeEvent, outletEvent } from '../realtime/realtime.types';
import { money } from '../orders/order-pricing';
import { isNearLimit, wholePercent } from './tab-math';
import { TabsRepository } from './tabs.repository';
import { toTabView } from './tab-view';

type Db = Prisma.TransactionClient;

/**
 * The tab rules that orders and payments need. It depends only on TabsRepository, so OrdersModule and
 * PaymentsModule can import it without a module cycle (the full TabsService needs both of them).
 */
@Injectable()
export class TabsLimitService {
  constructor(private repo: TabsRepository) {}

  /** The OPEN tab on an order, or null. */
  tabForOrder(tx: Db, orderId: string): Promise<BarTab | null> {
    return this.repo.findOpenTabByOrder(tx, orderId);
  }

  /**
   * Runs inside an order mutation, after re-pricing (PLAN 1.7 tab limit enforcement). Throws
   * 409 TAB_LIMIT_REACHED when the new total is above the limit, which rolls the mutation back. Crossing
   * the warning level for the first time sets warnedAt, notifies the opener, and returns a tab.nearLimit
   * event for the caller to publish after commit.
   */
  async enforce(tx: Db, orderId: string, spentBefore: Prisma.Decimal, now: Date): Promise<RealtimeEvent[]> {
    const tab = await this.repo.findOpenTabByOrder(tx, orderId);
    if (!tab) return [];

    const attempted = (await this.repo.orderGrandTotal(tx, orderId)) ?? new Prisma.Decimal(0);
    const limit = new Prisma.Decimal(tab.tabLimit);
    if (attempted.greaterThan(limit)) {
      throw apiError(409, 'TAB_LIMIT_REACHED', `Tab ${tab.number} has reached its limit of ${money(limit)}`, {
        tabId: tab.id,
        number: tab.number,
        limit: money(limit),
        spent: money(spentBefore),
        attempted: money(attempted),
      });
    }

    if (tab.warnedAt || !isNearLimit(attempted, limit, tab.warnAtPercent)) return [];

    await this.repo.updateTab(tx, tab.id, { warnedAt: now });
    const pct = wholePercent(attempted, limit);
    await this.repo.createNotification(tx, {
      tenantId: tab.tenantId,
      outletId: tab.outletId,
      userId: tab.openedById,
      type: 'alert',
      title: `Tab ${tab.number} is at ${pct}% of its ₹${limit.toNumber().toLocaleString('en-IN')} limit`,
      body: null,
      data: { tabId: tab.id, orderId },
    });
    const rows = await this.repo.loadRows(tx, [{ ...tab, warnedAt: now }]);
    return rows.map((r) => outletEvent(tab.outletId, 'tab.nearLimit', toTabView(r)));
  }

  /**
   * Called by PaymentsService when an order is fully paid. The tab closes, and the bill is not
   * reopened. Does nothing for orders without an OPEN tab.
   */
  async onOrderPaid(tx: Db, orderId: string, now: Date = new Date()): Promise<void> {
    const tab = await this.repo.findOpenTabByOrder(tx, orderId);
    if (!tab) return;
    await this.repo.updateTab(tx, tab.id, { status: 'CLOSED', closedAt: now });
  }
}
