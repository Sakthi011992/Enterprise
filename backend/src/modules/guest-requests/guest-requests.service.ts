import { Inject, Injectable } from '@nestjs/common';
import { GuestRequestStatus, Prisma, ServiceRequestStatus } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { AuditTrailService } from '../approvals/audit-trail.service';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { GuestLifecycleService } from '../guest/guest-lifecycle.service';
import { GuestMenuService } from '../guest/guest-menu.service';
import { lineDto } from '../guest/guest-ordering.service';
import { readRoundItems, RoundItem, roundTotal, toRequestRow, toServiceRow } from '../guest/guest-round.types';
import { GuestRepository } from '../guest/guest.repository';
import { newQrToken } from '../guest-auth/guest-utils';
import { D, money } from '../orders/order-pricing';
import { OrdersService } from '../orders/orders.service';
import { GUEST_EVENTS, GuestEvents } from '../realtime/guest-events.port';
import { ConfirmRequestDto, RejectRequestDto } from './dto/guest-requests.dto';

const REQUEST_STATUSES: GuestRequestStatus[] = ['PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED', 'EXPIRED'];
const SERVICE_STATUSES: ServiceRequestStatus[] = ['OPEN', 'ACKNOWLEDGED', 'DONE'];

/** Staff side of guest ordering (PLAN 2.7): rounds to confirm, service requests, table PIN and QR. */
@Injectable()
export class GuestRequestsService {
  constructor(
    private repo: GuestRepository,
    private orders: OrdersService,
    private audit: AuditTrailService,
    private lifecycle: GuestLifecycleService,
    private config: GuestConfigService,
    private menus: GuestMenuService,
    @Inject(GUEST_EVENTS) private events: GuestEvents,
  ) {}

  // ------------------------------------------------------------------ rounds

  async list(auth: AuthUser, status?: string, mine?: string) {
    const statuses = parseList(status, REQUEST_STATUSES, ['PENDING']);
    let rows = await this.repo.listRequests(auth.outletId, statuses);
    if (mine === 'true') {
      const waiters = new Map<string, string | null>();
      for (const r of rows) {
        if (!waiters.has(r.orderId)) waiters.set(r.orderId, (await this.repo.orderState(r.orderId))?.waiterId ?? null);
      }
      rows = rows.filter((r) => r.claimedById === auth.userId || waiters.get(r.orderId) === auth.userId);
    }
    return { data: await this.rows(rows) };
  }

  async claim(id: string, auth: AuthUser) {
    const r = await this.own(id, auth);
    if (r.status !== 'PENDING') throw apiError(409, 'REQUEST_NOT_PENDING', 'This round is no longer waiting', { status: r.status });
    if (!(await this.repo.claimRequest(id, auth.userId))) {
      throw apiError(409, 'ALREADY_CLAIMED', 'Another waiter is on it', { claimedById: r.claimedById });
    }
    await this.repo.setOrderWaiterIfEmpty(r.orderId, auth.userId);
    void this.events.requestDecided({ requestId: id, outletId: r.outletId, status: 'PENDING', claimedById: auth.userId });
    return this.row(id);
  }

