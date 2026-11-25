import { Prisma } from '@prisma/client';
import { RealtimeEvent } from '../realtime/realtime.types';
import { StockLedgerRepository } from './stock-ledger.repository';
import { MovementContext, StockLedgerService } from './stock-ledger.service';

const D = (v: string | number) => new Prisma.Decimal(v);
const TX = {} as unknown as Prisma.TransactionClient;
const BASE_CTX: MovementContext = {
  tenantId: 't1',
  outletId: 'o1',
  userId: 'u1',
  now: new Date('2026-11-25T21:00:00+05:30'),
};

/**
 * In-memory stand-in for StockLedgerRepository. Method names and shapes mirror the repository, so
 * the service runs unchanged. Returned rows are copies, as they are from a database.
 */
class FakeRepo {
  items = new Map<string, { id: string; name: string; avgCost: Prisma.Decimal }>();
  locations = new Map<string, { id: string; outletId: string; name: string; isActive: boolean; stations: string[]; isDefaultSales: boolean }>();
  levels = new Map<string, { onHand: Prisma.Decimal; parLevel: Prisma.Decimal }>();
  movements: any[] = [];
  products = new Map<string, { id: string; name: string; is86: boolean; auto86: boolean; categoryId: string | null }>();
  categories = new Map<string, string>();
  recipes: { productId: string; variantId: string | null; lines: { stockItemId: string; qty: Prisma.Decimal; wastagePercent: Prisma.Decimal; sortOrder: number }[] }[] = [];
  options = new Map<string, { id: string; stockItemId: string | null; stockQty: Prisma.Decimal | null }>();
  notifications: any[] = [];
  wastage: any[] = [];

  private key(loc: string, item: string) {
    return `${loc}|${item}`;
  }

  async findItem(_tx: unknown, id: string) {
    const i = this.items.get(id);
    return i ? { ...i } : null;
  }
  async findLocation(_tx: unknown, id: string) {
    return this.locations.get(id) ?? null;
  }
  async activeLocations(_tx: unknown, outletId: string) {
    return [...this.locations.values()].filter((l) => l.outletId === outletId && l.isActive);
  }
  async findLevel(_tx: unknown, loc: string, item: string) {
    const l = this.levels.get(this.key(loc, item));
    return l ? { ...l } : null;
  }
  async addToLevel(_tx: unknown, loc: string, item: string, delta: Prisma.Decimal) {
    const k = this.key(loc, item);
    const cur = this.levels.get(k) ?? { onHand: D(0), parLevel: D(0) };
    const next = { onHand: cur.onHand.plus(delta), parLevel: cur.parLevel };
    this.levels.set(k, next);
    return { ...next };
  }
  async totalOnHand(_tx: unknown, _tenant: string, item: string) {
    let sum = D(0);
    for (const [k, v] of this.levels) if (k.endsWith(`|${item}`)) sum = sum.plus(v.onHand);
    return sum;
  }
  async setAvgCost(_tx: unknown, id: string, avgCost: Prisma.Decimal) {
    this.items.get(id)!.avgCost = avgCost;
  }
  async createMovement(_tx: unknown, data: any) {
    const m = { ...data, id: `m${this.movements.length + 1}`, refId: data.refId ?? null };
    this.movements.push(m);
    return m;
  }
  async outletTimezone() {
    return 'Asia/Kolkata';
  }
  async findProductsForEightySix(_tx: unknown, ids: string[]) {
    return ids
      .map((id) => this.products.get(id))
      .filter((p): p is NonNullable<typeof p> => !!p)
      .map((p) => ({ ...p }));
  }
  async categoryStation(_tx: unknown, categoryId: string | null) {
    return (categoryId && this.categories.get(categoryId)) || 'KITCHEN';
  }
  async findRecipe(_tx: unknown, productId: string, variantId: string | null) {
    return this.recipes.find((r) => r.productId === productId && r.variantId === variantId) ?? null;
  }
  async modifierOptionStock(_tx: unknown, ids: string[]) {
    return ids.map((id) => this.options.get(id)).filter((o): o is NonNullable<typeof o> => !!o);
  }
  async recipeStockItemIdsForProduct(_tx: unknown, productId: string) {
    const ids = this.recipes.filter((r) => r.productId === productId).flatMap((r) => r.lines.map((l) => l.stockItemId));
    return [...new Set(ids)];
  }
  async levelsAt(_tx: unknown, loc: string, ids: string[]) {
    return ids
      .filter((i) => this.levels.has(this.key(loc, i)))
      .map((i) => ({ stockItemId: i, onHand: this.levels.get(this.key(loc, i))!.onHand }));
  }
  async auto86ProductsUsing(_tx: unknown, ids: string[]) {
    const hits = this.recipes.filter((r) => {
      const p = this.products.get(r.productId)!;
      return p.is86 && p.auto86 && r.lines.some((l) => ids.includes(l.stockItemId));
    });
    return [...new Set(hits.map((r) => r.productId))];
  }
  async setEightySix(_tx: unknown, productId: string, is86: boolean, auto86: boolean) {
    const p = this.products.get(productId)!;
    p.is86 = is86;
    p.auto86 = auto86;
  }
  async createWastage(_tx: unknown, data: any) {
    this.wastage.push(data);
    return data;
  }
  async movementsByRef(_tx: unknown, refType: string, refIds: string[], types: string[]) {
    return this.movements.filter((m) => m.refType === refType && refIds.includes(m.refId) && types.includes(m.type));
  }
  async createNotification(_tx: unknown, data: any) {
    this.notifications.push(data);
    return data;
  }
}

