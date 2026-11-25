import { Injectable, Logger } from '@nestjs/common';
import { Prisma, StockMovement, StockMovementType } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { RealtimeEvent } from '../realtime/realtime.types';
import { movementValue, recipeQty, weightedAverage } from './stock-math';
import { LedgerLocation, LedgerProduct, StockLedgerRepository } from './stock-ledger.repository';

export interface MovementInput {
  locationId: string;
  stockItemId: string;
  type: StockMovementType;
  qty: Prisma.Decimal; // signed, base units
  unitCost?: Prisma.Decimal; // receipts only; others use avgCost
  refType?: string;
  refId?: string;
  note?: string;
}

export interface MovementContext {
  tenantId: string;
  outletId: string;
  userId: string | null;
  now: Date;
  /** Realtime events are queued here and emitted by the caller after the transaction commits. */
  events?: RealtimeEvent[];
}

export interface SentItemForDeduction {
  orderItemId: string;
  productId: string | null;
  variantId: string | null;
  quantity: number;
  modifiers: { optionId?: string }[];
  station: string;
}

const RESTOCK_TYPES: StockMovementType[] = ['RECEIPT', 'TRANSFER_IN', 'COUNT_ADJUST'];

/** Stock core: every change to stock goes through here (PLAN.md 1.3, 1.4). */
@Injectable()
export class StockLedgerService {
  private readonly logger = new Logger(StockLedgerService.name);

  constructor(private readonly repo: StockLedgerRepository) {}

  /**
   * Writes the movements, updates the levels and the weighted average (receipts), and runs the
   * low-stock check and the auto un-86 check. Must run inside the caller's transaction.
   */
  async post(tx: Prisma.TransactionClient, ctx: MovementContext, inputs: MovementInput[]): Promise<StockMovement[]> {
    const out: StockMovement[] = [];
    if (inputs.length === 0) return out;

    const businessDate = await this.businessDateOf(tx, ctx);
    const restocked: string[] = [];

    for (const input of inputs) {
      const item = await this.repo.findItem(tx, input.stockItemId);
      if (!item) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');
      const location = await this.repo.findLocation(tx, input.locationId);
      if (!location || location.outletId !== ctx.outletId) {
        throw apiError(404, 'LOCATION_NOT_FOUND', 'Stock location not found');
      }

      let unitCost: Prisma.Decimal;
      if (input.type === 'RECEIPT') {
        if (!input.unitCost) throw apiError(400, 'UNIT_COST_REQUIRED', 'A receipt needs a unit cost');
        unitCost = input.unitCost;
        const onHandAll = await this.repo.totalOnHand(tx, ctx.tenantId, item.id);
        const avgCost = weightedAverage(onHandAll, item.avgCost, input.qty, unitCost);
        await this.repo.setAvgCost(tx, item.id, avgCost);
        item.avgCost = avgCost;
      } else {
        unitCost = item.avgCost;
      }

      const level = await this.repo.addToLevel(tx, location.id, item.id, input.qty);
      const onHandAfter = level.onHand;
      const onHandBefore = onHandAfter.minus(input.qty);
      const par = level.parLevel;

      const movement = await this.repo.createMovement(tx, {
        tenantId: ctx.tenantId,
        outletId: ctx.outletId,
        locationId: location.id,
        stockItemId: item.id,
        type: input.type,
        qty: input.qty,
        unitCost,
        refType: input.refType ?? null,
        refId: input.refId ?? null,
        businessDate,
        note: input.note ?? null,
        createdById: ctx.userId,
      });
      out.push(movement);

      if (input.qty.gt(0) && RESTOCK_TYPES.includes(input.type)) restocked.push(item.id);

      // Low stock: only when the level crosses below par (was at or above it, now below). Items
      // without a par level are not tracked.
      if (par.gt(0) && onHandBefore.gte(par) && onHandAfter.lt(par)) {
        await this.repo.createNotification(tx, {
          tenantId: ctx.tenantId,
          outletId: ctx.outletId,
          permissionKey: 'stock.purchaseOrders',
          type: 'stock',
          title: `${item.name} is below par at ${location.name}`,
          data: { stockItemId: item.id, locationId: location.id },
        });
        this.emit(ctx, {
          scope: 'outlet',
          outletId: ctx.outletId,
          event: 'stock.low',
          payload: {
            stockItemId: item.id,
            name: item.name,
            locationId: location.id,
            locationName: location.name,
            onHand: onHandAfter.toFixed(3),
            parLevel: par.toFixed(3),
          },
        });
      }
    }

    await this.autoUnEightySix(tx, ctx, [...new Set(restocked)]);
    return out;
  }

