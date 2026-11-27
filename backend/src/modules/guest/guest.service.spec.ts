import { Prisma } from '@prisma/client';
import { DEFAULT_GUEST_CONFIG, GuestConfigData } from '../guest-config/guest-config.types';
import { GuestRateLimiter } from '../guest-auth/guest-rate-limiter';
import { GuestRequestsService } from '../guest-requests/guest-requests.service';
import { GuestLifecycleService } from './guest-lifecycle.service';
import { GuestMenu, GuestMenuService } from './guest-menu.service';
import { GuestOrderViewService } from './guest-order-view.service';
import { GuestOrderingService } from './guest-ordering.service';
import { guestOrderStatus, lineState, roundOnlyState, ticketStatusByLine } from './guest-status';

const U = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const PRODUCT = U(1);
const BEER = U(2);
const GROUP = U(3);
const OPT = U(4);

const guest = { kind: 'guest' as const, sessionId: 's1', participantId: 'p1', tableId: 't1', outletId: 'o1', tenantId: 'ten' };
const staff = { userId: 'w1', username: 'ravi', tenantId: 'ten', outletId: 'o1', personaId: 'x', personaKey: 'waiter', permissions: {}, role: 'USER' as const };

const menu: GuestMenu = {
  markupPercent: '0.00',
  happyHour: null,
  categories: [
    {
      id: 'c1',
      name: 'Food',
      color: null,
      sortOrder: 0,
      products: [
        {
          id: PRODUCT, name: 'Chicken Wings', description: null, categoryId: 'c1', price: '300.00', basePrice: '300.00', listPrice: '300.00',
          available: true, isAlcohol: false, featured: false, imageUrl: null, happyHour: null, variants: [],
          modifierGroups: [{ id: GROUP, name: 'Sauce', minSelect: 0, maxSelect: 1, options: [{ id: OPT, name: 'Hot', priceDelta: '20.00' }] }],
        },
        {
          id: BEER, name: 'Beer', description: null, categoryId: 'c1', price: '200.00', basePrice: '200.00', listPrice: '200.00',
          available: true, isAlcohol: true, featured: false, imageUrl: null, happyHour: null, variants: [], modifierGroups: [],
        },
      ],
    },
  ],
};

function cfg(over: Partial<GuestConfigData> = {}): GuestConfigData {
  return { ...DEFAULT_GUEST_CONFIG, ...over };
}

