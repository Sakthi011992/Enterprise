import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { TabsLimitService } from './tabs-limit.service';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string; details?: Record<string, unknown> };
const now = new Date('2026-11-25T12:00:00Z');

function tabRow(over: Record<string, unknown> = {}) {
  return {
    id: 'tab1',
    tenantId: 't1',
    outletId: 'o1',
    number: 'T-07',
    businessDate: new Date('2026-11-25'),
    orderId: 'ord1',
    guestName: 'Karthik R',
    mobile: null,
    ageChecked: true,
    security: 'CARD_PREAUTH',
    cardLast4: '4821',
    amountHeld: D(5000),
    houseAccount: null,
    tabLimit: D(5000),
    warnAtPercent: 90,
    warnedAt: null,
    linkType: 'BAR_SEAT',
    linkLabel: 'Bar seat 3',
    tableId: null,
    status: 'OPEN',
    approvalId: null,
    openedById: 'u1',
    openedAt: new Date('2026-11-25T10:00:00Z'),
    closedAt: null,
    closedById: null,
    ...over,
  };
}

function build(state: { tab: ReturnType<typeof tabRow> | null; total: Prisma.Decimal }) {
  const repo: any = {
    findOpenTabByOrder: jest.fn(async () => state.tab),
    orderGrandTotal: jest.fn(async () => state.total),
    updateTab: jest.fn(async (_tx: unknown, _id: string, data: Record<string, unknown>) => Object.assign(state.tab!, data)),
    createNotification: jest.fn(async () => ({})),
    loadRows: jest.fn(async (_tx: unknown, tabs: any[]) =>
      tabs.map((t) => ({ tab: t, order: { id: 'ord1', grandTotal: state.total, status: 'SENT', tableId: null }, table: null, opener: null, itemCount: 2 })),
    ),
  };
  return { svc: new TabsLimitService(repo), repo };
}

describe('TabsLimitService', () => {
  it('refuses a total above the limit with the spent and attempted amounts', async () => {
    const state = { tab: tabRow(), total: D(5100) };
    const { svc } = build(state);

    const err = await svc.enforce({} as any, 'ord1', D(4700), now).catch((e) => e);

    expect(codeOf(err).code).toBe('TAB_LIMIT_REACHED');
    expect(codeOf(err).details).toMatchObject({ number: 'T-07', limit: '5000.00', spent: '4700.00', attempted: '5100.00' });
  });

  it('warns once when spent crosses the warning level, and notifies the opener', async () => {
    const state = { tab: tabRow(), total: D(4700) };
    const { svc, repo } = build(state);

    const first = await svc.enforce({} as any, 'ord1', D(4000), now);
    expect(first).toHaveLength(1);
    expect(first[0]).toMatchObject({ scope: 'outlet', outletId: 'o1', event: 'tab.nearLimit' });
    expect(repo.createNotification).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ userId: 'u1', type: 'alert', title: expect.stringContaining('94% of its ₹5,000 limit') }),
    );

    const second = await svc.enforce({} as any, 'ord1', D(4700), now);
    expect(second).toEqual([]);
    expect(repo.createNotification).toHaveBeenCalledTimes(1);
  });

  it('stays quiet below the warning level', async () => {
    const state = { tab: tabRow(), total: D(4000) };
    const { svc, repo } = build(state);

    expect(await svc.enforce({} as any, 'ord1', D(0), now)).toEqual([]);
    expect(repo.createNotification).not.toHaveBeenCalled();
  });

  it('does nothing for an order without an open tab', async () => {
    const state = { tab: null, total: D(9999) };
    const { svc, repo } = build(state);

    expect(await svc.enforce({} as any, 'ord1', D(0), now)).toEqual([]);
    expect(repo.orderGrandTotal).not.toHaveBeenCalled();
  });

  it('closes the tab when its order is paid', async () => {
    const state = { tab: tabRow(), total: D(1450) };
    const { svc, repo } = build(state);

    await svc.onOrderPaid({} as any, 'ord1', now);

    expect(repo.updateTab).toHaveBeenCalledWith(expect.anything(), 'tab1', { status: 'CLOSED', closedAt: now });
  });
});
