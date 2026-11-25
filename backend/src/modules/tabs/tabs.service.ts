import { Injectable } from '@nestjs/common';
import { BarTab, PaymentMethod, Prisma, TabStatus } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { ApprovalsService } from '../approvals/approvals.service';
import { D, ZERO, money } from '../orders/order-pricing';
import { OrdersRepository } from '../orders/orders.repository';
import { OrdersService } from '../orders/orders.service';
import { PaymentsService } from '../payments/payments.service';
import { PermissionsService } from '../personas/permissions.service';
import { MoveTabDto, OpenTabDto, TabQueryDto, UpdateTabDto, VoidTabDto } from './dto/tab.dto';
import { depositSplit, heldFor, tabNumber, tabSecurityError } from './tab-math';
import { TabView, toTabView } from './tab-view';
import { TabsRepository } from './tabs.repository';

const SECURITY_MESSAGES: Record<string, string> = {
  AGE_CHECK_REQUIRED: 'Check the guest is of legal age before opening a tab',
  CARD_LAST4_REQUIRED: 'Enter the last four digits of the card',
  DEPOSIT_REQUIRED: 'A cash deposit needs an amount above zero',
  HOUSE_ACCOUNT_REQUIRED: 'Name the house account',
};

/**
 * Bar tabs: open, list, change the limit, move to a table, close (bill and apply a cash deposit) and void.
 * Paying the order and the 80/90 % warning both live in the orders and payments paths (TabsLimitService).
 */
@Injectable()
export class TabsService {
  constructor(
    private repo: TabsRepository,
    private orders: OrdersService,
    private ordersRepo: OrdersRepository,
    private payments: PaymentsService,
    private approvals: ApprovalsService,
    private permissions: PermissionsService,
    private audit: AuditTrailService,
  ) {}

  /**
   * GET /tabs. Counts cover today's business date (open, near limit, closed today). Items follow
   * `scope` (default today) and the optional filters.
   */
  async list(q: TabQueryDto, auth: AuthUser) {
    const tz = await this.ordersRepo.getOutletTimezone(auth.outletId);
    const today = toDateOnly(businessDateFor(new Date(), tz, '05:00'));
    const todayTabs = await this.repo.listTabs(auth.outletId, { businessDate: today });
    const openToday = todayTabs.filter((t) => t.status === TabStatus.OPEN);
    const nearLimit = (await this.repo.rowsFor(openToday)).map(toTabView).filter((v) => v.nearLimit).length;

    const scoped =
      q.scope === 'all'
        ? await this.repo.listTabs(auth.outletId, {
            status: q.status as TabStatus | undefined,
            openedById: q.openedById,
          })
        : todayTabs.filter(
            (t) => (!q.status || t.status === q.status) && (!q.openedById || t.openedById === q.openedById),
          );

    const items = (await this.repo.rowsFor(scoped)).map(toTabView);
    return {
      counts: {
        open: openToday.length,
        nearLimit,
        closedToday: todayTabs.filter((t) => t.status === TabStatus.CLOSED).length,
      },
      items,
    };
  }

  /** GET /tabs/:id, with the order (lines, totals, payments). */
  async findOne(id: string, auth: AuthUser) {
    const tab = await this.mustFind(id, auth);
    const view = await this.viewOf(tab);
    const order = await this.orders.findOne(tab.orderId, auth);
    return { ...view, order };
  }