function setup() {
  const repo = new FakeRepo();
  repo.locations.set('bar', { id: 'bar', outletId: 'o1', name: 'Bar', isActive: true, stations: ['BAR'], isDefaultSales: false });
  repo.locations.set('kit', {
    id: 'kit',
    outletId: 'o1',
    name: 'Kitchen',
    isActive: true,
    stations: ['KITCHEN', 'TANDOOR', 'GRILL'],
    isDefaultSales: true,
  });
  repo.items.set('whisky', { id: 'whisky', name: 'House Whisky 750 ml', avgCost: D('1.466667') });
  repo.items.set('soda', { id: 'soda', name: 'Soda 200 ml', avgCost: D('0.05') });
  repo.items.set('paneer', { id: 'paneer', name: 'Paneer', avgCost: D('0.4') });
  repo.levels.set('bar|whisky', { onHand: D(1000), parLevel: D(0) });
  repo.levels.set('bar|soda', { onHand: D(5000), parLevel: D(0) });
  repo.levels.set('kit|paneer', { onHand: D(500), parLevel: D(0) });
  repo.categories.set('cat-spirits', 'BAR');
  repo.categories.set('cat-bites', 'KITCHEN');
  repo.products.set('p-whisky', { id: 'p-whisky', name: 'House Whisky', is86: false, auto86: false, categoryId: 'cat-spirits' });
  repo.products.set('p-paneer', { id: 'p-paneer', name: 'Paneer Tikka', is86: false, auto86: false, categoryId: 'cat-bites' });
  // 60 ml variant recipe, product-level 30 ml recipe for every other variant
  repo.recipes.push({
    productId: 'p-whisky',
    variantId: 'v60',
    lines: [{ stockItemId: 'whisky', qty: D(60), wastagePercent: D(2), sortOrder: 0 }],
  });
  repo.recipes.push({
    productId: 'p-whisky',
    variantId: null,
    lines: [{ stockItemId: 'whisky', qty: D(30), wastagePercent: D(2), sortOrder: 0 }],
  });
  repo.recipes.push({
    productId: 'p-paneer',
    variantId: null,
    lines: [{ stockItemId: 'paneer', qty: D(250), wastagePercent: D(0), sortOrder: 0 }],
  });
  repo.options.set('opt-soda', { id: 'opt-soda', stockItemId: 'soda', stockQty: D(200) });
  const svc = new StockLedgerService(repo as unknown as StockLedgerRepository);
  const ctx = (): MovementContext & { events: RealtimeEvent[] } => ({ ...BASE_CTX, events: [] });
  return { repo, svc, ctx };
}

