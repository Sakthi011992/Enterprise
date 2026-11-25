import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { TabsService } from './tabs.service';
import { PermissionsService } from '../personas/permissions.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string; details?: Record<string, unknown> };

const auth = (permissions: AuthUser['permissions']) =>
  ({ userId: 'u1', username: 'bartender', tenantId: 't1', outletId: 'o1', personaId: 'p1', personaKey: 'bartender', role: 'USER', permissions }) as AuthUser;

const LIMITED = { 'sales.tab.open': { level: 'LIMITED', limit: 5000 } } as AuthUser['permissions'];
const APPROVE = { 'sales.tab.open': { level: 'APPROVE', limit: null } } as AuthUser['permissions'];

function tabRow(over: Record<string, unknown> = {}) {
  return {
    id: 'tab1', tenantId: 't1', outletId: 'o1', number: 'T-07', businessDate: new Date('2026-11-25'), orderId: 'ord1',
    guestName: 'Karthik R', mobile: null, ageChecked: true, security: 'CASH_DEPOSIT', cardLast4: null, amountHeld: D(2000),
    houseAccount: null, tabLimit: D(5000), warnAtPercent: 80, warnedAt: null, linkType: 'BAR_SEAT', linkLabel: 'Bar seat 3',
    tableId: null, status: 'OPEN', approvalId: null, openedById: 'u1', openedAt: new Date('2026-11-25T10:00:00Z'),
    closedAt: null, closedById: null, ...over,
  };
}

/** Builds the service with in-memory fakes. `total` is the order grand total after billing. */
function build(opts: { tab?: ReturnType<typeof tabRow> | null; total?: string; itemCount?: number; permissions?: AuthUser['permissions'] } = {}) {
  const state = { tab: opts.tab === undefined ? tabRow() : opts.tab, total: opts.total ?? '1450.00', itemCount: opts.itemCount ?? 2 };
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    findTab: jest.fn(async () => state.tab),
    listTabs: jest.fn(async () => []),
    countTabsOn: jest.fn(async () => 6),
    createTab: jest.fn(async (_tx: unknown, data: any) => ({ id: 'tab-new', ...data })),
    updateTab: jest.fn(async (_tx: unknown, _id: string, data: any) => Object.assign(state.tab!, data)),
    rowsFor: jest.fn(async (tabs: any[]) =>
      tabs.map((t) => ({ tab: t, order: { id: t.orderId, grandTotal: D(state.total), status: 'BILLED', tableId: null }, table: null, opener: { id: 'u1', name: 'Meera' }, itemCount: state.itemCount })),
    ),
    loadRows: jest.fn(async (_tx: unknown, tabs: any[]) =>
      tabs.map((t) => ({ tab: t, order: { id: t.orderId, grandTotal: D(0), status: 'OPEN', tableId: null }, table: null, opener: null, itemCount: 0 })),
    ),
  };
  const ordersRepo: any = {
    getOutletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    claimTable: jest.fn(async () => 1),
    nextOrderNumber: jest.fn(async () => 'A-1044'),
    createOrder: jest.fn(async (_tx: unknown, data: any) => ({ id: 'ord-new', ...data })),
    setTableStatus: jest.fn(),
    updateOrder: jest.fn(),
    loadBundle: jest.fn(),
  };
  const orders: any = {
    bill: jest.fn(async () => ({ totals: { grandTotal: state.total }, payments: [] })),
    findOne: jest.fn(),
  };
  const payments: any = { pay: jest.fn(async () => ({})) };
  const approvals: any = { assertApproved: jest.fn(async () => ({ approverId: 'm1' })) };
  const audit: any = { record: jest.fn() };
  const permissions = new PermissionsService({} as any);
  const svc = new TabsService(repo, orders, ordersRepo, payments, approvals, permissions, audit);
  return { svc, repo, ordersRepo, orders, payments, approvals, audit, state, permissions, opts };
}