function setup(config: GuestConfigData = cfg()) {
  const requests = new Map<string, any>();
  const session: any = { id: 's1', tenantId: 'ten', outletId: 'o1', tableId: 't1', orderId: null, status: 'OPEN', ageConfirmedAt: null };
  const serviceRequests: any[] = [];
  const repo: any = {
    findSession: jest.fn(async (id: string) => (id === session.id ? session : null)),
    findTable: jest.fn(async () => ({ id: 't1', name: 'R4', outletId: 'o1', tenantId: 'ten', status: 'OCCUPIED', qrEnabled: true, guestPin: null, qrToken: 'old' })),
    findParticipant: jest.fn(async () => ({ id: 'p1', name: 'Deepa', phone: '+919876543210' })),
    findRequestByKey: jest.fn(async (_s: string, key: string) => [...requests.values()].find((r) => r.roundKey === key) ?? null),
    openOrderOnTable: jest.fn(async () => null),
    linkOrderToSession: jest.fn(async (orderId: string) => { session.orderId = orderId; }),
    createRequest: jest.fn(async (data: any) => {
      const r = { claimedById: null, decidedById: null, rejectReason: null, decidedAt: null, createdAt: new Date(), ...data };
      requests.set(data.id, r);
      return r;
    }),
    deleteRequest: jest.fn(async (id: string) => requests.delete(id)),
    findRequest: jest.fn(async (id: string) => {
      const r = requests.get(id);
      return r ? { ...r, participant: { name: 'Deepa', phone: '+919876543210' }, session } : null;
    }),
    transitionRequest: jest.fn(async (id: string, from: string[], data: any) => {
      const r = requests.get(id);
      if (!r || !from.includes(r.status)) return false;
      Object.assign(r, data);
      return true;
    }),
    claimRequest: jest.fn(async () => true),
    setOrderWaiterIfEmpty: jest.fn(),
    setAgeConfirmed: jest.fn(async (_id: string, at: Date) => { session.ageConfirmedAt = at; }),
    findOpenServiceRequest: jest.fn(async (_s: string, type: string) => serviceRequests.find((x) => x.type === type && x.status !== 'DONE') ?? null),
    createServiceRequest: jest.fn(async (data: any) => {
      const s = { id: `sr${serviceRequests.length + 1}`, status: 'OPEN', createdAt: new Date(), ...data };
      serviceRequests.push(s);
      return s;
    }),
    tableNames: jest.fn(async () => [{ id: 't1', name: 'R4' }]),
    userNames: jest.fn(async () => [{ id: 'w1', displayName: 'Ravi', username: 'ravi' }]),
    findQrGuestUser: jest.fn(async () => ({ id: 'qr', username: 'qr-guest' })),
    transaction: jest.fn(async (fn: any) => fn({})),
    orderState: jest.fn(),
    countParticipants: jest.fn(async () => 2),
    touchParticipant: jest.fn(async () => undefined),
  };
  const orders: any = {
    create: jest.fn(async () => ({ id: 'order1' })),
    addItems: jest.fn(async () => ({})),
    send: jest.fn(async () => ({ tickets: [{ id: 'k1', kind: 'KOT' }] })),
  };
  const configSvc: any = { get: jest.fn(async () => config) };
  const menus = new GuestMenuService({} as any, {} as any, {} as any, {} as any);
  jest.spyOn(menus, 'build').mockResolvedValue(menu);
  const views: any = { forOrder: jest.fn(async () => null) };
  const events: any = {
    orderChanged: jest.fn(), requestNew: jest.fn(), requestDecided: jest.fn(),
    serviceRequestNew: jest.fn(), serviceRequestUpdated: jest.fn(), sessionClosed: jest.fn(),
  };
  const limiter = new GuestRateLimiter();
  const svc = new GuestOrderingService(repo, configSvc, menus, views, orders, limiter, {} as any, events);
  const audit: any = { record: jest.fn() };
  const lifecycle: any = { ensurePin: jest.fn(), closeSession: jest.fn() };
  const staffSvc = new GuestRequestsService(repo, orders, audit, lifecycle, configSvc, menus, events);
  return { svc, staffSvc, repo, orders, events, requests, session, audit, serviceRequests };
}

const wings = { productId: PRODUCT, quantity: 2, modifiers: [] };

