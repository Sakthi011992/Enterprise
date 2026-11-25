import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { PrintService } from '../printing/print.service';
import { dayWindow } from '../orders/business-day-window';
import { OPEN_STATUSES } from '../orders/order-pricing';
import { computeDayTotals, DayTotals } from './day-totals';
import { DayCloseRepository } from './day-close.repository';
import { ZCloseDto } from './dto/day-close.dto';

/** Statuses an order can have when the Z report links it (money taken or voided). */
const LINKABLE = ['PAID', 'CLOSED', 'VOID', 'REFUNDED'];

const D = (v: Prisma.Decimal | number | string) => new Prisma.Decimal(v);
const json = (v: unknown) => v as Prisma.InputJsonValue;

@Injectable()
export class DayCloseService {
  private readonly logger = new Logger(DayCloseService.name);

  constructor(
    private repo: DayCloseRepository,
    private audit: AuditTrailService,
    private print: PrintService,
  ) {}

  /** The current business date of the outlet and its [start, end) window (05:00 cut-off). */
  private async window(auth: AuthUser, now: Date) {
    const timezone = await this.repo.outletTimezone(auth.outletId);
    const businessDate = businessDateFor(now, timezone, '05:00');
    const { start, end } = dayWindow(businessDate, timezone);
    return { businessDate, start, end };
  }

  /** X report: live totals for the business date. Nothing is saved. */
  async xReport(auth: AuthUser): Promise<DayTotals> {
    const now = new Date();
    const w = await this.window(auth, now);
    return this.repo.transaction(async (tx) => {
      const orders = await this.repo.ordersInWindow(tx, auth.outletId, w.start, w.end);
      return computeDayTotals(await this.repo.factsFor(tx, orders, w.businessDate));
    });
  }

  /** Prints the live X report on the outlet's receipt printer. Nothing is saved. */
  async printX(auth: AuthUser) {
    const totals = await this.xReport(auth);
    const job = await this.print.queueReportTotals(auth.outletId, { kind: 'X', totals });
    return { success: true, printJobId: job.id };
  }

  /**
   * Z report: saves a DayClose for the business date, links the day's paid, closed, refunded and
   * voided orders to it, and prints. One Z per business date. Open orders block it unless forced.
   */
  async zClose(auth: AuthUser, dto: ZCloseDto) {
    const now = new Date();
    const w = await this.window(auth, now);

    const saved = await this.repo.transaction(async (tx) => {
      const existing = await this.repo.findZClose(tx, auth.outletId, toDateOnly(w.businessDate));
      if (existing) throw apiError(409, 'DAY_ALREADY_CLOSED', `${w.businessDate} is already closed`);

      const orders = await this.repo.ordersInWindow(tx, auth.outletId, w.start, w.end);
      const openCount = orders.filter((o) => OPEN_STATUSES.includes(o.status)).length;
      if (openCount > 0 && !dto.force) {
        throw apiError(409, 'OPEN_ORDERS_EXIST', `${openCount} order(s) are still open`, { count: openCount });
      }

      const totals = computeDayTotals(await this.repo.factsFor(tx, orders, w.businessDate));
      const cashCounted = D(dto.cashCounted);
      const cashExpected = D(totals.cashExpected);

      const dayClose = await this.repo.createDayClose(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        kind: 'Z',
        businessDate: toDateOnly(w.businessDate),
        totals: json(totals),
        cashCounted,
        cashExpected,
        createdById: auth.userId,
      });
      const linkIds = orders.filter((o) => LINKABLE.includes(o.status)).map((o) => o.id);
      if (linkIds.length) await this.repo.linkOrders(tx, linkIds, dayClose.id);

      await this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'day_close.z',
        entity: 'DayClose',
        entityId: dayClose.id,
        metadata: { businessDate: w.businessDate, cashCounted: cashCounted.toFixed(2), cashExpected: cashExpected.toFixed(2), forced: !!dto.force && openCount > 0, openCount },
      });
      return { dayClose, totals, cashCounted, cashExpected };
    });

    try {
      await this.print.queueReport(saved.dayClose.id);
    } catch (e) {
      this.logger.warn(`Z report ${saved.dayClose.id} saved but not queued for print: ${(e as Error).message}`);
    }

    return {
      id: saved.dayClose.id,
      kind: 'Z' as const,
      businessDate: w.businessDate,
      cashCounted: saved.cashCounted.toFixed(2),
      cashExpected: saved.cashExpected.toFixed(2),
      variance: saved.cashCounted.sub(saved.cashExpected).toFixed(2),
      totals: saved.totals,
    };
  }

  async list(auth: AuthUser) {
    const rows = await this.repo.listDayCloses(auth.outletId, 50);
    return {
      data: rows.map((r) => ({
        id: r.id,
        kind: r.kind,
        businessDate: r.businessDate.toISOString().slice(0, 10),
        cashCounted: r.cashCounted === null ? null : r.cashCounted.toFixed(2),
        cashExpected: r.cashExpected === null ? null : r.cashExpected.toFixed(2),
        createdAt: r.createdAt.toISOString(),
        totals: r.totals,
      })),
    };
  }
}
