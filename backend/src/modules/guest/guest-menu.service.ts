import { Injectable } from '@nestjs/common';
import { Order, Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { PricingLineInput } from '../../common/pricing/pricing.engine';
import { MenuService } from '../menu/menu.service';
import { OrderLineResolver } from '../orders/order-line-resolver';
import { D, legacySnapshot, money, runPricing, toPricingTaxClass, ZERO } from '../orders/order-pricing';
import { OrdersRepository } from '../orders/orders.repository';
import { GuestRepository } from './guest.repository';

export interface GuestMenuOption {
  id: string;
  name: string;
  priceDelta: string;
}
export interface GuestMenuGroup {
  id: string;
  name: string;
  minSelect: number;
  maxSelect: number;
  options: GuestMenuOption[];
}
export interface GuestMenuVariant {
  id: string;
  name: string;
  price: string;
  basePrice: string;
  isDefault: boolean;
  /** Catalogue price before markup and happy hour. */
  listPrice: string;
}
export interface GuestMenuProduct {
  id: string;
  name: string;
  description: string | null;
  categoryId: string;
  price: string;
  basePrice: string;
  available: boolean;
  isAlcohol: boolean;
  featured: boolean;
  imageUrl: string | null;
  listPrice: string;
  happyHour: { label: string; percent: string; until: string | null } | null;
  variants: GuestMenuVariant[];
  modifierGroups: GuestMenuGroup[];
}
export interface GuestMenu {
  categories: { id: string; name: string; color: string | null; sortOrder: number; products: GuestMenuProduct[] }[];
  happyHour: { label: string; until: string | null } | null;
  /** Area markup of the table, percent. */
  markupPercent: string;
}

/** Price context for the table: area markup and the active happy-hour rules. */
interface PriceCtx {
  markup: Prisma.Decimal;
  rules: { name: string; percentOff: Prisma.Decimal; categoryIds: string[]; productIds: string[]; endsAt: string | null }[];
}

/**
 * QR channel projection of the POS menu (GET /menu/pos): only modifier groups shown on QR, current prices for
 * the table's area with happy hour applied (same pricing engine as order lines), availability, alcohol flag.
 */
@Injectable()
export class GuestMenuService {
  constructor(
    private menu: MenuService,
    private lines: OrderLineResolver,
    private orders: OrdersRepository,
    private repo: GuestRepository,
  ) {}

  async build(scope: { tenantId: string; outletId: string; tableId: string }, now = new Date()): Promise<GuestMenu> {
    const auth = { tenantId: scope.tenantId, outletId: scope.outletId } as AuthUser;
    const [pos, catTax, channels, featured, markup] = await Promise.all([
      this.menu.pos(auth, now),
      this.repo.categoryTaxClasses(),
      this.repo.modifierChannels(),
      this.repo.featuredProductIds(now),
      this.areaMarkup(scope, now),
    ]);
    const qrGroups = new Set(channels.filter((g) => g.showOn.includes('QR')).map((g) => g.id));
    const liquorClass = new Set(pos.taxClasses.filter((t) => t.isLiquor).map((t) => t.id));
    const catClass = new Map(catTax.map((c) => [c.id, c.taxClassId]));
    const groups = new Map(pos.modifierGroups.map((g) => [g.id, g]));
    const ctx: PriceCtx = {
      markup,
      rules: pos.priceRules
        .filter((r) => r.activeNow)
        .map((r) => ({ name: r.name, percentOff: D(r.percentOff), categoryIds: r.categoryIds, productIds: r.productIds, endsAt: r.endsAt })),
    };

    const byCat = new Map<string, GuestMenuProduct[]>();
    for (const p of pos.products) {
      if (!p.categoryId) continue;
      const rule = this.bestRule(ctx, p.categoryId, p.id);
      const hh = rule ? rule.percentOff : null;
      const taxClassId = p.taxClassId ?? catClass.get(p.categoryId) ?? null;
      const product: GuestMenuProduct = {
        id: p.id,
        name: p.name,
        description: (p as { description?: string | null }).description ?? null,
        categoryId: p.categoryId,
        price: money(unitPrice(D(p.price), ZERO, markup, hh)),
        basePrice: money(unitPrice(D(p.price), ZERO, markup, null)),
        listPrice: money(p.price),
        available: !p.is86,
        isAlcohol: taxClassId ? liquorClass.has(taxClassId) : false,
        featured: featured.has(p.id),
        imageUrl: p.imageUrl,
        happyHour: rule ? { label: rule.name, percent: money(rule.percentOff), until: rule.endsAt } : null,
        variants: p.variants.map((v) => ({
          id: v.id,
          name: v.name,
          isDefault: v.isDefault,
          listPrice: money(v.price),
          price: money(unitPrice(D(v.price), ZERO, markup, hh)),
          basePrice: money(unitPrice(D(v.price), ZERO, markup, null)),
        })),
        modifierGroups: p.modifierGroupIds
          .filter((id) => qrGroups.has(id))
          .map((id) => groups.get(id)!)
          .filter(Boolean)
          .map((g) => ({
            id: g.id,
            name: g.name,
            minSelect: g.minSelect,
            maxSelect: g.maxSelect,
            options: g.options.map((o) => ({ id: o.id, name: o.name, priceDelta: money(o.priceDelta) })),
          })),
      };
      const list = byCat.get(p.categoryId) ?? [];
      list.push(product);
      byCat.set(p.categoryId, list);
    }

    const active = ctx.rules[0];
    return {
      categories: pos.categories
        .filter((c) => byCat.has(c.id))
        .map((c) => ({ id: c.id, name: c.name, color: c.color, sortOrder: c.sortOrder, products: byCat.get(c.id)! })),
      happyHour: active ? { label: active.name, until: active.endsAt } : null,
      markupPercent: money(markup),
    };
  }

  /** Product index for validating rounds. */
  index(menu: GuestMenu): Map<string, GuestMenuProduct> {
    const m = new Map<string, GuestMenuProduct>();
    for (const c of menu.categories) for (const p of c.products) m.set(p.id, p);
    return m;
  }

  /** Unit price of a menu product with the chosen variant and option deltas: (list + options) x markup x (1 - happy hour). */
  priceOf(menu: GuestMenu, p: GuestMenuProduct, variantId: string | null | undefined, optionDelta: Prisma.Decimal): Prisma.Decimal {
    const v = variantId ? p.variants.find((x) => x.id === variantId) : null;
    const list = D(v ? v.listPrice : p.listPrice);
    return unitPrice(list, optionDelta, D(menu.markupPercent), p.happyHour ? D(p.happyHour.percent) : null);
  }

  private async areaMarkup(scope: { outletId: string; tableId: string }, now: Date): Promise<Prisma.Decimal> {
    const fake = { id: '', outletId: scope.outletId, type: 'DINE_IN', tableId: scope.tableId } as unknown as Order;
    const ctx = await this.orders.transaction((tx) => this.lines.context(tx, fake, now));
    return D(ctx.areaMarkupPercent);
  }

  private bestRule(ctx: PriceCtx, categoryId: string, productId: string) {
    let best: PriceCtx['rules'][number] | null = null;
    for (const r of ctx.rules) {
      if (!r.categoryIds.includes(categoryId) && !r.productIds.includes(productId)) continue;
      if (!best || r.percentOff.greaterThan(best.percentOff)) best = r;
    }
    return best;
  }
}

/** The pricing engine's unit price (PLAN 1.3 step 1). Tax does not change the unit price. */
export function unitPrice(base: Prisma.Decimal, delta: Prisma.Decimal, markup: Prisma.Decimal, hh: Prisma.Decimal | null) {
  const line: PricingLineInput = {
    id: 'unit',
    baseUnitPrice: base,
    modifiersDelta: delta,
    quantity: 1,
    taxClass: toPricingTaxClass(legacySnapshot(ZERO)),
    areaMarkupPercent: markup,
    happyHourPercent: hh,
    voided: false,
  };
  return runPricing({ lines: [line], discounts: [], serviceChargePercent: ZERO, roundingMode: 'NONE' }).lines[0].unitPrice;
}