describe('GuestOrderingService rounds', () => {
  it('DIRECT round adds the lines as the guest actor and sends tickets; round CONFIRMED', async () => {
    const t = setup(cfg({ routing: 'DIRECT' }));
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    expect(t.orders.create).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'DINE_IN', tableId: 't1', source: 'GUEST_QR', guestSessionId: 's1', waiterId: null }),
      expect.objectContaining({ userId: 'qr' }),
    );
    const [orderId, dto, actor] = t.orders.addItems.mock.calls[0];
    expect(orderId).toBe('order1');
    expect(actor.userId).toBe('qr');
    expect(dto.items[0]).toEqual(expect.objectContaining({ productId: PRODUCT, quantity: 2, guestName: 'Deepa', guestRequestId: round.id }));
    expect(t.orders.send).toHaveBeenCalledWith('order1', actor);
    expect(t.requests.get(round.id).status).toBe('CONFIRMED');
    expect(t.events.requestNew).not.toHaveBeenCalled();
  });

  it('WAITER round waits (PENDING, no order lines), then confirm adds as the waiter and sends', async () => {
    const t = setup();
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    expect(t.requests.get(round.id).status).toBe('PENDING');
    expect(t.orders.addItems).not.toHaveBeenCalled();
    expect(t.events.requestNew).toHaveBeenCalledWith(expect.objectContaining({ requestId: round.id, table: 'R4', by: 'Deepa', total: '600.00' }));

    const row: any = await t.staffSvc.confirm(round.id, {}, staff);
    const [, dto, actor] = t.orders.addItems.mock.calls[0];
    expect(actor.userId).toBe('w1');
    expect(dto.items[0].guestName).toBe('Deepa');
    expect(t.orders.send).toHaveBeenCalledWith('order1', staff);
    expect(t.repo.setOrderWaiterIfEmpty).toHaveBeenCalledWith('order1', 'w1');
    expect(t.audit.record).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ action: 'guest.round.confirm' }));
    expect(row.status).toBe('CONFIRMED');
    expect(row.claimedBy).toEqual({ id: 'w1', name: 'Ravi' });
    await expect(t.staffSvc.confirm(round.id, {}, staff)).rejects.toMatchObject({ response: { code: 'REQUEST_NOT_PENDING' } });
  });

  it('edited confirm sends the edited lines and audits before/after', async () => {
    const t = setup();
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    await t.staffSvc.confirm(round.id, { items: [{ productId: PRODUCT, quantity: 1, modifiers: [{ groupId: GROUP, optionId: OPT }] }] }, staff);
    const [, dto] = t.orders.addItems.mock.calls[0];
    expect(dto.items).toHaveLength(1);
    expect(dto.items[0]).toEqual(expect.objectContaining({ quantity: 1, modifierOptionIds: [OPT] }));
    const entry = t.audit.record.mock.calls[0][1];
    expect(entry.action).toBe('guest.round.confirm_edited');
    expect(entry.metadata.before[0].quantity).toBe(2);
    expect(entry.metadata.after[0]).toEqual(expect.objectContaining({ quantity: 1, unitPrice: '320.00', lineTotal: '320.00' }));
  });

  it('a failed send puts the round back to PENDING', async () => {
    const t = setup();
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    t.orders.addItems.mockRejectedValueOnce(new Error('ITEM_86'));
    await expect(t.staffSvc.confirm(round.id, {}, staff)).rejects.toThrow('ITEM_86');
    expect(t.requests.get(round.id).status).toBe('PENDING');
  });

  it('reject keeps the reason for the guest', async () => {
    const t = setup();
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    const row: any = await t.staffSvc.reject(round.id, { reason: 'Kitchen closed' }, staff);
    expect(row.status).toBe('REJECTED');
    expect(row.rejectReason).toBe('Kitchen closed');
    expect(t.orders.addItems).not.toHaveBeenCalled();
    expect(t.events.requestDecided).toHaveBeenCalledWith(expect.objectContaining({ status: 'REJECTED' }));
  });

  it('guest cancels own PENDING round; not a sent one; not another table', async () => {
    const t = setup();
    const round = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    await t.svc.cancelRound(guest, round.id);
    expect(t.requests.get(round.id).status).toBe('CANCELLED');
    await expect(t.svc.cancelRound(guest, round.id)).rejects.toMatchObject({ response: { code: 'ROUND_NOT_PENDING' } });
    const other = { ...guest, sessionId: 's2', participantId: 'p9', tableId: 't9' };
    await expect(t.svc.cancelRound(other, round.id)).rejects.toMatchObject({ response: { code: 'ROUND_NOT_FOUND' } });
  });

  it('a guest of another (closed or unknown) session cannot read or order', async () => {
    const t = setup();
    const other = { ...guest, sessionId: 's2' };
    await expect(t.svc.order(other)).rejects.toMatchObject({ response: { code: 'SESSION_CLOSED' } });
    await expect(t.svc.placeRound(other, { roundKey: 'x', items: [wings] })).rejects.toMatchObject({ response: { code: 'SESSION_CLOSED' } });
  });

  it('same roundKey returns the same round and creates nothing new', async () => {
    const t = setup(cfg({ routing: 'DIRECT' }));
    const a = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    const b = await t.svc.placeRound(guest, { roundKey: 'k1', items: [wings] });
    expect(b.id).toBe(a.id);
    expect(t.repo.createRequest).toHaveBeenCalledTimes(1);
    expect(t.orders.send).toHaveBeenCalledTimes(1);
  });

  it('validates availability, modifiers, limits and seating', async () => {
    const t = setup(cfg({ maxQtyPerLine: 3 }));
    await expect(t.svc.placeRound(guest, { roundKey: 'a', items: [{ productId: U(99), quantity: 1 }] })).rejects.toMatchObject({
      response: { code: 'ITEM_UNAVAILABLE', details: { productIds: [U(99)] } },
    });
    await expect(t.svc.placeRound(guest, { roundKey: 'b', items: [{ ...wings, quantity: 5 }] })).rejects.toMatchObject({ response: { code: 'ROUND_TOO_LARGE' } });
    await expect(
      t.svc.placeRound(guest, { roundKey: 'c', items: [{ ...wings, modifiers: [{ groupId: GROUP, optionId: U(77) }] }] }),
    ).rejects.toMatchObject({ response: { code: 'MODIFIER_RULE' } });
    t.repo.findTable.mockResolvedValueOnce({ id: 't1', name: 'R4', status: 'FREE', qrEnabled: true });
    await expect(t.svc.placeRound(guest, { roundKey: 'd', items: [wings] })).rejects.toMatchObject({ response: { code: 'TABLE_NOT_SEATED' } });
    const off = setup(cfg({ enabled: false }));
    await expect(off.svc.placeRound(guest, { roundKey: 'e', items: [wings] })).rejects.toMatchObject({ response: { code: 'GUEST_ORDERING_OFF' } });
  });

  it('age gate: alcohol needs age-confirm first', async () => {
    const t = setup();
    await expect(t.svc.placeRound(guest, { roundKey: 'a', items: [{ productId: BEER, quantity: 1 }] })).rejects.toMatchObject({
      status: 403,
      response: { code: 'AGE_NOT_CONFIRMED' },
    });
    await t.svc.ageConfirm(guest);
    await expect(t.svc.placeRound(guest, { roundKey: 'b', items: [{ productId: BEER, quantity: 1 }] })).resolves.toBeDefined();
    const noGate = setup(cfg({ ageGate: false }));
    await expect(noGate.svc.placeRound(guest, { roundKey: 'c', items: [{ productId: BEER, quantity: 1 }] })).resolves.toBeDefined();
  });
});