  /**
   * Recipe deduction when lines go from NEW to SENT (PLAN.md 1.4 steps 1 to 6). Recipe lookup:
   * variant recipe, then the product recipe. Modifiers with a stock item add their own quantity.
   */
  async deductForSentItems(
    tx: Prisma.TransactionClient,
    ctx: MovementContext,
    items: SentItemForDeduction[],
  ): Promise<{ eightySixed: { productId: string; name: string }[] }> {
    const inputs: MovementInput[] = [];
    const candidates = new Set<string>();

    for (const item of items) {
      if (!item.productId) continue;
      candidates.add(item.productId);

      const recipe =
        (item.variantId ? await this.repo.findRecipe(tx, item.productId, item.variantId) : null) ??
        (await this.repo.findRecipe(tx, item.productId, null));

      const locationId = await this.salesLocationFor(tx, ctx.outletId, item.station);
      if (!locationId) {
        this.logger.warn(`No sales location for station ${item.station}; order item ${item.orderItemId} not deducted`);
        continue;
      }

      if (recipe) {
        for (const line of recipe.lines) {
          inputs.push({
            locationId,
            stockItemId: line.stockItemId,
            type: 'SALE',
            qty: recipeQty(line.qty, line.wastagePercent, item.quantity).neg(),
            refType: 'ORDER_ITEM',
            refId: item.orderItemId,
          });
        }
      }

      const optionIds = item.modifiers.map((m) => m.optionId).filter((x): x is string => !!x);
      if (optionIds.length > 0) {
        const options = await this.repo.modifierOptionStock(tx, optionIds);
        for (const opt of options) {
          if (!opt.stockItemId || !opt.stockQty) continue;
          inputs.push({
            locationId,
            stockItemId: opt.stockItemId,
            type: 'SALE',
            qty: new Prisma.Decimal(opt.stockQty).mul(item.quantity).toDecimalPlaces(3).neg(),
            refType: 'ORDER_ITEM',
            refId: item.orderItemId,
          });
        }
      }
    }

    await this.post(tx, ctx, inputs);

    // Auto-86 after every deduction of the send (PLAN.md 1.4 step 6).
    const eightySixed: { productId: string; name: string }[] = [];
    for (const productId of candidates) {
      const { product, outOfStock } = await this.recipeAvailability(tx, ctx.outletId, productId);
      if (!product || !outOfStock || product.is86) continue;
      await this.repo.setEightySix(tx, productId, true, true);
      eightySixed.push({ productId, name: product.name });
      this.emit(ctx, {
        scope: 'outlet',
        outletId: ctx.outletId,
        event: 'menu.item86',
        payload: { productId, name: product.name, is86: true, auto: true },
      });
    }
    return { eightySixed };
  }