  /** Confirm (optionally edited): lines go on the order as the waiter, keeping guestName, then are sent. */
  async confirm(id: string, dto: ConfirmRequestDto, auth: AuthUser) {
    const r = await this.own(id, auth);
    if (r.status !== 'PENDING') throw apiError(409, 'REQUEST_NOT_PENDING', 'This round is no longer waiting', { status: r.status });
    if (r.session.status !== 'OPEN') throw apiError(409, 'SESSION_CLOSED', "This table's session has ended");
    const before = readRoundItems(r.items);
    const after = dto.items ? await this.edited(before, dto, r.session) : before;
    if (after.length === 0) throw apiError(400, 'ITEMS_REQUIRED', 'Keep at least one line, or reject the round');

    const now = new Date();
    const won = await this.repo.transitionRequest(id, ['PENDING'], {
      status: 'CONFIRMED',
      decidedById: auth.userId,
      decidedAt: now,
      claimedById: r.claimedById ?? auth.userId,
      items: after as unknown as Prisma.InputJsonValue,
    });
    if (!won) throw apiError(409, 'REQUEST_NOT_PENDING', 'This round is no longer waiting');

    try {
      await this.orders.addItems(
        r.orderId,
        { items: after.map((i) => ({ ...lineDto(i), guestRequestId: id, guestName: r.participant.name })) },
        auth,
      );
      await this.orders.send(r.orderId, auth);
    } catch (e) {
      await this.repo.transitionRequest(id, ['CONFIRMED'], {
        status: 'PENDING',
        decidedById: null,
        decidedAt: null,
        items: before as unknown as Prisma.InputJsonValue,
      });
      throw e;
    }
    await this.repo.setOrderWaiterIfEmpty(r.orderId, auth.userId);
    await this.repo.transaction((tx) =>
      this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: dto.items ? 'guest.round.confirm_edited' : 'guest.round.confirm',
        entity: 'GuestOrderRequest',
        entityId: id,
        metadata: { orderId: r.orderId, before, after } as unknown as Record<string, unknown>,
      }),
    );
    void this.events.requestDecided({ requestId: id, outletId: r.outletId, status: 'CONFIRMED', claimedById: r.claimedById ?? auth.userId });
    return this.row(id);
  }

  async reject(id: string, dto: RejectRequestDto, auth: AuthUser) {
    const r = await this.own(id, auth);
    const won = await this.repo.transitionRequest(id, ['PENDING'], {
      status: 'REJECTED',
      rejectReason: dto.reason,
      decidedById: auth.userId,
      decidedAt: new Date(),
    });
    if (!won) throw apiError(409, 'REQUEST_NOT_PENDING', 'This round is no longer waiting', { status: r.status });
    await this.repo.transaction((tx) =>
      this.audit.record(tx, {
        tenantId: auth.tenantId,
        actorId: auth.userId,
        action: 'guest.round.reject',
        entity: 'GuestOrderRequest',
        entityId: id,
        metadata: { orderId: r.orderId, reason: dto.reason, before: readRoundItems(r.items), after: [] } as unknown as Record<string, unknown>,
      }),
    );
    void this.events.requestDecided({ requestId: id, outletId: r.outletId, status: 'REJECTED', claimedById: r.claimedById });
    void this.events.orderChanged(r.orderId);
    return this.row(id);
  }

  // ------------------------------------------------------------------ service requests

  async serviceRequests(auth: AuthUser, status?: string) {
    const statuses = parseList(status, SERVICE_STATUSES, ['OPEN', 'ACKNOWLEDGED']);
    const rows = await this.repo.listServiceRequests(auth.outletId, statuses);
    const names = new Map((await this.repo.tableNames([...new Set(rows.map((r) => r.tableId))])).map((t) => [t.id, t.name]));
    return { data: rows.map((s) => toServiceRow(s, names.get(s.tableId) ?? '')) };
  }

  ack(id: string, auth: AuthUser) {
    return this.updateService(id, auth, ['OPEN'], { status: 'ACKNOWLEDGED', acknowledgedById: auth.userId });
  }

  done(id: string, auth: AuthUser) {
    return this.updateService(id, auth, ['OPEN', 'ACKNOWLEDGED'], {
      status: 'DONE',
      doneAt: new Date(),
    });
  }

  // ------------------------------------------------------------------ tables

  async guestPin(tableId: string, auth: AuthUser) {
    const t = await this.table(tableId, auth);
    const cfg = await this.config.get(auth.tenantId);
    if (cfg.verification.method !== 'TABLE_PIN') throw apiError(409, 'PIN_NOT_USED', 'Table PIN verification is not switched on');
    if (t.status !== 'OCCUPIED' && t.status !== 'BILL_PRINTED') throw apiError(409, 'TABLE_NOT_SEATED', 'Seat the table first');
    const pin = t.guestPin ?? (await this.lifecycle.ensurePin(auth.tenantId, { ...t, status: 'OCCUPIED' }));
    return { pin };
  }

  async rotateQr(tableId: string, auth: AuthUser) {
    await this.table(tableId, auth);
    const s = await this.repo.openSessionForTable(tableId);
    if (s) await this.lifecycle.closeSession(s.id, tableId);
    else await this.repo.rotateTableQr(tableId, newQrToken());
    const t = await this.repo.findTable(tableId);
    return { tableId, qrToken: t!.qrToken, sessionClosed: !!s };
  }

  /**
   * Printable sheet of table QR cards as HTML. No QR or PDF library is installed and Chrome is not available
   * for puppeteer here, so each card carries its URL in data-url and as text (see the G-B report).
   */
  async qrSheet(auth: AuthUser, areaId?: string): Promise<string> {
    const tables = await this.repo.tablesForSheet(auth.outletId, areaId);
    const base = (process.env.GUEST_APP_BASE_URL ?? 'http://localhost:8080').replace(/\/$/, '');
    const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
    const cards = tables
      .filter((t) => t.qrEnabled)
      .map((t) => {
        const url = `${base}/t/${t.qrToken}`;
        return `<div class="card"><h2>${esc(t.name)}</h2><p class="area">${esc(t.area?.name ?? '')}</p>` +
          `<div class="qr" data-url="${esc(url)}"></div><p class="hint">Scan to see the menu and order</p>` +
          `<p class="url">${esc(url)}</p></div>`;
      })
      .join('\n');
    return `<!doctype html><html><head><meta charset="utf-8"><title>Table QR codes</title><style>
body{font-family:system-ui,sans-serif;margin:16px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}
.card{border:1px solid #999;border-radius:8px;padding:12px;text-align:center;page-break-inside:avoid}
h2{margin:0}.area,.hint{color:#555;margin:4px 0}.url{font-size:10px;word-break:break-all}
@media print{body{margin:0}}</style></head><body><div class="grid">${cards}</div></body></html>`;
  }

  // ------------------------------------------------------------------ internals

  private async own(id: string, auth: AuthUser) {
    const r = await this.repo.findRequest(id);
    if (!r || r.outletId !== auth.outletId) throw apiError(404, 'REQUEST_NOT_FOUND', 'Guest order not found');
    return r;
  }

  private async table(tableId: string, auth: AuthUser) {
    const t = await this.repo.findTable(tableId);
    if (!t || t.outletId !== auth.outletId) throw apiError(404, 'TABLE_NOT_FOUND', 'Table not found');
    return t;
  }

  /** Waiter edits: remove lines, change quantities and notes. Prices and names come from the QR menu. */
  private async edited(before: RoundItem[], dto: ConfirmRequestDto, session: { tenantId: string; outletId: string; tableId: string }) {
    const menu = await this.menus.build({ tenantId: session.tenantId, outletId: session.outletId, tableId: session.tableId });
    const index = this.menus.index(menu);
    return dto.items!.map((i) => {
      const prev = before.find((b) => b.productId === i.productId && (b.variantId ?? null) === (i.variantId ?? null));
      const p = index.get(i.productId);
      const mods = i.modifiers ?? prev?.modifiers ?? [];
      let delta = D(0);
      const names: string[] = [];
      for (const m of mods) {
        const o = p?.modifierGroups.find((g) => g.id === m.groupId)?.options.find((x) => x.id === m.optionId);
        if (o) {
          delta = delta.add(D(o.priceDelta));
          names.push(o.name);
        }
      }
      const unit = p ? this.menus.priceOf(menu, p, i.variantId, delta) : D(prev?.unitPrice ?? 0);
      return {
        productId: i.productId,
        variantId: i.variantId ?? null,
        quantity: i.quantity,
        modifiers: mods.map((m) => ({ groupId: m.groupId, optionId: m.optionId })),
        note: i.note ?? null,
        name: p?.name ?? prev?.name ?? '',
        variantName: i.variantId ? p?.variants.find((v) => v.id === i.variantId)?.name ?? prev?.variantName ?? null : null,
        modifierNames: names,
        unitPrice: money(unit),
        lineTotal: money(unit.mul(i.quantity)),
        isAlcohol: p?.isAlcohol ?? prev?.isAlcohol ?? false,
      } as RoundItem;
    });
  }

  private async updateService(id: string, auth: AuthUser, from: ServiceRequestStatus[], data: Prisma.ServiceRequestUncheckedUpdateInput) {
    const s = await this.repo.findServiceRequest(id);
    if (!s || s.outletId !== auth.outletId) throw apiError(404, 'SERVICE_REQUEST_NOT_FOUND', 'Request not found');
    if (!from.includes(s.status)) throw apiError(409, 'SERVICE_REQUEST_DONE', 'This request is already handled', { status: s.status });
    const u = await this.repo.updateServiceRequest(id, data);
    const [t] = await this.repo.tableNames([u.tableId]);
    void this.events.serviceRequestUpdated({
      id: u.id,
      tenantId: u.tenantId,
      outletId: u.outletId,
      table: t?.name ?? '',
      type: u.type,
      status: u.status,
      acknowledgedById: u.acknowledgedById,
    });
    return toServiceRow(u, t?.name ?? '');
  }

  private async row(id: string) {
    const r = await this.repo.findRequest(id);
    return (await this.rows([r!]))[0];
  }

  private async rows(rows: NonNullable<Awaited<ReturnType<GuestRepository['findRequest']>>>[]) {
    const tables = new Map((await this.repo.tableNames([...new Set(rows.map((r) => r.session.tableId))])).map((t) => [t.id, t.name]));
    const users = await this.repo.userNames([...new Set(rows.map((r) => r.claimedById).filter((x): x is string => !!x))]);
    const names = new Map(users.map((u) => [u.id, u.displayName ?? u.username]));
    return rows.map((r) => toRequestRow(r, tables.get(r.session.tableId) ?? '', names));
  }
}

function parseList<T extends string>(raw: string | undefined, allowed: T[], fallback: T[]): T[] {
  if (!raw) return fallback;
  const picked = raw.split(',').map((s) => s.trim().toUpperCase()).filter((s): s is T => allowed.includes(s as T));
  return picked.length ? picked : fallback;
}

export { roundTotal };