describe('GuestOrderingService checkout', () => {
  it('WAITER creates one BILL request; repeat taps return the same one', async () => {
    const t = setup();
    const a = await t.svc.checkout(guest, { mode: 'WAITER' });
    const b = await t.svc.checkout(guest, { mode: 'WAITER' });
    expect(a).toEqual({ mode: 'WAITER', requestId: 'sr1' });
    expect(b.requestId).toBe('sr1');
    expect(t.serviceRequests).toHaveLength(1);
    expect(t.events.serviceRequestNew).toHaveBeenCalledTimes(1);
    expect(t.events.serviceRequestNew).toHaveBeenCalledWith(expect.objectContaining({ table: 'R4', type: 'BILL' }));
  });

  it('ONLINE is 501 NOT_AVAILABLE', async () => {
    const t = setup();
    await expect(t.svc.checkout(guest, { mode: 'ONLINE' })).rejects.toMatchObject({ status: 501, response: { code: 'NOT_AVAILABLE' } });
  });
});

describe('guest line state derivation', () => {
  it.each([
    ['SENT', 'NEW', 'SENT'],
    ['SENT', 'PREPARING', 'COOKING'],
    ['SENT', 'READY', 'READY'],
    ['SENT', 'SERVED', 'SERVED'],
    ['SERVED', 'READY', 'SERVED'],
    ['VOIDED', 'READY', 'CANCELLED'],
    ['NEW', undefined, 'WAITING_WAITER'],
    ['SENT', undefined, 'SENT'],
  ])('line %s + ticket %s -> %s', (line, ticket, want) => {
    expect(lineState(line, ticket)).toBe(want);
  });

  it('round-only lines and order status', () => {
    expect(roundOnlyState('PENDING')).toBe('WAITING_WAITER');
    expect(roundOnlyState('REJECTED')).toBe('CANCELLED');
    expect(roundOnlyState('EXPIRED')).toBe('CANCELLED');
    expect(guestOrderStatus('SENT')).toBe('OPEN');
    expect(guestOrderStatus('BILLED')).toBe('BILLED');
    expect(guestOrderStatus('PAID')).toBe('PAID');
    expect(guestOrderStatus('CLOSED')).toBe('CLOSED');
  });

  it('finds the ticket of each line through items[].orderItemId', () => {
    const m = ticketStatusByLine([
      { items: [{ orderItemId: 'i1' }, { orderItemId: 'i2' }], kdsStatus: 'READY', createdAt: new Date(1) },
      { items: [{ orderItemId: 'i3' }], kdsStatus: 'PREPARING', createdAt: new Date(2) },
    ]);
    expect(m.get('i2')?.status).toBe('READY');
    expect(m.get('i3')?.status).toBe('PREPARING');
    expect(m.has('i9')).toBe(false);
  });
});