  /**
   * Void of SENT lines: SALE_REVERSAL (+qty) and WASTAGE (−qty) per sale movement, plus one
   * WastageEntry (reason VOID) per wastage movement, valued at the movement's unit cost.
   */
  async reverseSale(
    tx: Prisma.TransactionClient,
    ctx: MovementContext,
    orderItemIds: string[],
    reason: string,
  ): Promise<void> {
    if (orderItemIds.length === 0) return;
    const sales = await this.repo.movementsByRef(tx, 'ORDER_ITEM', orderItemIds, ['SALE']);
    if (sales.length === 0) return;
    if (!ctx.userId) throw apiError(400, 'USER_REQUIRED', 'Voiding a sent item needs a signed-in user');

    const inputs: MovementInput[] = [];
    for (const sale of sales) {
      const qty = sale.qty.neg();
      inputs.push({
        locationId: sale.locationId,
        stockItemId: sale.stockItemId,
        type: 'SALE_REVERSAL',
        qty,
        refType: 'ORDER_ITEM',
        refId: sale.refId ?? undefined,
        note: reason,
      });
      inputs.push({
        locationId: sale.locationId,
        stockItemId: sale.stockItemId,
        type: 'WASTAGE',
        qty: qty.neg(),
        refType: 'ORDER_ITEM',
        refId: sale.refId ?? undefined,
        note: reason,
      });
    }

    const posted = await this.post(tx, ctx, inputs);
    for (const m of posted) {
      if (m.type !== 'WASTAGE') continue;
      await this.repo.createWastage(tx, {
        tenantId: ctx.tenantId,
        outletId: ctx.outletId,
        locationId: m.locationId,
        stockItemId: m.stockItemId,
        qty: m.qty.neg(),
        value: movementValue(m.qty.neg(), m.unitCost),
        reason: 'VOID',
        note: reason,
        refType: 'ORDER_ITEM',
        refId: m.refId,
        businessDate: m.businessDate,
        createdById: ctx.userId,
      });
    }
  }

  /** Sales location for a station: the location listing it, else the default sales location, else null. */
  async salesLocationFor(tx: Prisma.TransactionClient, outletId: string, station: string): Promise<string | null> {
    const locations: LedgerLocation[] = await this.repo.activeLocations(tx, outletId);
    const listing = locations.find((l) => l.stations.includes(station));
    if (listing) return listing.id;
    return locations.find((l) => l.isDefaultSales)?.id ?? null;
  }

  /** On hand at one location, 0 when there is no level row. */
  async onHand(tx: Prisma.TransactionClient, locationId: string, stockItemId: string): Promise<Prisma.Decimal> {
    const level = await this.repo.findLevel(tx, locationId, stockItemId);
    return level?.onHand ?? new Prisma.Decimal(0);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /** True when some recipe item of the product is at or below zero at the product's sales location. */
  private async recipeAvailability(
    tx: Prisma.TransactionClient,
    outletId: string,
    productId: string,
  ): Promise<{ product: LedgerProduct | null; outOfStock: boolean }> {
    const [product] = await this.repo.findProductsForEightySix(tx, [productId]);
    if (!product) return { product: null, outOfStock: false };

    const station = await this.repo.categoryStation(tx, product.categoryId);
    const locationId = await this.salesLocationFor(tx, outletId, station);
    if (!locationId) return { product, outOfStock: false };

    const itemIds = await this.repo.recipeStockItemIdsForProduct(tx, productId);
    if (itemIds.length === 0) return { product, outOfStock: false };

    const levels = await this.repo.levelsAt(tx, locationId, itemIds);
    const onHand = new Map<string, Prisma.Decimal>(
      levels.map((l): [string, Prisma.Decimal] => [l.stockItemId, l.onHand]),
    );
    const outOfStock = itemIds.some((id) => (onHand.get(id) ?? new Prisma.Decimal(0)).lte(0));
    return { product, outOfStock };
  }

  /** Clears auto-86 on products whose recipe items are all above zero again. Manual 86 is kept. */
  private async autoUnEightySix(tx: Prisma.TransactionClient, ctx: MovementContext, stockItemIds: string[]) {
    if (stockItemIds.length === 0) return;
    const productIds = await this.repo.auto86ProductsUsing(tx, stockItemIds);
    for (const productId of productIds) {
      const { product, outOfStock } = await this.recipeAvailability(tx, ctx.outletId, productId);
      if (!product || !product.is86 || !product.auto86 || outOfStock) continue;
      await this.repo.setEightySix(tx, productId, false, false);
      this.emit(ctx, {
        scope: 'outlet',
        outletId: ctx.outletId,
        event: 'menu.item86',
        payload: { productId, name: product.name, is86: false, auto: false },
      });
    }
  }

  private async businessDateOf(tx: Prisma.TransactionClient, ctx: MovementContext): Promise<Date> {
    const tz = await this.repo.outletTimezone(tx, ctx.outletId);
    return toDateOnly(businessDateFor(ctx.now, tz, '05:00'));
  }

  private emit(ctx: MovementContext, event: RealtimeEvent): void {
    ctx.events?.push(event);
  }
}
