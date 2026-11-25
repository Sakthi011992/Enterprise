import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { PermissionsService } from '../personas/permissions.service';
import { VarianceService } from './variance.service';

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

const viewer = {
  userId: 'u1', tenantId: 't1', outletId: 'o1', username: 'mgr',
  permissions: { 'stock.count': { level: 'VIEW', limit: null } },
} as unknown as AuthUser;

describe('VarianceService.variance (PLAN.md 1.3)', () => {
  it('computes expected, counted and variance from the movements and the opening', async () => {
    const malt = { id: 'malt', name: 'Single Malt 12Y 750 ml', baseUnit: 'ML', packSize: D(750), packName: 'btl', avgCost: D('4.16'), isLiquor: true, isActive: true };
    const day = new Date('2026-11-24T00:00:00Z');
    const movements = [
      { stockItemId: 'malt', type: 'RECEIPT', qty: D(9000), unitCost: D('4.16') },
      { stockItemId: 'malt', type: 'SALE', qty: D(-300), unitCost: D('4.16') },
      { stockItemId: 'malt', type: 'WASTAGE', qty: D(-60), unitCost: D('4.16') },
      { stockItemId: 'malt', type: 'COUNT_ADJUST', qty: D(-40), unitCost: D('4.16') },
    ].map((m) => ({ ...m, businessDate: day, locationId: 'bar' }));

    const repo = autoMock({
      outletTimezone: jest.fn(async () => 'Asia/Kolkata'),
      findItems: jest.fn(async () => [malt]),
      movementsWhere: jest.fn(async () => movements),
      openingSums: jest.fn(async () => [{ stockItemId: 'malt', _sum: { qty: D(3000) } }]),
      findLocation: jest.fn(async () => null),
    });
    const service = new VarianceService(repo, new PermissionsService({} as any));

    const report = await service.variance({ from: '2026-11-19', to: '2026-11-25' } as any, viewer);
    const row = report.rows[0] as any;

    expect(row.opening).toBe('3000.000');
    expect(row.received).toBe('9000.000');
    expect(row.sold).toBe('300.000');
    expect(row.wastage).toBe('60.000');
    expect(row.expected).toBe('11640.000');
    expect(row.counted).toBe('11600.000');
    expect(row.variance).toBe('-40.000');
    expect(row.varianceValue).toBe('-166.40');
    expect(report.totals.varianceValue).toBe('-166.40');
  });

  it('refuses a caller with neither stock.count VIEW nor reports.view LIMITED', async () => {
    const repo = autoMock({ outletTimezone: jest.fn(async () => 'Asia/Kolkata') });
    const service = new VarianceService(repo, new PermissionsService({} as any));
    const nobody = { ...viewer, permissions: {} } as unknown as AuthUser;
    await expect(service.variance({} as any, nobody)).rejects.toBeInstanceOf(HttpException);
  });
});