describe('GuestOrderViewService totals', () => {
  it('includes PENDING rounds priced at today\'s price, marked estimate', async () => {
    const D = (v: number | string) => new Prisma.Decimal(v);
    const taxBreakdown = { snapshot: { taxClassId: null, code: 'G5', name: 'GST', rate: '5.00', inclusive: false, isLiquor: false, components: [{ name: 'GST', rate: 5 }] } };
    const item = {
      id: 'i1', productId: PRODUCT, productName: 'Chicken Wings', variantName: null, quantity: 1, price: D(300), status: 'SENT',
      lineTotal: D(315), modifiers: [], guestRequestId: 'r1', createdAt: new Date(), sentAt: new Date(), voidedAt: null, taxBreakdown,
    };
    const bundle = { order: { id: 'order1', status: 'SENT', outletId: 'o1', type: 'DINE_IN', tableId: 't1' }, items: [item], discounts: [], payments: [] };
    const repo: any = {
      orderState: jest.fn(async () => ({ id: 'order1', tenantId: 'ten', tableId: 't1', guestSessionId: 's1' })),
      requestsForOrder: jest.fn(async () => [
        { id: 'r1', status: 'CONFIRMED', participantId: 'p1', participant: { name: 'Deepa' }, items: [], rejectReason: null, createdAt: new Date(), decidedAt: null },
        { id: 'r2', status: 'PENDING', participantId: 'p2', participant: { name: 'Arun' }, items: [{ productId: PRODUCT, quantity: 2, modifiers: [], name: 'Chicken Wings' }], rejectReason: null, createdAt: new Date(), decidedAt: null },
      ]),
      ticketsForOrder: jest.fn(async () => [{ items: [{ orderItemId: 'i1' }], kdsStatus: 'PREPARING', createdAt: new Date() }]),
      findTable: jest.fn(async () => ({ name: 'R4' })),
      countParticipants: jest.fn(async () => 2),
      findOpenServiceRequest: jest.fn(async () => null),
    };
    const { frozenLineInput, ZERO } = jest.requireActual('../orders/order-pricing');
    const orders: any = { transaction: (fn: any) => fn({}), loadBundle: jest.fn(async () => bundle) };
    const pricing: any = {
      inputFor: jest.fn(async (_tx: any, b: any) => ({
        input: { lines: b.items.map(frozenLineInput), discounts: [], serviceChargePercent: ZERO, roundingMode: 'NONE' },
      })),
    };
    const lines: any = {
      context: jest.fn(async () => ({})),
      resolve: jest.fn(async () => ({ unitPrice: D(300), snapshot: taxBreakdown.snapshot })),
    };
    const svc = new GuestOrderViewService(repo, orders, pricing, lines, { get: async () => cfg() } as any);
    const view = (await svc.forOrder('order1', 'p1'))!;
    expect(view.totals.grandTotal).toBe('945.00'); // 315 sent + 2 x 315 pending
    expect(view.totals.pendingEstimate).toBe('630.00');
    expect(view.totals.estimate).toBe(true);
    expect(view.atTable).toBe(2);
    expect(view.rounds[0]).toEqual(expect.objectContaining({ by: 'Deepa', mine: true, status: 'CONFIRMED' }));
    expect(view.rounds[0].lines[0].state).toBe('COOKING');
    expect(view.rounds[1]).toEqual(expect.objectContaining({ by: 'Arun', mine: false, status: 'PENDING' }));
    expect(view.rounds[1].lines[0]).toEqual(expect.objectContaining({ state: 'WAITING_WAITER', lineTotal: '630.00', estimate: true }));
  });
});

