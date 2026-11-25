import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { CountsService } from './counts.service';

const D = (v: number | string) => new Prisma.Decimal(v);

function autoMock(overrides: Record<string, unknown> = {}): any {
  const store: Record<string, unknown> = { ...overrides };
  return new Proxy(store, {
    get(target, prop) {
      if (typeof prop === 'symbol') return undefined;
      if (!(prop in target)) target[prop] = jest.fn();
      return target[prop];
    },
  });
}

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', username: 'store', permissions: {} } as unknown as AuthUser;

async function codeOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
  } catch (e) {
    return ((e as HttpException).getResponse() as { code: string }).code;
  }
  throw new Error('expected an error');
}

/** Count at the Bar with three lines: Single Malt counted 9 of 12 expected, Vodka counted 5 of 5, Lager not counted. */
function setup(status: string, lines: any[] = []) {
  const count = { id: 'c1', tenantId: 't1', outletId: 'o1', locationId: 'bar', status, businessDate: new Date('2026-11-25T00:00:00Z'), startedById: 'u1', submittedAt: null, postedAt: null, postedById: null, note: null, createdAt: new Date() } as any;
  const items = [
    { id: 'malt', name: 'Single Malt 12Y 750 ml', baseUnit: 'ML', packSize: D(750), packName: 'btl', avgCost: D('4.16'), isActive: true },
    { id: 'vodka', name: 'Premium Vodka 750 ml', baseUnit: 'ML', packSize: D(750), packName: 'btl', avgCost: D('1.93'), isActive: true },
    { id: 'lager', name: 'Premium Lager 650 ml', baseUnit: 'ML', packSize: D(650), packName: 'btl', avgCost: D('0.12'), isActive: true },
  ];
  const repo = autoMock({
    transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn({})),
    findCount: jest.fn(async () => count),
    claimSubmittedCount: jest.fn(async () => 1),
    countLines: jest.fn(async () => lines),
    levelsForLocations: jest.fn(async () => [
      { locationId: 'bar', stockItemId: 'malt', onHand: D(12), parLevel: D(6) },
      { locationId: 'bar', stockItemId: 'vodka', onHand: D(5), parLevel: D(0) },
    ]),
    findItemsByIds: jest.fn(async (ids: string[]) => items.filter((i) => ids.includes(i.id))),
    findLocationsByIds: jest.fn(async () => [{ id: 'bar', name: 'Bar' }]),
    findUsers: jest.fn(async () => [{ id: 'u1', username: 'store', displayName: 'Store' }]),
    countAdjustmentsOf: jest.fn(async () => []),
    outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
  });
  const ledger = autoMock({ post: jest.fn(async (_tx: unknown, _ctx: unknown, inputs: unknown[]) => inputs) });
  const realtime = autoMock({ publish: jest.fn() });
  const service = new CountsService(repo, ledger, realtime);
  return { service, repo, ledger, count };
}

const line = (stockItemId: string, countedQty: string | null, expectedQty: string | null) => ({
  id: `l-${stockItemId}`, countId: 'c1', stockItemId, countedQty: countedQty === null ? null : D(countedQty),
  expectedQty: expectedQty === null ? null : D(expectedQty), note: null, confirmedOutlier: false, countedAt: null, countedById: null,
});

describe('CountsService submit', () => {
  it('snapshots the on-hand quantity as the expected quantity', async () => {
    const { service, repo } = setup('OPEN', [line('malt', '9', null), line('vodka', '5', null)]);
    await service.submit('c1', auth);
    const calls = repo.setCountLineExpected.mock.calls.map((c: any[]) => [c[2], c[3].toFixed(3)]);
    expect(calls).toEqual([
      ['malt', '12.000'],
      ['vodka', '5.000'],
    ]);
    expect(repo.updateCount).toHaveBeenCalledWith(expect.anything(), 'c1', expect.objectContaining({ status: 'SUBMITTED' }));
  });

  it('refuses a count with nothing counted', async () => {
    const { service } = setup('OPEN', [line('malt', null, null)]);
    expect(await codeOf(service.submit('c1', auth))).toBe('NOTHING_COUNTED');
  });
});

describe('CountsService post', () => {
  it('posts COUNT_ADJUST as counted minus expected, for counted lines only', async () => {
    const { service, ledger, repo } = setup('SUBMITTED', [
      line('malt', '9', '12'),
      line('vodka', '5', '5'),
      line('lager', null, '40'),
    ]);
    await service.post('c1', auth);
    const inputs = ledger.post.mock.calls[0][2] as any[];
    expect(inputs).toHaveLength(1);
    expect(inputs[0]).toMatchObject({ type: 'COUNT_ADJUST', stockItemId: 'malt', refType: 'COUNT', refId: 'c1' });
    expect(inputs[0].qty.toFixed(3)).toBe('-3.000');
    expect(repo.updateCount).toHaveBeenCalledWith(expect.anything(), 'c1', expect.objectContaining({ status: 'POSTED' }));
  });

  it('refuses to post a count that was not submitted', async () => {
    const { service } = setup('OPEN', [line('malt', '9', null)]);
    expect(await codeOf(service.post('c1', auth))).toBe('COUNT_NOT_SUBMITTED');
  });
});

describe('CountsService start', () => {
  it('refuses a second live count at the same location', async () => {
    const { service, repo } = setup('OPEN');
    repo.findLocation.mockResolvedValue({ id: 'bar', name: 'Bar' });
    repo.findLiveCount.mockResolvedValue({ id: 'c0' });
    expect(await codeOf(service.start('bar', auth))).toBe('COUNT_ALREADY_OPEN');
  });
});
