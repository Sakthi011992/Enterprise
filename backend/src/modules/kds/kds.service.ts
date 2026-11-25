import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor } from '../../common/pricing/business-date';
import { dayWindow } from '../orders/business-day-window';
import { PermissionsService } from '../personas/permissions.service';
import { RealtimeEvent, outletEvent, stationEvent, userEvent } from '../realtime/realtime.types';
import { RealtimeService } from '../realtime/realtime.service';
import { BoardQueryDto, ReadyQueryDto } from './dto/kds.dto';
import {
  DONE_WINDOW_MS,
  KdsAction,
  OVERDUE_MS,
  allDayCounts,
  avgTicketSeconds,
  stationLabel,
  transitionError,
} from './kds-math';
import { KdsRepository } from './kds.repository';
import {
  KdsOrderContext,
  itemsSummary,
  overdueTitle,
  readTicketItems,
  readyTitle,
  toKdsTicket,
  toReadyItem,
} from './kds-view';

const OVERDUE_CHECK_MS = 60_000;

/**
 * Kitchen and bar display. Start, bump, recall and served move a ticket through NEW, PREPARING, READY and
 * SERVED. A bump tells the waiter (notification and realtime). A READY ticket that is still waiting after
 * five minutes raises one overdue alert.
 */
@Injectable()
export class KdsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KdsService.name);
  private timer?: NodeJS.Timeout;

  constructor(
    private repo: KdsRepository,
    private permissions: PermissionsService,
    private realtime: RealtimeService,
  ) {}

  onModuleInit(): void {
    if (process.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => {
      this.alertOverdue().catch((e) => this.logger.warn(`Overdue check failed: ${(e as Error).message}`));
    }, OVERDUE_CHECK_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /**
   * GET /kds/tickets. Active cards (or done cards from the last two hours), plus the all-day totals and the
   * average time to bump for the business day.
   */
  async board(q: BoardQueryDto, auth: AuthUser) {
    const now = new Date();
    const station = q.station && q.station !== 'ALL' ? q.station : undefined;
    const tz = await this.repo.outletTimezone(auth.outletId);
    const window = dayWindow(businessDateFor(now, tz, '05:00'), tz);

    const day = await this.repo.dayTickets(auth.outletId, window.start, window.end, station);
    const cardRows =
      q.view === 'done'
        ? await this.repo.servedSince(auth.outletId, new Date(now.getTime() - DONE_WINDOW_MS), station)
        : await this.repo.activeTickets(auth.outletId, station);

    const contexts = await this.repo.loadContext([...day, ...cardRows].map((t) => t.orderId));
    const tickets = cardRows.flatMap((t) => {
      const ctx = contexts.get(t.orderId);
      return ctx ? [toKdsTicket(t, ctx, now)] : [];
    });

    const allDay = allDayCounts(
      day.map((t) => {
        const ctx = contexts.get(t.orderId);
        return {
          kdsStatus: t.kdsStatus,
          items: readTicketItems(t.items).map((i) => ({
            name: i.name,
            variantName: i.variantName,
            quantity: i.quantity,
            voided: ctx?.itemStatus.get(i.orderItemId) === 'VOIDED',
          })),
        };
      }),
    );

    return {
      serverTime: now.toISOString(),
      tickets,
      allDay,
      avgTicketSeconds: avgTicketSeconds(day),
    };
  }

  start(id: string, auth: AuthUser) {
    return this.transition(id, auth, 'start');
  }

  bump(id: string, auth: AuthUser) {
    return this.transition(id, auth, 'bump');
  }

  recall(id: string, auth: AuthUser) {
    return this.transition(id, auth, 'recall');
  }

  /** Mark served: READY to SERVED. Allowed with sales.orders.take EDIT or kds.bump EDIT. */
  async served(id: string, auth: AuthUser) {
    const allowed =
      this.permissions.check(auth, 'sales.orders.take', 'EDIT') || this.permissions.check(auth, 'kds.bump', 'EDIT');
    if (!allowed) {
      throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', {
        permission: 'kds.bump',
        required: 'EDIT',
      });
    }
    return this.transition(id, auth, 'served');
  }

  /**
   * GET /kds/ready. READY tickets of the outlet, oldest first. `mine` keeps the waiter's tickets (the order's
   * waiter, or whoever sent the ticket). Needs sales.orders.take VIEW or kds.bump VIEW.
   */
  async ready(q: ReadyQueryDto, auth: AuthUser) {
    const allowed =
      this.permissions.check(auth, 'sales.orders.take', 'VIEW') || this.permissions.check(auth, 'kds.bump', 'VIEW');
    if (!allowed) {
      throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', {
        permission: 'kds.bump',
        required: 'VIEW',
      });
    }
    const now = new Date();
    const rows = await this.repo.readyTickets(auth.outletId);
    const contexts = await this.repo.loadContext(rows.map((t) => t.orderId));
    const items = rows.flatMap((t) => {
      const ctx = contexts.get(t.orderId);
      if (!ctx) return [];
      if (q.mine === 'true' && ctx.waiterId !== auth.userId && t.createdById !== auth.userId) return [];
      return [toReadyItem(t, ctx, now)];
    });
    return items;
  }

  /** GET /kds/stations: station values in use, with how many cards are active on each. */
  async stations(auth: AuthUser) {
    const [configured, active] = await Promise.all([
      this.repo.categoryStations(auth.tenantId),
      this.repo.activeTickets(auth.outletId),
    ]);
    const counts = new Map<string, number>();
    for (const t of active) counts.set(t.station, (counts.get(t.station) ?? 0) + 1);
    const names = [...new Set([...configured, ...counts.keys()])].sort();
    return names.map((station) => ({ station, label: stationLabel(station), activeCount: counts.get(station) ?? 0 }));
  }

  /**
   * Overdue job. Finds READY tickets bumped more than five minutes ago that have not been alerted, raises
   * one notification each, and returns how many were raised.
   */
  async alertOverdue(now: Date = new Date()): Promise<number> {
    const rows = await this.repo.overdueReady(new Date(now.getTime() - OVERDUE_MS));
    if (rows.length === 0) return 0;
    const contexts = await this.repo.loadContext(rows.map((t) => t.orderId));
    let raised = 0;
    for (const t of rows) {
      const ctx = contexts.get(t.orderId);
      if (!ctx) continue;
      await this.repo.transaction(async (tx) => {
        await this.repo.createNotification(tx, {
          tenantId: t.tenantId,
          outletId: t.outletId,
          userId: null,
          permissionKey: 'kds.bump',
          type: 'alert',
          title: overdueTitle(t, ctx, now),
          body: null,
          data: { ticketId: t.id, orderId: t.orderId },
        });
        await this.repo.markOverdueAlerted(tx, t.id, now);
      });
      raised += 1;
    }
    return raised;
  }

  // ---------------------------------------------------------------------------

  private async transition(id: string, auth: AuthUser, action: KdsAction) {
    const now = new Date();
    const done = await this.repo.transaction(async (tx) => {
      const ticket = await this.repo.findTicket(tx, id, auth.outletId);
      if (!ticket) throw apiError(404, 'TICKET_NOT_FOUND', 'Ticket not found');

      const code = transitionError(action, ticket.kdsStatus, ticket.servedAt, now);
      if (code) {
        const message = code === 'RECALL_TOO_LATE' ? 'Served tickets can be recalled for 30 minutes only' : 'This ticket cannot do that now';
        throw apiError(409, code, message, { status: ticket.kdsStatus });
      }

      const updated = await this.repo.updateTicket(tx, ticket.id, this.dataFor(action, auth.userId, now));
      const ctxMap = await this.repo.loadContext([ticket.orderId], tx);
      const ctx: KdsOrderContext | undefined = ctxMap.get(ticket.orderId);
      if (!ctx) throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');

      if (action === 'served') {
        await this.repo.markItemsServed(tx, readTicketItems(ticket.items).map((i) => i.orderItemId));
      }
      if (action === 'bump') {
        await this.repo.createNotification(tx, {
          tenantId: ticket.tenantId,
          outletId: ticket.outletId,
          userId: ctx.waiterId ?? ticket.createdById,
          permissionKey: null,
          type: 'ready',
          title: readyTitle(ticket, ctx),
          body: itemsSummary(ticket) || null,
          data: { ticketId: ticket.id, orderId: ticket.orderId },
        });
      }
      return { updated, ctx };
    });

    const card = toKdsTicket(done.updated, done.ctx, now);
    const events: RealtimeEvent[] = [stationEvent(auth.outletId, done.updated.station, 'kds.ticket.updated', card)];
    if (action === 'bump') {
      const ready = toReadyItem(done.updated, done.ctx, now);
      events.push(userEvent(done.ctx.waiterId ?? done.updated.createdById, 'kds.ready', ready));
      events.push(outletEvent(auth.outletId, 'kds.ready', ready));
    }
    this.realtime.publish(events);
    return card;
  }

  private dataFor(action: KdsAction, userId: string, now: Date): Prisma.TicketUncheckedUpdateInput {
    switch (action) {
      case 'start':
        return { kdsStatus: 'PREPARING', startedAt: now };
      case 'bump':
        return { kdsStatus: 'READY', readyAt: now, bumpedById: userId };
      case 'recall':
        return { kdsStatus: 'PREPARING', recalledAt: now, readyAt: null, servedAt: null };
      case 'served':
        return { kdsStatus: 'SERVED', servedAt: now };
    }
  }
}
