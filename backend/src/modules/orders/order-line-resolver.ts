import { Injectable } from '@nestjs/common';
import { Order, Prisma, PriceRule } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { isWithinSchedule, PricingLineInput } from '../../common/pricing/pricing.engine';
import { TaxService } from '../tax/tax.service';
import {
  D,
  legacySnapshot,
  runPricing,
  snapshotFromClass,
  TaxSnapshot,
  toPricingTaxClass,
  ZERO,
} from './order-pricing';
import { ModifierSnapshot } from './order-view';
import { OrdersRepository } from './orders.repository';
import { AddItemDto } from './dto/order.dto';

export interface LineContext {
  timezone: string;
  now: Date;
  globalTax: Prisma.Decimal;
  rules: PriceRule[];
  /** Area markup for dine-in orders at a table in an area that charges one. Zero otherwise. */
  areaMarkupPercent: Prisma.Decimal;
}

export interface ResolvedLine {
  productId: string;
  productName: string;
  comboId: string | null;
  variantId: string | null;
  variantName: string | null;
  quantity: number;
  seat: number | null;
  note: string | null;
  modifiers: ModifierSnapshot[];
  happyHourPercent: Prisma.Decimal | null;
  taxClassId: string | null;
  snapshot: TaxSnapshot;
  /** Final unit price (markup and happy hour applied, modifiers included). Frozen on the line. */
  unitPrice: Prisma.Decimal;
}

/** Turns an AddItem into a priced line: catalogue lookups, availability, modifiers, tax snapshot and unit price. */
@Injectable()
export class OrderLineResolver {
  constructor(
    private repo: OrdersRepository,
    private tax: TaxService,
  ) {}

  async context(tx: Prisma.TransactionClient, order: Order, now: Date): Promise<LineContext> {
    const timezone = await this.repo.getOutletTimezone(order.outletId ?? '');
    const globalTax = (await this.tax.getGlobalTax()).percentage as Prisma.Decimal;
    const rules = order.outletId ? await this.repo.findActivePriceRules(tx, order.outletId) : [];

    let areaMarkupPercent = ZERO;
    if (order.type === 'DINE_IN' && order.tableId) {
      const table = await this.repo.findTableById(tx, order.tableId);
      const area = table ? await this.repo.findArea(tx, table.areaId) : null;
      if (area) areaMarkupPercent = D(area.priceMarkupPercent);
    }
    return { timezone, now, globalTax, rules, areaMarkupPercent };
  }

  async resolve(tx: Prisma.TransactionClient, dto: AddItemDto, ctx: LineContext): Promise<ResolvedLine> {
    if (Boolean(dto.productId) === Boolean(dto.comboId)) {
      throw apiError(400, 'ITEM_REQUIRED', 'Each item needs exactly one of productId or comboId');
    }
    const base = dto.productId
      ? await this.resolveProduct(tx, dto, ctx)
      : await this.resolveCombo(tx, dto, ctx);
    return {
      ...base,
      quantity: dto.quantity,
      seat: dto.seat ?? null,
      note: dto.note ?? null,
      unitPrice: this.unitPrice(base, ctx),
    };
  }

  private async resolveProduct(tx: Prisma.TransactionClient, dto: AddItemDto, ctx: LineContext) {
    const product = await this.repo.findProduct(tx, dto.productId!);
    if (!product) throw apiError(400, 'ITEM_UNAVAILABLE', 'This item is not available', { productId: dto.productId });
    if (product.is86) throw apiError(400, 'ITEM_86', 'This item is out of stock', { productId: product.id });

    let price = D(product.price);
    let variantName: string | null = null;
    if (dto.variantId) {
      const variant = await this.repo.findVariant(tx, dto.variantId, product.id);
      if (!variant) throw apiError(400, 'VARIANT_UNAVAILABLE', 'This size is not available', { variantId: dto.variantId });
      price = D(variant.price);
      variantName = variant.name;
    }

    const category = product.categoryId ? await this.repo.findCategory(tx, product.categoryId) : null;
    const taxClassId = product.taxClassId ?? category?.taxClassId ?? null;
    const taxClass = taxClassId ? await this.repo.findTaxClass(tx, taxClassId) : null;
    const snapshot = taxClass
      ? snapshotFromClass(taxClass)
      : legacySnapshot(this.tax.resolveRate(product.taxPercentage, ctx.globalTax));

    const mods = await this.resolveModifiers(tx, product.id, dto.modifierOptionIds ?? []);
    return {
      productId: product.id,
      productName: product.name,
      comboId: null,
      variantId: dto.variantId ?? null,
      variantName,
      modifiers: mods.picked,
      happyHourPercent: this.happyHourFor(ctx, product.categoryId, product.id),
      taxClassId: taxClass?.id ?? null,
      snapshot,
      basePrice: price,
      modifiersDelta: mods.delta,
    };
  }

