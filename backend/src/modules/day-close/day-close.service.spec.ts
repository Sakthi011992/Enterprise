import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { DayCloseService } from './day-close.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string };
const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', permissions: {} } as unknown as AuthUser;
const emptyFacts = (businessDate: string) => ({
  businessDate, orders: [], payments: [], items: [], discounts: [],
  categoryOfProduct: new Map(), categoryNames: new Map(), userNames: new Map(),
});

function build(openOrders: { id: string; status: string }[], existingZ: boolean) {
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    findZClose: jest.fn(async () => (existingZ ? { id: 'dc0' } : null)),
    ordersInWindow: jest.fn(async () => openOrders),
    factsFor: jest.fn(async (_tx: unknown, _orders: unknown, bd: string) => emptyFacts(bd)),
    createDayClose: jest.fn(async (_tx: unknown, data: any) => ({ id: 'dc1', ...data })),
    linkOrders: jest.fn(),
    listDayCloses: jest.fn(),
  };
  const audit: any = { record: jest.fn() };
  const print: any = { queueReport: jest.fn(async () => ({ id: 'pj1' })), queueReportTotals: jest.fn(async () => ({ id: 'pj2' })) };
  return { svc: new DayCloseService(repo, audit, print), repo, print };
}

describe('DayCloseService.zClose', () => {
  it('refuses to close while orders are open, unless forced', async () => {
    const { svc, repo } = build([{ id: 'o9', status: 'SENT' }], false);

    const err = await svc.zClose(auth, { cashCounted: 1000 }).catch((e) => e);

    expect(codeOf(err)).toMatchObject({ code: 'OPEN_ORDERS_EXIST', details: { count: 1 } });
    expect(repo.createDayClose).not.toHaveBeenCalled();
  });

  it('refuses a second Z close for the same business date', async () => {
    const { svc, repo } = build([], true);

    const err = await svc.zClose(auth, { cashCounted: 1000 }).catch((e) => e);

    expect(err).toBeInstanceOf(HttpException);
    expect(codeOf(err).code).toBe('DAY_ALREADY_CLOSED');
    expect(repo.createDayClose).not.toHaveBeenCalled();
  });

  it('saves the Z close, links the day orders and queues the report', async () => {
    const { svc, repo, print } = build([{ id: 'o1', status: 'PAID' }], false);

    const res = await svc.zClose(auth, { cashCounted: 500 });

    expect(repo.createDayClose).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ kind: 'Z' }));
    expect(repo.linkOrders).toHaveBeenCalledWith(expect.anything(), ['o1'], 'dc1');
    expect(print.queueReport).toHaveBeenCalledWith('dc1');
    expect(res.cashCounted).toBe('500.00');
    expect(res.cashExpected).toBe('0.00');
    expect(res.variance).toBe('500.00');
  });
});
