import { Inject, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { randomUUID } from 'crypto';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { TenantContext } from '../../common/tenancy/tenant-context';
import { GuestAuthRepository } from '../guest-auth/guest-auth.repository';
import type { GuestPrincipal } from '../guest-auth/guest-auth.guard';
import { GuestRateLimiter } from '../guest-auth/guest-rate-limiter';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { GuestConfigData } from '../guest-config/guest-config.types';
import { D, money, ZERO } from '../orders/order-pricing';
import { OrdersService } from '../orders/orders.service';
import { GUEST_EVENTS, GuestEvents } from '../realtime/guest-events.port';
import { CheckoutDto, PlaceRoundDto, ServiceRequestDto } from './dto/guest.dto';
import { GuestMenu, GuestMenuService } from './guest-menu.service';
import { GuestOrderViewService, GuestRoundView } from './guest-order-view.service';
import { readRoundItems, RoundItem, roundTotal } from './guest-round.types';
import { GuestRepository } from './guest.repository';

const SEATED = ['OCCUPIED', 'BILL_PRINTED'];

/** Guest API (PLAN 2.4): menu, rounds, order view, service requests, checkout, age gate. */
@Injectable()
export class GuestOrderingService {
  private actors = new Map<string, AuthUser>();

  constructor(
    private repo: GuestRepository,
    private config: GuestConfigService,
    private menus: GuestMenuService,
    private views: GuestOrderViewService,
    private orders: OrdersService,
    private limiter: GuestRateLimiter,
    private authRepo: GuestAuthRepository,
    @Inject(GUEST_EVENTS) private events: GuestEvents,
  ) {}

  // ------------------------------------------------------------------ menu

  async menu(guest: GuestPrincipal): Promise<GuestMenu> {
    return this.menus.build({ tenantId: guest.tenantId, outletId: guest.outletId, tableId: await this.tableOf(guest) });
  }

  /** GET /guest/t/:qrToken/menu: read-only menu for a table that is not seated yet (no token). */
  async publicMenu(qrToken: string): Promise<GuestMenu> {
    const table = await TenantContext.runAsSystem(() => this.authRepo.findTableByQrToken(qrToken));
    if (!table) throw apiError(404, 'TABLE_NOT_FOUND', 'This QR code is not valid');
    TenantContext.set({ tenantId: table.tenantId, outletId: table.outletId });
    return this.menus.build({ tenantId: table.tenantId, outletId: table.outletId, tableId: table.id });
  }

  // ------------------------------------------------------------------ rounds

  async placeRound(guest: GuestPrincipal, dto: PlaceRoundDto): Promise<GuestRoundView & { total: string }> {
    const cfg = await this.config.get(guest.tenantId);
    const session = await this.openSession(guest);
    const table = await this.repo.findTable(session.tableId);
    if (!cfg.enabled || !table || !table.qrEnabled) throw apiError(403, 'GUEST_ORDERING_OFF', 'Ordering from the table is switched off');
    if (cfg.requireSeated && !SEATED.includes(table.status)) {
      throw apiError(409, 'TABLE_NOT_SEATED', 'Ask staff to seat you to start ordering');
    }

    const existing = await this.repo.findRequestByKey(session.id, dto.roundKey);
    if (existing) return this.roundView(existing.id, guest.participantId);

    this.limiter.consume('placeOrderPerParticipant', guest.participantId);
    const participant = await this.repo.findParticipant(guest.participantId);
    if (!participant) throw apiError(401, 'SESSION_CLOSED', "This table's session has ended");

    const menu = await this.menus.build({ tenantId: guest.tenantId, outletId: guest.outletId, tableId: table.id });
    const items = this.validate(dto, cfg, menu, !!session.ageConfirmedAt);

    // The table order: reuse the open one, or create it as the guest actor.
    const actor = await this.actor(guest);
    let order = await this.repo.openOrderOnTable(table.id);
    if (!order) {
      const created = (await this.orders.create(
        { type: 'DINE_IN', tableId: table.id, covers: 1, waiterId: null, source: 'GUEST_QR', guestSessionId: session.id },
        actor,
      )) as { id: string };
      order = { id: created.id, status: 'OPEN' as any, guestSessionId: session.id, waiterId: null };
    }
    if (order.guestSessionId !== session.id || session.orderId !== order.id) {
      await this.repo.linkOrderToSession(order.id, session.id);
    }

    const now = new Date();
    const id = randomUUID();
    const direct = cfg.routing === 'DIRECT';
    try {
      await this.repo.createRequest({
        id,
        tenantId: guest.tenantId,
        outletId: guest.outletId,
        sessionId: session.id,
        participantId: participant.id,
        orderId: order.id,
        roundKey: dto.roundKey,
        status: direct ? 'CONFIRMED' : 'PENDING',
        items: items as unknown as Prisma.InputJsonValue,
        decidedAt: direct ? now : null,
        expiresAt: new Date(now.getTime() + cfg.requestTtlMinutes * 60_000),
      });
    } catch (e) {
      if ((e as { code?: string }).code === 'P2002') {
        const again = await this.repo.findRequestByKey(session.id, dto.roundKey);
        if (again) return this.roundView(again.id, guest.participantId);
      }
      throw e;
    }

    if (direct) {
      try {
        await this.orders.addItems(
          order.id,
          { items: items.map((i) => ({ ...lineDto(i), guestRequestId: id, guestName: participant.name })) },
          actor,
        );
        await this.orders.send(order.id, actor);
      } catch (e) {
        await this.repo.deleteRequest(id);
        throw e;
      }
    } else {
      void this.events.requestNew({
        requestId: id,
        tenantId: guest.tenantId,
        outletId: guest.outletId,
        table: table.name,
        by: participant.name,
        phone: participant.phone,
        lines: items.map((i) => ({
          name: i.name ?? '',
          variant: i.variantName ?? null,
          modifiers: i.modifierNames ?? [],
          qty: i.quantity,
          lineTotal: i.lineTotal,
          note: i.note ?? null,
        })),
        total: roundTotal(items),
        claimedById: null,
      });
      void this.events.orderChanged(order.id);
    }
    return this.roundView(id, guest.participantId);
  }

  async cancelRound(guest: GuestPrincipal, id: string) {
    const cfg = await this.config.get(guest.tenantId);
    const r = await this.repo.findRequest(id);
    if (!r || r.sessionId !== guest.sessionId || r.participantId !== guest.participantId) {
      throw apiError(404, 'ROUND_NOT_FOUND', 'Round not found');
    }
    if (!cfg.allowGuestCancel) throw apiError(403, 'CANCEL_NOT_ALLOWED', 'Ask your waiter to change this order');
    const won = await this.repo.transitionRequest(id, ['PENDING'], { status: 'CANCELLED', decidedAt: new Date() });
    if (!won) throw apiError(409, 'ROUND_NOT_PENDING', 'This round was already sent', { status: r.status });
    void this.events.requestDecided({ requestId: id, outletId: r.outletId, status: 'CANCELLED', claimedById: r.claimedById });
    void this.events.orderChanged(r.orderId);
    return this.roundView(id, guest.participantId);
  }

  // ------------------------------------------------------------------ order view

  async order(guest: GuestPrincipal) {
    const session = await this.openSession(guest);
    void this.repo.touchParticipant(guest.participantId, new Date());
    const table = await this.repo.findTable(session.tableId);
    const cfg = await this.config.get(guest.tenantId);
    const orderId = session.orderId;
    const view = orderId ? await this.views.forOrder(orderId, guest.participantId) : null;
    if (view) return view;
    const zero = money(ZERO);
    return {
      orderId: null,
      table: table?.name ?? '',
      status: 'OPEN',
      atTable: await this.repo.countParticipants(session.id),
      rounds: [],
      totals: { subtotal: zero, discount: zero, serviceCharge: zero, tax: zero, roundOff: zero, grandTotal: zero, paid: zero, due: zero, estimate: false, pendingEstimate: zero },
      checkout: { mode: cfg.checkout, requested: !!(await this.repo.findOpenServiceRequest(session.id, 'BILL')) },
    };
  }

  // ------------------------------------------------------------------ service requests, checkout, age

  async serviceRequest(guest: GuestPrincipal, dto: ServiceRequestDto) {
    const session = await this.openSession(guest);
    const open = await this.repo.findOpenServiceRequest(session.id, dto.type);
    if (open) return this.serviceView(open);
    this.limiter.consume('serviceRequestPerSession', session.id);
    const created = await this.repo.createServiceRequest({
      tenantId: guest.tenantId,
      outletId: guest.outletId,
      sessionId: session.id,
      tableId: session.tableId,
      type: dto.type,
    });
    const table = await this.repo.findTable(session.tableId);
    void this.events.serviceRequestNew({
      id: created.id,
      tenantId: created.tenantId,
      outletId: created.outletId,
      table: table?.name ?? '',
      type: created.type,
      status: created.status,
    });
    if (session.orderId) void this.events.orderChanged(session.orderId);
    return this.serviceView(created);
  }

  async checkout(guest: GuestPrincipal, dto: CheckoutDto) {
    if (dto.mode === 'ONLINE') throw apiError(501, 'NOT_AVAILABLE', 'Online payment is coming soon');
    const r = await this.serviceRequest(guest, { type: 'BILL' });
    return { mode: 'WAITER' as const, requestId: r.id };
  }

  async ageConfirm(guest: GuestPrincipal) {
    const session = await this.openSession(guest);
    const at = session.ageConfirmedAt ?? new Date();
    if (!session.ageConfirmedAt) await this.repo.setAgeConfirmed(session.id, at);
    return { ageConfirmedAt: at.toISOString() };
  }

  // ------------------------------------------------------------------ internals

  /** Validates a round against the QR menu and the limits, and snapshots names and prices. */
  validate(dto: PlaceRoundDto, cfg: GuestConfigData, menu: GuestMenu, ageConfirmed: boolean): RoundItem[] {
    if (!dto.items.length || dto.items.length > cfg.maxLinesPerRound || dto.items.some((i) => i.quantity > cfg.maxQtyPerLine)) {
      throw apiError(400, 'ROUND_TOO_LARGE', `Up to ${cfg.maxLinesPerRound} lines and ${cfg.maxQtyPerLine} of each item per round`, {
        maxLinesPerRound: cfg.maxLinesPerRound,
        maxQtyPerLine: cfg.maxQtyPerLine,
      });
    }
    const index = this.menus.index(menu);
    const unavailable = dto.items
      .filter((i) => {
        const p = index.get(i.productId);
        if (!p || !p.available) return true;
        if (i.variantId && !p.variants.some((v) => v.id === i.variantId)) return true;
        return false;
      })
      .map((i) => i.productId);
    if (unavailable.length) {
      throw apiError(400, 'ITEM_UNAVAILABLE', 'Some items are not available right now', { productIds: [...new Set(unavailable)] });
    }

    const out: RoundItem[] = [];
    for (const i of dto.items) {
      const p = index.get(i.productId)!;
      const picked = i.modifiers ?? [];
      let delta = ZERO;
      const names: string[] = [];
      for (const m of picked) {
        const g = p.modifierGroups.find((x) => x.id === m.groupId);
        const o = g?.options.find((x) => x.id === m.optionId);
        if (!g || !o) throw apiError(400, 'MODIFIER_RULE', 'This option is not available for this item', { productId: p.id, optionId: m.optionId });
        delta = delta.add(D(o.priceDelta));
        names.push(o.name);
      }
      for (const g of p.modifierGroups) {
        const n = new Set(picked.filter((m) => m.groupId === g.id).map((m) => m.optionId)).size;
        if (n < g.minSelect || n > g.maxSelect) {
          throw apiError(400, 'MODIFIER_RULE', `${g.name}: choose ${g.minSelect} to ${g.maxSelect}`, {
            productId: p.id,
            groupId: g.id,
            minSelect: g.minSelect,
            maxSelect: g.maxSelect,
          });
        }
      }
      if (p.isAlcohol && cfg.ageGate && !ageConfirmed) {
        throw apiError(403, 'AGE_NOT_CONFIRMED', `Alcohol is served only to guests ${cfg.minAge} and over`, { minAge: cfg.minAge });
      }
      const unit = this.menus.priceOf(menu, p, i.variantId, delta);
      out.push({
        productId: p.id,
        variantId: i.variantId ?? null,
        quantity: i.quantity,
        modifiers: picked.map((m) => ({ groupId: m.groupId, optionId: m.optionId })),
        note: i.note ?? null,
        name: p.name,
        variantName: i.variantId ? p.variants.find((v) => v.id === i.variantId)?.name ?? null : null,
        modifierNames: names,
        unitPrice: money(unit),
        lineTotal: money(unit.mul(i.quantity)),
        isAlcohol: p.isAlcohol,
      });
    }
    return out;
  }

  /** One round as the guest sees it, from the order view (falls back to the stored round). */
  private async roundView(id: string, participantId: string): Promise<GuestRoundView & { total: string }> {
    const r = await this.repo.findRequest(id);
    if (!r) throw apiError(404, 'ROUND_NOT_FOUND', 'Round not found');
    const view = await this.views.forOrder(r.orderId, participantId);
    const round = view?.rounds.find((x) => x.id === id);
    const items = readRoundItems(r.items);
    const base: GuestRoundView = round ?? {
      id: r.id,
      by: r.participant.name,
      participantId: r.participantId,
      mine: r.participantId === participantId,
      status: r.status,
      rejectReason: r.rejectReason,
      createdAt: r.createdAt.toISOString(),
      lines: [],
    };
    const total = round ? money(round.lines.reduce((s, l) => s.add(D(l.lineTotal)), ZERO)) : roundTotal(items);
    return { ...base, total };
  }

  private serviceView(s: { id: string; type: string; status: string; createdAt: Date }) {
    return { id: s.id, type: s.type, status: s.status, createdAt: s.createdAt.toISOString() };
  }

  private async openSession(guest: GuestPrincipal) {
    const s = await this.repo.findSession(guest.sessionId);
    if (!s || s.status !== 'OPEN') throw apiError(409, 'SESSION_CLOSED', "This table's session has ended");
    return s;
  }

  /** The session's table (it follows the order when staff move it), not the token claim. */
  private async tableOf(guest: GuestPrincipal) {
    const s = await this.repo.findSession(guest.sessionId);
    return s?.tableId ?? guest.tableId;
  }

  /** The tenant's inactive `qr-guest` system user as an AuthUser for OrdersService (PLAN 2.2). */
  async actor(guest: { tenantId: string; outletId: string }): Promise<AuthUser> {
    const key = `${guest.tenantId}:${guest.outletId}`;
    const hit = this.actors.get(key);
    if (hit) return hit;
    const user = await this.repo.findQrGuestUser(guest.tenantId);
    if (!user) throw apiError(503, 'GUEST_ACTOR_MISSING', 'Guest ordering is not set up (qr-guest user missing)');
    const actor: AuthUser = {
      userId: user.id,
      username: user.username,
      tenantId: guest.tenantId,
      outletId: guest.outletId,
      personaId: '',
      personaKey: 'qr-guest',
      permissions: {},
      role: 'USER',
    };
    this.actors.set(key, actor);
    return actor;
  }
}

/** A round line as an OrdersService AddItem. */
export function lineDto(i: RoundItem) {
  return {
    productId: i.productId,
    variantId: i.variantId ?? undefined,
    quantity: i.quantity,
    note: i.note ?? undefined,
    modifierOptionIds: i.modifiers.map((m) => m.optionId),
  };
}