  private async resolveCombo(tx: Prisma.TransactionClient, dto: AddItemDto, ctx: LineContext) {
    const combo = await this.repo.findCombo(tx, dto.comboId!);
    if (!combo || combo.items.length === 0) throw apiError(400, 'COMBO_UNAVAILABLE', 'This combo is not available');
    if (!isWithinSchedule(ctx.now, ctx.timezone, combo.days, combo.startTime, combo.endTime)) {
      throw apiError(400, 'COMBO_UNAVAILABLE', 'This combo is not available right now');
    }
    const parts = await this.repo.findProductsFull(tx, combo.items.map((i) => i.productId));
    const unavailable = combo.items.some((ci) => {
      const p = parts.find((x) => x.id === ci.productId);
      return !p || !p.isActive || p.deletedAt !== null || p.is86;
    });
    if (unavailable) throw apiError(400, 'COMBO_UNAVAILABLE', 'A part of this combo is out of stock');

    const first = parts.find((x) => x.id === combo.items[0].productId)!;
    const taxClass = combo.taxClassId ? await this.repo.findTaxClass(tx, combo.taxClassId) : null;
    const snapshot = taxClass ? snapshotFromClass(taxClass) : legacySnapshot(ctx.globalTax);
    return {
      productId: first.id,
      productName: combo.name,
      comboId: combo.id,
      variantId: null,
      variantName: null,
      modifiers: [] as ModifierSnapshot[],
      happyHourPercent: null,
      taxClassId: taxClass?.id ?? null,
      snapshot,
      basePrice: D(combo.price),
      modifiersDelta: ZERO,
    };
  }

  /** Options must belong to a group linked to the product, and each group's min/max must hold. */
  private async resolveModifiers(tx: Prisma.TransactionClient, productId: string, optionIds: string[]) {
    const groupIds = await this.repo.productModifierGroupIds(tx, productId);
    const groups = groupIds.length ? await this.repo.modifierGroupsWithOptions(tx, groupIds) : [];

    const options = new Map<string, { groupId: string; name: string; priceDelta: Prisma.Decimal }>();
    for (const g of groups) {
      for (const o of g.options) options.set(o.id, { groupId: g.id, name: o.name, priceDelta: D(o.priceDelta) });
    }

    const picked: ModifierSnapshot[] = [];
    let delta = ZERO;
    for (const id of [...new Set(optionIds)]) {
      const hit = options.get(id);
      if (!hit) throw apiError(400, 'MODIFIER_RULES', 'This option is not available for this item', { optionId: id });
      picked.push({ groupId: hit.groupId, optionId: id, name: hit.name, priceDelta: hit.priceDelta.toFixed(2) });
      delta = delta.add(hit.priceDelta);
    }

    for (const g of groups) {
      const count = picked.filter((p) => p.groupId === g.id).length;
      if (count < g.minSelect || count > g.maxSelect) {
        throw apiError(400, 'MODIFIER_RULES', `${g.name}: choose ${g.minSelect} to ${g.maxSelect}`, {
          groupId: g.id,
          minSelect: g.minSelect,
          maxSelect: g.maxSelect,
          selected: count,
        });
      }
    }
    return { picked, delta };
  }

  /** The best active happy-hour percent for this product right now, or null. */
  private happyHourFor(ctx: LineContext, categoryId: string | null, productId: string): Prisma.Decimal | null {
    let best: Prisma.Decimal | null = null;
    for (const rule of ctx.rules) {
      const applies = (categoryId !== null && rule.categoryIds.includes(categoryId)) || rule.productIds.includes(productId);
      if (!applies) continue;
      if (!isWithinSchedule(ctx.now, ctx.timezone, rule.days, rule.startTime, rule.endTime)) continue;
      if (best === null || D(rule.percentOff).greaterThan(best)) best = D(rule.percentOff);
    }
    return best;
  }

  /** Unit price per PLAN.md 1.3 step 1: (base + modifiers) x area markup x (1 - happy hour). */
  private unitPrice(
    base: { basePrice: Prisma.Decimal; modifiersDelta: Prisma.Decimal; snapshot: TaxSnapshot; happyHourPercent: Prisma.Decimal | null },
    ctx: LineContext,
  ): Prisma.Decimal {
    const line: PricingLineInput = {
      id: 'unit',
      baseUnitPrice: base.basePrice,
      modifiersDelta: base.modifiersDelta,
      quantity: 1,
      taxClass: toPricingTaxClass(base.snapshot),
      areaMarkupPercent: ctx.areaMarkupPercent,
      happyHourPercent: base.happyHourPercent,
      voided: false,
    };
    const r = runPricing({
      lines: [line],
      discounts: [],
      serviceChargePercent: ZERO,
      roundingMode: 'NONE',
    });
    return r.lines[0].unitPrice;
  }
}