describe('StockLedgerService.deductForSentItems', () => {
  it('deducts the variant recipe, falls back to the product recipe, with wastage', async () => {
    const { repo, svc, ctx } = setup();
    await svc.deductForSentItems(TX, ctx(), [
      { orderItemId: 'oi1', productId: 'p-whisky', variantId: 'v60', quantity: 4, modifiers: [], station: 'BAR' },
      { orderItemId: 'oi2', productId: 'p-whisky', variantId: 'v30', quantity: 1, modifiers: [], station: 'BAR' },
    ]);
    const sales = repo.movements.filter((m) => m.type === 'SALE');
    expect(sales.map((m) => [m.refId, m.qty.toString(), m.locationId])).toEqual([
      ['oi1', '-244.8', 'bar'], // 60 × 1.02 × 4
      ['oi2', '-30.6', 'bar'], // 30 × 1.02 × 1
    ]);
    expect(sales[0].unitCost.toString()).toBe('1.466667');
    expect(repo.levels.get('bar|whisky')!.onHand.toString()).toBe('724.6');
  });

  it('deducts modifier stock per order quantity', async () => {
    const { repo, svc, ctx } = setup();
    await svc.deductForSentItems(TX, ctx(), [
      {
        orderItemId: 'oi3',
        productId: 'p-whisky',
        variantId: 'v60',
        quantity: 2,
        modifiers: [{ optionId: 'opt-soda' }],
        station: 'BAR',
      },
    ]);
    const soda = repo.movements.find((m) => m.stockItemId === 'soda');
    expect(soda.qty.toString()).toBe('-400');
    expect(soda.locationId).toBe('bar');
    expect(repo.levels.get('bar|soda')!.onHand.toString()).toBe('4600');
  });

  it('routes a station to the location that lists it, else the default sales location', async () => {
    const { repo, svc, ctx } = setup();
    await svc.deductForSentItems(TX, ctx(), [
      { orderItemId: 'oi4', productId: 'p-paneer', variantId: null, quantity: 1, modifiers: [], station: 'GRILL' },
      { orderItemId: 'oi5', productId: 'p-paneer', variantId: null, quantity: 1, modifiers: [], station: 'PASTRY' },
    ]);
    expect(repo.movements.filter((m) => m.type === 'SALE').map((m) => m.locationId)).toEqual(['kit', 'kit']);
  });

  it('skips the deduction when no location fits the station and there is no default', async () => {
    const { repo, svc, ctx } = setup();
    repo.locations.get('kit')!.isDefaultSales = false;
    await svc.deductForSentItems(TX, ctx(), [
      { orderItemId: 'oi6', productId: 'p-paneer', variantId: null, quantity: 1, modifiers: [], station: 'PASTRY' },
    ]);
    expect(repo.movements.filter((m) => m.type === 'SALE')).toHaveLength(0);
  });

  it('auto-86s the product when a recipe item reaches zero, and emits menu.item86', async () => {
    const { repo, svc, ctx } = setup();
    const c = ctx();
    const result = await svc.deductForSentItems(TX, c, [
      { orderItemId: 'oi7', productId: 'p-paneer', variantId: null, quantity: 2, modifiers: [], station: 'KITCHEN' },
    ]);
    expect(result.eightySixed).toEqual([{ productId: 'p-paneer', name: 'Paneer Tikka' }]);
    expect(repo.products.get('p-paneer')).toMatchObject({ is86: true, auto86: true });
    expect(c.events.filter((e) => e.event === 'menu.item86')).toEqual([
      { scope: 'outlet', outletId: 'o1', event: 'menu.item86', payload: { productId: 'p-paneer', name: 'Paneer Tikka', is86: true, auto: true } },
    ]);
  });

  it('does not change a manual 86', async () => {
    const { repo, svc, ctx } = setup();
    repo.products.set('p-paneer', { id: 'p-paneer', name: 'Paneer Tikka', is86: true, auto86: false, categoryId: 'cat-bites' });
    const result = await svc.deductForSentItems(TX, ctx(), [
      { orderItemId: 'oi8', productId: 'p-paneer', variantId: null, quantity: 2, modifiers: [], station: 'KITCHEN' },
    ]);
    expect(result.eightySixed).toEqual([]);
    expect(repo.products.get('p-paneer')).toMatchObject({ is86: true, auto86: false });
  });

  it('notifies low stock only when the level crosses below par', async () => {
    const { repo, svc, ctx } = setup();
    repo.levels.set('bar|whisky', { onHand: D(150), parLevel: D(100) });
    const c = ctx();
    await svc.deductForSentItems(TX, c, [
      { orderItemId: 'oi9', productId: 'p-whisky', variantId: 'v60', quantity: 1, modifiers: [], station: 'BAR' },
    ]);
    expect(repo.notifications).toHaveLength(1);
    expect(repo.notifications[0]).toMatchObject({
      tenantId: 't1',
      outletId: 'o1',
      permissionKey: 'stock.purchaseOrders',
      type: 'stock',
      title: 'House Whisky 750 ml is below par at Bar',
    });
    await svc.deductForSentItems(TX, c, [
      { orderItemId: 'oi10', productId: 'p-whisky', variantId: 'v60', quantity: 1, modifiers: [], station: 'BAR' },
    ]);
    expect(repo.notifications).toHaveLength(1);
    expect(c.events.filter((e) => e.event === 'stock.low')).toHaveLength(1);
  });
});

