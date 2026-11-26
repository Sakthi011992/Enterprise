import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { GuestNotificationsService } from '../notifications/guest-notifications.service';
import {
  GUEST_ORDER_VIEW,
  GuestEvents,
  GuestOrderViewBuilder,
  GuestRequestDecidedInput,
  GuestRequestEventInput,
  ServiceRequestEventInput,
  maskPhone,
} from './guest-events.port';
import { RealtimeService } from './realtime.service';

/**
 * Realtime events of guest QR ordering (PLAN 2.6) plus the waiter notifications they raise. Every method
 * is best effort: a failure is logged and never fails the caller's (already committed) change.
 */
@Injectable()
export class GuestEventsService implements GuestEvents {
  private readonly logger = new Logger(GuestEventsService.name);

  constructor(
    private realtime: RealtimeService,
    private prisma: PrismaService,
    private notices: GuestNotificationsService,
    @Optional() @Inject(GUEST_ORDER_VIEW) private views?: GuestOrderViewBuilder,
  ) {}

  /**
   * Lets G-B register its GuestOrderView builder from its own module (e.g. in onModuleInit), since a
   * GUEST_ORDER_VIEW provider in G-B's module is not visible to this global module unless exported to it.
   */
  registerViewBuilder(builder: GuestOrderViewBuilder): void {
    this.views = builder;
  }

  /** No-op unless the order belongs to a guest session. Sends the guest-safe view to the table room. */
  async orderChanged(orderId: string): Promise<void> {
    await this.safe('orderChanged', async () => {
      const order = await this.prisma.order.findUnique({
        where: { id: orderId },
        select: { guestSessionId: true, tableId: true, guestSession: { select: { tableId: true } } },
      });
      const tableId = order?.guestSession?.tableId ?? order?.tableId;
      if (!order?.guestSessionId || !tableId) return;
      const view = this.views ? await this.views.build(orderId) : null;
      this.realtime.emitToTable(tableId, 'guest.order.updated', view ?? { orderId, changed: true });
    });
  }

  async requestNew(req: GuestRequestEventInput): Promise<void> {
    await this.safe('requestNew', async () => {
      const payload = {
        requestId: req.requestId,
        table: req.table,
        by: req.by,
        phone: maskPhone(req.phone),
        lines: req.lines.map((l) => ({
          name: l.name,
          variant: l.variant ?? null,
          modifiers: l.modifiers ?? [],
          qty: l.qty,
          lineTotal: l.lineTotal ?? null,
          note: l.note ?? null,
        })),
        total: req.total,
      };
      this.toStaff(req.outletId, req.claimedById, 'guest.request.new', payload);
      const count = req.lines.reduce((n, l) => n + l.qty, 0);
      await this.notices.notify({
        tenantId: req.tenantId,
        outletId: req.outletId,
        permissionKey: 'guests.orders.confirm',
        type: 'guest_round',
        title: `New QR order · ${req.table}`,
        body: `${req.by} · ${count} item${count === 1 ? '' : 's'}`,
        data: { requestId: req.requestId },
      });
    });
  }

  async requestDecided(req: GuestRequestDecidedInput): Promise<void> {
    await this.safe('requestDecided', async () => {
      this.toStaff(req.outletId, req.claimedById, 'guest.request.decided', { requestId: req.requestId, status: req.status });
    });
  }

  async serviceRequestNew(req: ServiceRequestEventInput): Promise<void> {
    await this.safe('serviceRequestNew', async () => {
      this.toStaff(req.outletId, req.acknowledgedById, 'service.request.new', { id: req.id, table: req.table, type: req.type });
      await this.notices.notify({
        tenantId: req.tenantId,
        outletId: req.outletId,
        permissionKey: 'sales.orders.take',
        type: 'service_request',
        title: req.type === 'BILL' ? `Bill requested · ${req.table}` : `Waiter called · ${req.table}`,
        body: null,
        data: { serviceRequestId: req.id, type: req.type },
      });
    });
  }

  async serviceRequestUpdated(req: ServiceRequestEventInput): Promise<void> {
    await this.safe('serviceRequestUpdated', async () => {
      this.toStaff(req.outletId, req.acknowledgedById, 'service.request.updated', {
        id: req.id,
        table: req.table,
        type: req.type,
        status: req.status ?? null,
      });
    });
  }

  async sessionClosed(sessionId: string, tableId: string): Promise<void> {
    await this.safe('sessionClosed', async () => {
      this.realtime.emitToTable(tableId, 'guest.session.closed', { sessionId });
    });
  }

  private toStaff(outletId: string, userId: string | null | undefined, event: string, payload: unknown): void {
    this.realtime.emitToOutlet(outletId, event, payload);
    if (userId) this.realtime.emitToUser(userId, event, payload);
  }

  private async safe(what: string, fn: () => Promise<void>): Promise<void> {
    try {
      await fn();
    } catch (e) {
      this.logger.warn(`guest event ${what} failed: ${(e as Error).message}`);
    }
  }
}
