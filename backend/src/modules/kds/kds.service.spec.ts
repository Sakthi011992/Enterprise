import { HttpException } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { PermissionsService } from '../personas/permissions.service';
import { KdsService } from './kds.service';
import { KdsOrderContext } from './kds-view';

const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string; details?: Record<string, unknown> };

const user = (permissions: AuthUser['permissions']) =>
  ({ userId: 'u1', username: 'chef', tenantId: 't1', outletId: 'o1', personaId: 'p1', personaKey: 'chef', role: 'USER', permissions }) as AuthUser;

const CHEF = user({ 'kds.bump': { level: 'EDIT', limit: null } } as AuthUser['permissions']);
const WAITER = user({ 'sales.orders.take': { level: 'EDIT', limit: null } } as AuthUser['permissions']);

function ticket(over: Record<string, unknown> = {}) {
  return {
    id: 'tk1', tenantId: 't1', outletId: 'o1', orderId: 'ord1', kind: 'BOT', station: 'BAR', seq: 4, isCancellation: false,
    kdsStatus: 'NEW', createdAt: new Date('2026-11-25T12:00:00Z'), startedAt: null, readyAt: null, servedAt: null,
    createdById: 'u2',
    items: [
      { orderItemId: 'l1', name: 'Lager', variantName: null, quantity: 4, modifiers: [], note: null, seat: null },
      { orderItemId: 'w1', name: 'House Whisky', variantName: '60 ml', quantity: 6, modifiers: [], note: null, seat: null },
    ],
    ...over,
  };
}

const ctx: KdsOrderContext = {
  id: 'ord1', orderNumber: 'A-1044', type: 'DINE_IN', covers: 2, tableName: 'R4', tabNumber: 'T-07',
  waiterId: 'u9', waiterName: 'Meera', itemStatus: new Map([['l1', 'SENT'], ['w1', 'SENT']]),
};

function build(row = ticket(), opts: { ready?: boolean; board?: any } = {}) {
  const state = { row: row as any };
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    findTicket: jest.fn(async () => state.row),
    updateTicket: jest.fn(async (_tx: unknown, _id: string, data: any) => {
      state.row = { ...state.row, ...data };
      return state.row;
    }),
    loadContext: jest.fn(async () => new Map([['ord1', ctx]])),
    markItemsServed: jest.fn(async () => ({ count: 2 })),
    createNotification: jest.fn(async () => ({})),
    outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    dayTickets: jest.fn(async () => opts.board?.day ?? []),
    activeTickets: jest.fn(async () => opts.board?.active ?? []),
    servedSince: jest.fn(async () => []),
    readyTickets: jest.fn(async () => (opts.ready ? [ticket({ kdsStatus: 'READY', readyAt: new Date('2026-11-25T12:02:00Z') })] : [])),
  };
  const realtime: any = { publish: jest.fn() };
  const permissions = new PermissionsService({} as any);
  return { svc: new KdsService(repo, permissions, realtime), repo, realtime, state };
}

describe('KdsService transitions', () => {
  it('refuses start on a ticket that is already READY', async () => {
    const { svc } = build(ticket({ kdsStatus: 'READY', readyAt: new Date() }));
    const err = await svc.start('tk1', CHEF).catch((e) => e);
    expect(codeOf(err).code).toBe('KDS_BAD_STATE');
    expect(codeOf(err).details).toEqual({ status: 'READY' });
  });

  it('bump moves the ticket to READY, tells the waiter, and publishes the card and the ready item', async () => {
    const { svc, repo, realtime } = build();

    const card = await svc.bump('tk1', CHEF);

    expect(card.kdsStatus).toBe('READY');
    expect(repo.createNotification).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: 'u9', type: 'ready', title: 'Ready at the bar · R4', body: '4 × Lager, 6 × House Whisky' }),
    );
    const events = realtime.publish.mock.calls[0][0];
    expect(events.map((e: any) => [e.scope, e.event])).toEqual([
      ['station', 'kds.ticket.updated'],
      ['user', 'kds.ready'],
      ['outlet', 'kds.ready'],
    ]);
    expect(events[1].userId).toBe('u9');
  });

  it('served marks the ticket SERVED and its lines SERVED', async () => {
    const { svc, repo } = build(ticket({ kdsStatus: 'READY', readyAt: new Date() }));
    await svc.served('tk1', CHEF);
    expect(repo.markItemsServed).toHaveBeenCalledWith(expect.anything(), ['l1', 'w1']);
  });

  it('served needs sales.orders.take EDIT or kds.bump EDIT', async () => {
    const { svc } = build(ticket({ kdsStatus: 'READY', readyAt: new Date() }));
    const err = await svc.served('tk1', user({})).catch((e) => e);
    expect(codeOf(err).code).toBe('PERMISSION_DENIED');
    await expect(svc.served('tk1', WAITER)).resolves.toMatchObject({ kdsStatus: 'SERVED' });
  });

  it('recall refuses a SERVED ticket older than 30 minutes', async () => {
    const { svc } = build(ticket({ kdsStatus: 'SERVED', servedAt: new Date(Date.now() - 31 * 60_000) }));
    const err = await svc.recall('tk1', CHEF).catch((e) => e);
    expect(codeOf(err).code).toBe('RECALL_TOO_LATE');
  });

  it('a ticket from another outlet is not found', async () => {
    const { svc, repo } = build();
    repo.findTicket.mockResolvedValueOnce(null);
    const err = await svc.bump('tk1', CHEF).catch((e) => e);
    expect(codeOf(err).code).toBe('TICKET_NOT_FOUND');
  });
});

describe('KdsService board', () => {
  it('all-day totals skip served tickets and voided lines', async () => {
    const served = ticket({ id: 'old', kdsStatus: 'SERVED', servedAt: new Date(), readyAt: new Date() });
    const live = ticket({ id: 'new', kdsStatus: 'NEW' });
    const { svc, repo } = build(ticket(), { board: { day: [served, live], active: [live] } });
    repo.loadContext.mockResolvedValueOnce(
      new Map([['ord1', { ...ctx, itemStatus: new Map([['l1', 'SENT'], ['w1', 'VOIDED']]) }]]),
    );

    const board = await svc.board({ view: 'active' }, CHEF);

    expect(board.allDay).toEqual([{ name: 'Lager', variantName: null, quantity: 4 }]);
    expect(board.tickets.map((t) => t.label)).toEqual(['BOT 4']);
    expect(board.tickets[0].items.find((i) => i.orderItemId === 'w1')).toMatchObject({ voided: true });
  });
});