describe('GuestLifecycleService', () => {
  function life(method: 'STATIC_OTP' | 'TABLE_PIN' = 'STATIC_OTP') {
    const repo: any = {
      closeSession: jest.fn(async () => true),
      orderState: jest.fn(),
      findSession: jest.fn(async () => ({ id: 's1', tableId: 't1', status: 'OPEN' })),
      countOpenOrdersOnTable: jest.fn(async () => 0),
      expiredPending: jest.fn(async () => [{ id: 'r1', orderId: 'order1', outletId: 'o1', claimedById: null }]),
      transitionRequest: jest.fn(async () => true),
      blankOldPhones: jest.fn(async () => ({ count: 3 })),
      moveSession: jest.fn(),
      rotateTableQr: jest.fn(),
      findTable: jest.fn(),
      openSessionForTable: jest.fn(async () => ({ id: 's1' })),
    };
    const pins: any = { generate: jest.fn(async () => '4817') };
    const events: any = { orderChanged: jest.fn(), sessionClosed: jest.fn(), requestDecided: jest.fn() };
    const guard: any = { forget: jest.fn() };
    const svc = new GuestLifecycleService(repo, { get: async () => cfg({ verification: { method, staticOtpHash: null, codeLength: 6 } }) } as any, pins, events, guard);
    return { svc, repo, pins, events, guard };
  }

  it('closing a session rotates the QR token, clears the PIN, revokes tokens and tells the table', async () => {
    const t = life();
    await t.svc.closeSession('s1', 't1');
    const [sid, tid, token] = t.repo.closeSession.mock.calls[0];
    expect([sid, tid]).toEqual(['s1', 't1']);
    expect(token).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(t.guard.forget).toHaveBeenCalledWith('s1');
    expect(t.events.sessionClosed).toHaveBeenCalledWith('s1', 't1');
  });

  it('order CLOSED (or table CLEANING) closes the session after the last order update', async () => {
    const t = life();
    t.repo.orderState.mockResolvedValue({ id: 'order1', status: 'CLOSED', tableId: 't1', tenantId: 'ten', guestSessionId: 's1', table: { id: 't1', status: 'CLEANING', guestPin: null } });
    await t.svc.onOrderChanged('order1');
    expect(t.events.orderChanged).toHaveBeenCalledWith('order1');
    expect(t.repo.closeSession).toHaveBeenCalled();
  });

  it('open order keeps the session; table FREE by staff closes it', async () => {
    const t = life();
    t.repo.orderState.mockResolvedValue({ id: 'order1', status: 'SENT', tableId: 't1', tenantId: 'ten', guestSessionId: 's1', table: { id: 't1', status: 'OCCUPIED', guestPin: null } });
    await t.svc.onOrderChanged('order1');
    expect(t.repo.closeSession).not.toHaveBeenCalled();
    t.repo.findTable.mockResolvedValue({ id: 't1', tenantId: 'ten', status: 'FREE', guestPin: null });
    await t.svc.onTableChanged('t1');
    expect(t.repo.closeSession).toHaveBeenCalled();
  });

  it('seating a table in TABLE_PIN mode generates a PIN once', async () => {
    const t = life('TABLE_PIN');
    expect(await t.svc.ensurePin('ten', { id: 't1', status: 'OCCUPIED', guestPin: null })).toBe('4817');
    expect(await t.svc.ensurePin('ten', { id: 't1', status: 'OCCUPIED', guestPin: '1111' })).toBe('1111');
    expect(await t.svc.ensurePin('ten', { id: 't1', status: 'FREE', guestPin: null })).toBeNull();
    expect(t.pins.generate).toHaveBeenCalledTimes(1);
    const otp = life('STATIC_OTP');
    expect(await otp.svc.ensurePin('ten', { id: 't1', status: 'OCCUPIED', guestPin: null })).toBeNull();
  });

  it('expires PENDING rounds past their TTL and tells staff and guests', async () => {
    const t = life();
    expect(await t.svc.expireRequests(new Date())).toBe(1);
    expect(t.repo.transitionRequest).toHaveBeenCalledWith('r1', ['PENDING'], expect.objectContaining({ status: 'EXPIRED' }));
    expect(t.events.requestDecided).toHaveBeenCalledWith(expect.objectContaining({ requestId: 'r1', status: 'EXPIRED' }));
    expect(t.events.orderChanged).toHaveBeenCalledWith('order1');
  });

  it('blanks phones older than 90 days', async () => {
    const t = life();
    const now = new Date('2026-11-26T00:00:00Z');
    expect(await t.svc.blankOldPhones(now)).toBe(3);
    const before: Date = t.repo.blankOldPhones.mock.calls[0][0];
    expect(Math.round((now.getTime() - before.getTime()) / 86_400_000)).toBe(90);
  });
});