  /**
   * POST /tabs. Checks age, security, then the limit (sales.tab.open LIMITED), then the approval for a tab
   * with no security. Creates the BAR_COUNTER order (DINE_IN when linked to a table) and the tab in one
   * transaction.
   */
  async open(dto: OpenTabDto, auth: AuthUser): Promise<TabView> {
    const securityCode = tabSecurityError({
      ageChecked: dto.ageChecked,
      security: dto.security,
      cardLast4: dto.cardLast4,
      amountHeld: dto.amountHeld,
      houseAccount: dto.houseAccount,
    });
    if (securityCode) throw apiError(400, securityCode, SECURITY_MESSAGES[securityCode]);
    if (dto.linkType === 'TABLE' && !dto.tableId) throw apiError(400, 'TABLE_REQUIRED', 'A table link needs a table');

    this.permissions.assertWithinLimit(auth, 'sales.tab.open', dto.tabLimit);
    if (dto.security === 'NONE' && !this.permissions.check(auth, 'sales.tab.open', 'APPROVE')) {
      if (!dto.approvalId) {
        throw apiError(403, 'APPROVAL_REQUIRED', 'A manager must approve a tab with no security', { required: 'APPROVE' });
      }
      await this.approvals.assertApproved(
        dto.approvalId,
        auth,
        'TAB_NO_SECURITY',
        { guestName: dto.guestName, tabLimit: dto.tabLimit },
        null,
      );
    }

    const now = new Date();
    const tz = await this.ordersRepo.getOutletTimezone(auth.outletId);
    const businessDate = toDateOnly(businessDateFor(now, tz, '05:00'));
    const onTable = dto.linkType === 'TABLE';
    const held = heldFor(dto.security, dto.amountHeld);

    return this.repo.transaction(async (tx) => {
      const seq = (await this.repo.countTabsOn(tx, auth.outletId, businessDate)) + 1;
      const number = tabNumber(seq);

      if (onTable) {
        const claimed = await this.ordersRepo.claimTable(tx, dto.tableId!, auth.outletId, ['FREE', 'RESERVED'], 'OCCUPIED');
        if (claimed === 0) throw apiError(409, 'TABLE_OCCUPIED', 'This table is in use', { tableId: dto.tableId });
      }

      const orderNumber = await this.ordersRepo.nextOrderNumber(tx, auth.outletId);
      const order = await this.ordersRepo.createOrder(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        orderNumber,
        type: onTable ? 'DINE_IN' : 'BAR_COUNTER',
        status: 'OPEN',
        tableId: onTable ? dto.tableId! : null,
        covers: 1,
        waiterId: auth.userId,
        cashierId: auth.userId,
        note: `Tab ${number} · ${dto.guestName.trim()}`,
        subtotal: ZERO,
        taxAmount: ZERO,
        grandTotal: ZERO,
        invoiceNumber: null,
      });

      const tab = await this.repo.createTab(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        number,
        businessDate,
        orderId: order.id,
        guestName: dto.guestName.trim(),
        mobile: dto.mobile ?? null,
        ageChecked: true,
        security: dto.security,
        cardLast4: dto.security === 'CARD_PREAUTH' ? dto.cardLast4! : null,
        amountHeld: held,
        houseAccount: dto.security === 'HOUSE_ACCOUNT' ? dto.houseAccount!.trim() : null,
        tabLimit: D(dto.tabLimit),
        warnAtPercent: dto.warnAtPercent ?? 80,
        linkType: dto.linkType,
        linkLabel: dto.linkLabel ?? null,
        tableId: onTable ? dto.tableId! : null,
        approvalId: dto.security === 'NONE' ? dto.approvalId ?? null : null,
        openedById: auth.userId,
        openedAt: now,
      });

      const rows = await this.repo.loadRows(tx, [tab]);
      if (!rows[0]) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
      return toTabView(rows[0]);
    });
  }

  /**
   * PUT /tabs/:id. A new limit goes through the same LIMITED check as opening. Raising it re-arms the
   * warning. A tab on a table must be moved with move-to-table, not relinked here.
   */
  async update(id: string, dto: UpdateTabDto, auth: AuthUser): Promise<TabView> {
    const tab = await this.mustFind(id, auth);
    this.assertOpen(tab);
    if (dto.tabLimit !== undefined) this.permissions.assertWithinLimit(auth, 'sales.tab.open', dto.tabLimit);
    if (dto.linkType !== undefined && tab.linkType === 'TABLE') {
      throw apiError(409, 'TAB_ON_TABLE', 'Free the table first, or use move-to-table', { tableId: tab.tableId });
    }
    if (dto.linkType === undefined && dto.linkLabel === undefined && dto.tabLimit === undefined && dto.guestName === undefined && dto.mobile === undefined && dto.warnAtPercent === undefined) {
      return this.viewOf(tab);
    }

    const data: Prisma.BarTabUncheckedUpdateInput = {};
    if (dto.guestName !== undefined) data.guestName = dto.guestName.trim();
    if (dto.mobile !== undefined) data.mobile = dto.mobile || null;
    if (dto.warnAtPercent !== undefined) data.warnAtPercent = dto.warnAtPercent;
    if (dto.tabLimit !== undefined) {
      data.tabLimit = D(dto.tabLimit);
      data.warnedAt = null;
    }
    if (dto.linkType !== undefined) data.linkType = dto.linkType;
    if (dto.linkLabel !== undefined) data.linkLabel = dto.linkLabel || null;

    return this.repo.transaction(async (tx) => {
      const updated = await this.repo.updateTab(tx, tab.id, data);
      const rows = await this.repo.loadRows(tx, [updated]);
      if (!rows[0]) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
      return toTabView(rows[0]);
    });
  }

  /** POST /tabs/:id/move-to-table. The order becomes DINE_IN on the table; the old table is freed. */
  async moveToTable(id: string, dto: MoveTabDto, auth: AuthUser): Promise<TabView> {
    const tab = await this.mustFind(id, auth);
    this.assertOpen(tab);

    return this.repo.transaction(async (tx) => {
      const bundle = await this.ordersRepo.loadBundle(tx, tab.orderId);
      if (!bundle) throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');
      const target = await this.ordersRepo.findTable(tx, dto.tableId, auth.outletId);
      if (!target) throw apiError(404, 'TABLE_NOT_FOUND', 'Table not found');
      if (bundle.order.tableId === target.id) throw apiError(400, 'SAME_TABLE', 'The tab is already on this table');

      const claimed = await this.ordersRepo.claimTable(tx, target.id, auth.outletId, ['FREE', 'RESERVED'], 'OCCUPIED');
      if (claimed === 0) throw apiError(409, 'TABLE_OCCUPIED', `${target.name} is in use`, { tableId: target.id });
      if (bundle.order.tableId) await this.ordersRepo.setTableStatus(tx, bundle.order.tableId, 'FREE');

      await this.ordersRepo.updateOrder(tx, tab.orderId, { type: 'DINE_IN', tableId: target.id });
      const updated = await this.repo.updateTab(tx, tab.id, { linkType: 'TABLE', linkLabel: target.name, tableId: target.id });
      const rows = await this.repo.loadRows(tx, [updated]);
      if (!rows[0]) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
      return toTabView(rows[0]);
    });
  }

  /**
   * POST /tabs/:id/close. Bills the order. A cash deposit is applied as a CASH payment for
   * min(held, total), and the rest is returned to the guest. The tab closes when the order is fully paid
   * (here if the deposit covers it, otherwise when PaymentsService settles it).
   */
  async close(id: string, auth: AuthUser) {
    const tab = await this.mustFind(id, auth);
    this.assertOpen(tab);
    const [row] = await this.repo.rowsFor([tab]);
    if (!row) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
    if (row.itemCount === 0) throw apiError(400, 'TAB_EMPTY', 'The tab has no items to bill');

    const billed = await this.orders.bill(tab.orderId, {}, auth);
    const grand = D(billed.totals.grandTotal);

    let applied = ZERO;
    let toReturn = ZERO;
    // A second Close & pay (for example after a failed card payment) must not apply the deposit again.
    const depositAlreadyApplied = billed.payments.some((p) => p.reference === 'TAB_DEPOSIT');
    if (tab.security === 'CASH_DEPOSIT' && D(tab.amountHeld).greaterThan(0) && !depositAlreadyApplied) {
      const split = depositSplit(tab.amountHeld, grand);
      applied = split.applied;
      toReturn = split.toReturn;
      if (applied.greaterThan(0)) {
        await this.payments.pay(
          tab.orderId,
          { payments: [{ method: PaymentMethod.CASH, amount: applied.toNumber(), reference: 'TAB_DEPOSIT' }] },
          auth,
        );
      }
    }

    const fresh = await this.mustFind(id, auth);
    return {
      tab: await this.viewOf(fresh),
      orderId: tab.orderId,
      depositApplied: money(applied),
      depositToReturn: money(toReturn),
    };
  }

  /** POST /tabs/:id/void. Only a tab with no live lines. The order is voided and its table freed. */
  async voidTab(id: string, dto: VoidTabDto, auth: AuthUser): Promise<TabView> {
    const tab = await this.mustFind(id, auth);
    this.assertOpen(tab);
    const [row] = await this.repo.rowsFor([tab]);
    if (!row) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
    if (row.itemCount > 0) throw apiError(409, 'TAB_NOT_EMPTY', 'Only an empty tab can be voided', { itemCount: row.itemCount });

    const now = new Date();
    await this.repo.transaction(async (tx) => {
      const bundle = await this.ordersRepo.loadBundle(tx, tab.orderId);
      await this.ordersRepo.updateOrder(tx, tab.orderId, { status: 'VOID', voidedAt: now, voidReason: dto.reason });
      if (bundle?.order.tableId) await this.ordersRepo.setTableStatus(tx, bundle.order.tableId, 'FREE');
      await this.repo.updateTab(tx, tab.id, { status: TabStatus.VOID, closedAt: now, closedById: auth.userId });
      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'tab.void',
        entity: 'BarTab',
        entityId: tab.id,
        metadata: { number: tab.number, reason: dto.reason },
      });
    });
    return this.viewOf(await this.mustFind(id, auth));
  }

  // ---------------------------------------------------------------------------

  private async mustFind(id: string, auth: AuthUser): Promise<BarTab> {
    const tab = await this.repo.findTab(id, auth.outletId);
    if (!tab) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
    return tab;
  }

  private assertOpen(tab: BarTab): void {
    if (tab.status !== TabStatus.OPEN) throw apiError(409, 'TAB_CLOSED', 'This tab is closed', { status: tab.status });
  }

  private async viewOf(tab: BarTab): Promise<TabView> {
    const [row] = await this.repo.rowsFor([tab]);
    if (!row) throw apiError(404, 'TAB_NOT_FOUND', 'Tab not found');
    return toTabView(row);
  }
}