describe('TabsService.open', () => {
  const base = {
    guestName: 'Karthik R',
    ageChecked: true,
    security: 'CARD_PREAUTH' as const,
    cardLast4: '4821',
    amountHeld: 5000,
    tabLimit: 5000,
    linkType: 'BAR_SEAT' as const,
    linkLabel: 'Bar seat 3',
  };

  it('refuses a guest without an age check', async () => {
    const { svc } = build();
    const err = await svc.open({ ...base, ageChecked: false }, auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('AGE_CHECK_REQUIRED');
  });

  it('applies the sales.tab.open limit to the requested tab limit', async () => {
    const { svc, repo } = build();
    const err = await svc.open({ ...base, tabLimit: 6000 }, auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('LIMIT_EXCEEDED');
    expect(repo.createTab).not.toHaveBeenCalled();
  });

  it('needs an approval for a tab with no security unless the caller holds APPROVE', async () => {
    const { svc, approvals, repo } = build();
    const none = { ...base, security: 'NONE' as const, cardLast4: undefined, amountHeld: undefined };

    const err = await svc.open(none, auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('APPROVAL_REQUIRED');

    await svc.open({ ...none, approvalId: 'a1' }, auth(LIMITED));
    expect(approvals.assertApproved).toHaveBeenCalledWith(
      'a1',
      expect.anything(),
      'TAB_NO_SECURITY',
      { guestName: 'Karthik R', tabLimit: 5000 },
      null,
    );
    expect(repo.createTab).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ security: 'NONE', approvalId: 'a1' }));

    const { svc: manager, approvals: noApproval } = build();
    await manager.open({ ...none }, auth(APPROVE));
    expect(noApproval.assertApproved).not.toHaveBeenCalled();
  });

  it('creates a BAR_COUNTER order and the next tab number for the business date', async () => {
    const { svc, ordersRepo, repo } = build();

    const view = await svc.open(base, auth(LIMITED));

    expect(ordersRepo.createOrder).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ type: 'BAR_COUNTER', tableId: null, note: 'Tab T-07 · Karthik R' }),
    );
    expect(repo.createTab).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ number: 'T-07', security: 'CARD_PREAUTH', cardLast4: '4821', tabLimit: D(5000) }),
    );
    expect(view.number).toBe('T-07');
  });

  it('a table link claims the table and creates a DINE_IN order', async () => {
    const { svc, ordersRepo } = build();
    await svc.open({ ...base, linkType: 'TABLE', tableId: 'tb4', linkLabel: undefined }, auth(LIMITED));
    expect(ordersRepo.claimTable).toHaveBeenCalledWith(expect.anything(), 'tb4', 'o1', ['FREE', 'RESERVED'], 'OCCUPIED');
    expect(ordersRepo.createOrder).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ type: 'DINE_IN', tableId: 'tb4' }));
  });
});

describe('TabsService.close', () => {
  it('applies a cash deposit as min(held, total) and returns the rest', async () => {
    const { svc, payments, state } = build({ total: '1450.00' });
    state.tab!.amountHeld = D(2000) as any;

    const res = await svc.close('tab1', auth(LIMITED));

    expect(payments.pay).toHaveBeenCalledWith(
      'ord1',
      { payments: [{ method: 'CASH', amount: 1450, reference: 'TAB_DEPOSIT' }] },
      expect.anything(),
    );
    expect(res.depositApplied).toBe('1450.00');
    expect(res.depositToReturn).toBe('550.00');
  });

  it('does not pay anything for a card pre-auth tab', async () => {
    const { svc, payments } = build({ tab: tabRow({ security: 'CARD_PREAUTH', cardLast4: '4821', amountHeld: D(5000) }) });
    const res = await svc.close('tab1', auth(LIMITED));
    expect(payments.pay).not.toHaveBeenCalled();
    expect(res.depositApplied).toBe('0.00');
  });

  it('refuses an empty tab', async () => {
    const { svc } = build({ itemCount: 0 });
    const err = await svc.close('tab1', auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('TAB_EMPTY');
  });

  it('refuses a tab that is already closed', async () => {
    const { svc } = build({ tab: tabRow({ status: 'CLOSED' }) });
    const err = await svc.close('tab1', auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('TAB_CLOSED');
  });
});

describe('TabsService.voidTab', () => {
  it('only voids a tab with no live lines', async () => {
    const { svc, repo } = build({ itemCount: 1 });
    const err = await svc.voidTab('tab1', { reason: 'Wrong table' }, auth(LIMITED)).catch((e) => e);
    expect(codeOf(err).code).toBe('TAB_NOT_EMPTY');
    expect(repo.updateTab).not.toHaveBeenCalled();
  });
});
