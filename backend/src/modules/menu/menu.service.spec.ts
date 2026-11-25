import { AuthUser } from '../../common/decorators/current-user.decorator';
import { MenuService } from './menu.service';
import { nextClockTime } from './menu-time';

const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', permissions: {} } as unknown as AuthUser;
const NOW = new Date('2026-11-25T12:30:00Z'); // 18:00 in Asia/Kolkata

const ALL_DAYS = [0, 1, 2, 3, 4, 5, 6];

function product(overrides: Record<string, unknown> = {}) {
  return {
    id: 'p1',
    name: 'Classic Mojito',
    categoryId: 'c-cocktails',
    price: '350.00',
    is86: false,
    imageUrl: null,
    taxClassId: 'tc-gst5',
    isActive: true,
    deletedAt: null,
    variants: [{ id: 'v1', name: 'Glass', price: '350.00', isDefault: true, isActive: true }],
    modifierGroups: [{ groupId: 'g-live' }, { groupId: 'g-gone' }],
    ...overrides,
  };
}

function setup(overrides: Partial<Record<string, unknown>> = {}) {
  const repo = {
    findOutlet: jest.fn(async () => ({ timezone: 'Asia/Kolkata' })),
    categories: jest.fn(async () => [
      { id: 'c-cocktails', name: 'Cocktails', color: '#E0A526', sortOrder: 2, isActive: true },
      { id: 'c-old', name: 'Retired', color: null, sortOrder: 9, isActive: false },
    ]),
    products: jest.fn(async () => [
      product(),
      product({ id: 'p-86', name: 'Chicken Wings', is86: true, categoryId: 'c-bites' }),
      product({ id: 'p-off', name: 'Old item', isActive: false }),
    ]),
    modifierGroups: jest.fn(async () => [
      {
        id: 'g-live',
        name: 'How to serve',
        minSelect: 1,
        maxSelect: 1,
        isActive: true,
        options: [
          { id: 'o1', name: 'Neat', priceDelta: '0', isActive: true },
          { id: 'o2', name: 'Retired option', priceDelta: '0', isActive: false },
        ],
      },
    ]),
    combos: jest.fn(async () => [
      { id: 'cb1', name: 'Beer bucket', price: '1200', isActive: true, days: ALL_DAYS, startTime: '19:00', endTime: '23:59', items: [] },
    ]),
    priceRules: jest.fn(async () => [
      { id: 'hh', name: 'Happy hour', percentOff: '30', categoryIds: ['c-cocktails'], productIds: [], days: ALL_DAYS, startTime: '17:00', endTime: '20:00', isActive: true },
    ]),
    taxClasses: jest.fn(async () => [{ id: 'tc-gst5', code: 'GST5', name: 'GST 5%', rate: '5.00', isLiquor: false, inclusive: false, isActive: true }]),
    outletSettings: jest.fn(async () => null),
    ...overrides,
  };
  return { service: new MenuService(repo as any), repo };
}

describe('GET /menu/pos (MenuService.pos)', () => {
  it('leaves out inactive categories, products and options, and keeps 86 products with the flag set', async () => {
    const { service } = setup();
    const menu = await service.pos(auth, NOW);
    expect(menu.categories.map((c) => c.id)).toEqual(['c-cocktails']);
    expect(menu.products.map((p) => p.id)).toEqual(['p1', 'p-86']);
    expect(menu.products.find((p) => p.id === 'p-86')?.is86).toBe(true);
    expect(menu.modifierGroups[0].options.map((o) => o.name)).toEqual(['Neat']);
  });

  it('drops modifier groups that are no longer active from a product', async () => {
    const { service } = setup();
    const menu = await service.pos(auth, NOW);
    expect(menu.products[0].modifierGroupIds).toEqual(['g-live']);
  });

  it('reports the happy hour as active with the time it ends in outlet time', async () => {
    const { service } = setup();
    const menu = await service.pos(auth, NOW);
    expect(menu.priceRules[0].activeNow).toBe(true);
    // 20:00 IST is 14:30 UTC on the same day.
    expect(menu.priceRules[0].endsAt).toBe('2026-11-25T14:30:00.000Z');
  });

  it('reports a combo outside its window as not available now', async () => {
    const { service } = setup();
    const menu = await service.pos(auth, NOW);
    expect(menu.combos[0].availableNow).toBe(false);
  });

  it('uses default settings when the outlet has no settings row', async () => {
    const { service } = setup();
    const menu = await service.pos(auth, NOW);
    expect(menu.settings).toEqual({ serviceChargePercent: 0, serviceChargeTypes: ['DINE_IN'], roundingMode: 'NEAREST_1' });
  });
});

describe('nextClockTime', () => {
  it('returns today at the given outlet time when it is still ahead', () => {
    expect(nextClockTime(NOW, 'Asia/Kolkata', '20:00').toISOString()).toBe('2026-11-25T14:30:00.000Z');
  });

  it('returns tomorrow when the time has already passed today', () => {
    const late = new Date('2026-11-25T15:00:00Z'); // 20:30 IST
    expect(nextClockTime(late, 'Asia/Kolkata', '20:00').toISOString()).toBe('2026-11-26T14:30:00.000Z');
  });
});
