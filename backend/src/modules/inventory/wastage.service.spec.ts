import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { WastageService } from './wastage.service';

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

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', username: 'bartender', permissions: {} } as unknown as AuthUser;

async function errorOf(p: Promise<unknown>): Promise<{ code: string; details?: any }> {
  try {
    await p;
  } catch (e) {
    return (e as HttpException).getResponse() as { code: string; details?: any };
  }
  throw new Error('expected an error');
}

/** Single Malt at ₹4.16 per ml, so ₹3,120 per bottle. */
function setup(onHand = D(5000)) {
  const repo = autoMock({
    transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn({})),
    findLocation: jest.fn(async () => ({ id: 'bar', name: 'Bar' })),
    findItem: jest.fn(async () => ({ id: 'malt', name: 'Single Malt 12Y 750 ml', baseUnit: 'ML', packSize: D(750), packName: 'btl', avgCost: D('4.16') })),
    outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
    createWastage: jest.fn(async (_tx: unknown, data: any) => ({ id: 'w1', createdAt: new Date(), ...data })),
    createNotification: jest.fn(async () => undefined),
    findLocationsByIds: jest.fn(async () => [{ id: 'bar', name: 'Bar' }]),
    findItemsByIds: jest.fn(async () => [{ id: 'malt', name: 'Single Malt 12Y 750 ml', baseUnit: 'ML', packSize: D(750), packName: 'btl', avgCost: D('4.16') }]),
    findUsers: jest.fn(async () => []),
  });
  const ledger = autoMock({
    onHand: jest.fn(async () => onHand),
    post: jest.fn(async (_tx: unknown, _ctx: unknown, inputs: unknown[]) => inputs),
  });
  const realtime = autoMock({ publish: jest.fn() });
  return { service: new WastageService(repo, ledger, realtime), repo, ledger };
}

describe('WastageService.create', () => {
  it('refuses the system-only reasons', async () => {
    const { service } = setup();
    const err = await errorOf(service.create({ locationId: 'bar', stockItemId: 'malt', qty: 60, reason: 'VOID' } as any, auth));
    expect(err.code).toBe('INVALID_REASON');
  });

  it('needs a photo above ₹2,000', async () => {
    const { service } = setup();
    // 1000 ml × ₹4.16 = ₹4,160
    const err = await errorOf(service.create({ locationId: 'bar', stockItemId: 'malt', qty: 1000, reason: 'SPILLED' } as any, auth));
    expect(err.code).toBe('PHOTO_REQUIRED');
  });

  it('refuses more than is on hand, with the on-hand quantity in display form', async () => {
    const { service } = setup(D(750));
    // 800 ml × ₹4.16 = ₹3,328, so a photo is required first
    const err = await errorOf(
      service.create({ locationId: 'bar', stockItemId: 'malt', qty: 800, reason: 'SPILLED', photoUrl: 'https://x/p.jpg' } as any, auth),
    );
    expect(err.code).toBe('INSUFFICIENT_STOCK');
    expect(err.details).toEqual({ onHand: '750.000', onHandDisplay: '1 btl' });
  });

  it('posts a WASTAGE movement of minus the quantity against the new entry', async () => {
    const { service, ledger, repo } = setup();
    await service.create({ locationId: 'bar', stockItemId: 'malt', qty: 60, reason: 'BROKEN' } as any, auth);
    const inputs = ledger.post.mock.calls[0][2] as any[];
    expect(inputs[0]).toMatchObject({ type: 'WASTAGE', refType: 'WASTAGE', refId: 'w1', stockItemId: 'malt' });
    expect(inputs[0].qty.toFixed(3)).toBe('-60.000');
    expect(repo.createWastage.mock.calls[0][1].value.toFixed(2)).toBe('249.60');
    expect(repo.createNotification).not.toHaveBeenCalled();
  });

  it('notifies the purchase approvers when the value is above ₹2,000 and a photo was attached', async () => {
    const { service, repo } = setup();
    await service.create({ locationId: 'bar', stockItemId: 'malt', qty: 750, reason: 'DROPPED', photoUrl: 'https://x/p.jpg' } as any, auth);
    // 750 ml × ₹4.16 = ₹3,120
    expect(repo.createNotification).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ permissionKey: 'stock.purchaseOrders', type: 'stock' }),
    );
  });
});