describe('StockLedgerService.post', () => {
  it('re-averages cost on a receipt and stores the receipt cost on the movement', async () => {
    const { repo, svc, ctx } = setup();
    repo.items.get('whisky')!.avgCost = D('4.16');
    await svc.post(TX, ctx(), [
      { locationId: 'bar', stockItemId: 'whisky', type: 'RECEIPT', qty: D(1000), unitCost: D(2) },
    ]);
    // H = 1000 on hand before the receipt: (1000 × 4.16 + 1000 × 2) / 2000
    expect(repo.items.get('whisky')!.avgCost.toString()).toBe('3.08');
    const receipt = repo.movements[0];
    expect(receipt.type).toBe('RECEIPT');
    expect(receipt.unitCost.toString()).toBe('2');
    expect(repo.levels.get('bar|whisky')!.onHand.toString()).toBe('2000');
  });

  it('refuses a receipt without a unit cost', async () => {
    const { svc, ctx } = setup();
    await expect(
      svc.post(TX, ctx(), [{ locationId: 'bar', stockItemId: 'whisky', type: 'RECEIPT', qty: D(10) }]),
    ).rejects.toMatchObject({ response: { code: 'UNIT_COST_REQUIRED' } });
  });

  it('clears auto-86 when a receipt brings every recipe item above zero', async () => {
    const { repo, svc, ctx } = setup();
    const c = ctx();
    await svc.deductForSentItems(TX, c, [
      { orderItemId: 'oi11', productId: 'p-paneer', variantId: null, quantity: 2, modifiers: [], station: 'KITCHEN' },
    ]);
    expect(repo.products.get('p-paneer')).toMatchObject({ is86: true, auto86: true });
    await svc.post(TX, c, [{ locationId: 'kit', stockItemId: 'paneer', type: 'RECEIPT', qty: D(2000), unitCost: D('0.4') }]);
    expect(repo.products.get('p-paneer')).toMatchObject({ is86: false, auto86: false });
    expect(c.events.filter((e) => e.event === 'menu.item86').map((e) => (e.payload as any).is86)).toEqual([true, false]);
  });

  it('keeps a manual 86 when stock comes back', async () => {
    const { repo, svc, ctx } = setup();
    repo.products.set('p-whisky', { id: 'p-whisky', name: 'House Whisky', is86: true, auto86: false, categoryId: 'cat-spirits' });
    await svc.post(TX, ctx(), [{ locationId: 'bar', stockItemId: 'whisky', type: 'RECEIPT', qty: D(100), unitCost: D(1) }]);
    expect(repo.products.get('p-whisky')).toMatchObject({ is86: true, auto86: false });
  });
});

describe('StockLedgerService.reverseSale', () => {
  it('writes a SALE_REVERSAL and a WASTAGE per sale, and one VOID wastage entry', async () => {
    const { repo, svc, ctx } = setup();
    await svc.deductForSentItems(TX, ctx(), [
      { orderItemId: 'oi12', productId: 'p-whisky', variantId: 'v60', quantity: 4, modifiers: [], station: 'BAR' },
    ]);
    expect(repo.levels.get('bar|whisky')!.onHand.toString()).toBe('755.2');

    await svc.reverseSale(TX, ctx(), ['oi12'], 'Wrong table');

    const after = repo.movements.filter((m) => m.refId === 'oi12').map((m) => [m.type, m.qty.toString()]);
    expect(after).toEqual([
      ['SALE', '-244.8'],
      ['SALE_REVERSAL', '244.8'],
      ['WASTAGE', '-244.8'],
    ]);
    // Net stock effect of a void of a sent line is the WASTAGE: the pour is written off
    expect(repo.levels.get('bar|whisky')!.onHand.toString()).toBe('755.2');
    expect(repo.wastage).toHaveLength(1);
    expect(repo.wastage[0]).toMatchObject({ reason: 'VOID', note: 'Wrong table', refId: 'oi12', refType: 'ORDER_ITEM' });
    expect(repo.wastage[0].qty.toString()).toBe('244.8');
    expect(repo.wastage[0].value.toString()).toBe('359.04');
  });

  it('does nothing for lines that were never sent', async () => {
    const { repo, svc, ctx } = setup();
    await svc.reverseSale(TX, ctx(), ['never-sent'], 'Void');
    expect(repo.movements).toHaveLength(0);
    expect(repo.wastage).toHaveLength(0);
  });
});
