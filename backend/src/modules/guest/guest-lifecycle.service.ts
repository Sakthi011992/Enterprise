import { Inject, Injectable, Logger, OnModuleDestroy, OnModuleInit, Optional } from '@nestjs/common';
import { TenantContext } from '../../common/tenancy/tenant-context';
import { GuestAuthGuard } from '../guest-auth/guest-auth.guard';
import { GuestPinService } from '../guest-auth/guest-pin.service';
import { newQrToken } from '../guest-auth/guest-utils';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { GUEST_EVENTS, GuestEvents } from '../realtime/guest-events.port';
import { GuestRepository } from './guest.repository';

const JOB_INTERVAL_MS = 60_000;
export const SESSION_IDLE_MS = 6 * 60 * 60 * 1000;
export const PHONE_RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const PHONE_JOB_EVERY_MS = 24 * 60 * 60 * 1000;

/**
 * Guest session lifecycle (PLAN 2.7): table PIN on seating, session close (QR rotation, PIN cleared,
 * pending rounds expired), round TTL expiry, idle sessions and the 90-day phone clean-up.
 *
 * Existing order, KDS, payment and floor paths call it through `GuestHooks` (one line each).
 */
@Injectable()
export class GuestLifecycleService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(GuestLifecycleService.name);
  private timer?: NodeJS.Timeout;
  private lastPhoneJob = 0;

  constructor(
    private repo: GuestRepository,
    private config: GuestConfigService,
    private pins: GuestPinService,
    @Inject(GUEST_EVENTS) private events: GuestEvents,
    @Optional() private guard?: GuestAuthGuard,
  ) {}

  onModuleInit(): void {
    if (process.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => {
      this.runJobs().catch((e) => this.logger.warn(`Guest jobs failed: ${(e as Error).message}`));
    }, JOB_INTERVAL_MS);
    this.timer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /** One pass of the periodic jobs. Runs across tenants. */
  runJobs(now = new Date()) {
    return TenantContext.runAsSystem(async () => {
      await this.expireRequests(now);
      await this.closeIdleSessions(now);
      if (now.getTime() - this.lastPhoneJob >= PHONE_JOB_EVERY_MS) {
        this.lastPhoneJob = now.getTime();
        await this.blankOldPhones(now);
      }
    });
  }

  // ------------------------------------------------------------------ reactions

  /** After any order mutation: PIN on seating, session move/close, then the guest realtime event. */
  async onOrderChanged(orderId: string): Promise<void> {
    const o = await this.repo.orderState(orderId);
    if (!o) return;
    if (o.table) await this.ensurePin(o.tenantId, o.table);
    if (!o.guestSessionId) return;
    const session = await this.repo.findSession(o.guestSessionId);
    if (!session) return;

    // Staff moved the order: the session follows it; the old table's QR is rotated.
    if (session.status === 'OPEN' && o.tableId && session.tableId !== o.tableId) {
      await this.repo.moveSession(session.id, { tableId: o.tableId });
      await this.repo.rotateTableQr(session.tableId, newQrToken());
    }

    void this.events.orderChanged(orderId);
    if (session.status !== 'OPEN') return;
    const tableDone = o.table && (o.table.status === 'FREE' || o.table.status === 'CLEANING');
    const voidedAlone = o.status === 'VOID' && o.tableId && (await this.repo.countOpenOrdersOnTable(o.tableId)) === 0;
    if (o.status === 'CLOSED' || voidedAlone || tableDone) {
      await this.closeSession(session.id, o.tableId ?? session.tableId);
    }
  }

  /** Merge: the source order's session moves to the target when the target has none. */
  async onOrderMerged(fromOrderId: string, toOrderId: string): Promise<void> {
    const [from, to] = await Promise.all([this.repo.orderState(fromOrderId), this.repo.orderState(toOrderId)]);
    if (from?.guestSessionId && to && !to.guestSessionId) {
      await this.repo.linkOrderToSession(to.id, from.guestSessionId);
      if (to.tableId) await this.repo.moveSession(from.guestSessionId, { tableId: to.tableId });
    }
    await this.onOrderChanged(toOrderId);
    if (from?.guestSessionId && to?.guestSessionId) await this.onOrderChanged(fromOrderId);
  }

  /** Staff set a table status by hand (floor plan). FREE or CLEANING ends the session. */
  async onTableChanged(tableId: string): Promise<void> {
    const t = await this.repo.findTable(tableId);
    if (!t) return;
    await this.ensurePin(t.tenantId, t);
    if (t.status === 'FREE' || t.status === 'CLEANING') {
      const s = await this.repo.openSessionForTable(tableId);
      if (s) await this.closeSession(s.id, tableId);
    }
  }

  /** TABLE_PIN mode: a seated table without a PIN gets one. Returns the current PIN (or null). */
  async ensurePin(tenantId: string, table: { id: string; status: string; guestPin: string | null }): Promise<string | null> {
    if (table.status !== 'OCCUPIED') return null;
    const cfg = await this.config.get(tenantId);
    if (cfg.verification.method !== 'TABLE_PIN') return null;
    if (table.guestPin) return table.guestPin;
    return this.pins.generate(table.id);
  }

  /** Rotate the QR token, clear the PIN, expire pending rounds, revoke tokens, tell the table. */
  async closeSession(sessionId: string, tableId: string, now = new Date()): Promise<boolean> {
    const closed = await this.repo.closeSession(sessionId, tableId, newQrToken(), now);
    if (!closed) return false;
    this.guard?.forget(sessionId);
    void this.events.sessionClosed(sessionId, tableId);
    return true;
  }

  // ------------------------------------------------------------------ jobs

  async expireRequests(now: Date): Promise<number> {
    const due = await this.repo.expiredPending(now);
    let n = 0;
    for (const r of due) {
      const won = await this.repo.transitionRequest(r.id, ['PENDING'], { status: 'EXPIRED', decidedAt: now });
      if (!won) continue;
      n += 1;
      void this.events.requestDecided({ requestId: r.id, outletId: r.outletId, status: 'EXPIRED', claimedById: r.claimedById });
      void this.events.orderChanged(r.orderId);
    }
    return n;
  }

  async closeIdleSessions(now: Date): Promise<number> {
    const idle = await this.repo.idleSessions(new Date(now.getTime() - SESSION_IDLE_MS));
    let n = 0;
    for (const s of idle) if (await this.closeSession(s.id, s.tableId, now)) n += 1;
    return n;
  }

  async blankOldPhones(now: Date): Promise<number> {
    const r = await this.repo.blankOldPhones(new Date(now.getTime() - PHONE_RETENTION_MS));
    return r.count;
  }
}
