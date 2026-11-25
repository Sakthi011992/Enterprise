import { Injectable } from '@nestjs/common';
import { Prisma, StockMovementType } from '@prisma/client';

// All Prisma access of the stock ledger. Every method takes the caller's transaction client.

export interface LedgerItem {
  id: string;
  name: string;
  avgCost: Prisma.Decimal;
}

export interface LedgerLocation {
  id: string;
  outletId: string;
  name: string;
  isActive: boolean;
  stations: string[];
  isDefaultSales: boolean;
}

export interface LevelRow {
  onHand: Prisma.Decimal;
  parLevel: Prisma.Decimal;
}

export interface LedgerProduct {
  id: string;
  name: string;
  is86: boolean;
  auto86: boolean;
  categoryId: string | null;
}

export interface LedgerRecipe {
  productId: string;
  variantId: string | null;
  lines: { stockItemId: string; qty: Prisma.Decimal; wastagePercent: Prisma.Decimal; sortOrder: number }[];
}

@Injectable()
export class StockLedgerRepository {
  findItem(tx: Prisma.TransactionClient, id: string): Promise<LedgerItem | null> {
    return tx.stockItem.findFirst({ where: { id }, select: { id: true, name: true, avgCost: true } });
  }

  findLocation(tx: Prisma.TransactionClient, id: string): Promise<LedgerLocation | null> {
    return tx.stockLocation.findFirst({
      where: { id },
      select: { id: true, outletId: true, name: true, isActive: true, stations: true, isDefaultSales: true },
    });
  }

  activeLocations(tx: Prisma.TransactionClient, outletId: string): Promise<LedgerLocation[]> {
    return tx.stockLocation.findMany({
      where: { outletId, isActive: true },
      orderBy: { sortOrder: 'asc' },
      select: { id: true, outletId: true, name: true, isActive: true, stations: true, isDefaultSales: true },
    });
  }

  findLevel(tx: Prisma.TransactionClient, locationId: string, stockItemId: string): Promise<LevelRow | null> {
    return tx.stockLevel.findUnique({
      where: { locationId_stockItemId: { locationId, stockItemId } },
      select: { onHand: true, parLevel: true },
    });
  }

  /** Adds `delta` to the level row (creating it when missing) and returns the row after the change. */
  addToLevel(
    tx: Prisma.TransactionClient,
    locationId: string,
    stockItemId: string,
    delta: Prisma.Decimal,
  ): Promise<LevelRow> {
    return tx.stockLevel.upsert({
      where: { locationId_stockItemId: { locationId, stockItemId } },
      create: { locationId, stockItemId, onHand: delta },
      update: { onHand: { increment: delta } },
      select: { onHand: true, parLevel: true },
    });
  }

  /** Total on hand of one item across every location of the tenant. */
  async totalOnHand(tx: Prisma.TransactionClient, tenantId: string, stockItemId: string): Promise<Prisma.Decimal> {
    const agg = await tx.stockLevel.aggregate({
      where: { stockItemId, location: { tenantId } },
      _sum: { onHand: true },
    });
    return agg._sum.onHand ?? new Prisma.Decimal(0);
  }

  async setAvgCost(tx: Prisma.TransactionClient, stockItemId: string, avgCost: Prisma.Decimal): Promise<void> {
    await tx.stockItem.update({ where: { id: stockItemId }, data: { avgCost } });
  }

  createMovement(tx: Prisma.TransactionClient, data: Prisma.StockMovementUncheckedCreateInput) {
    return tx.stockMovement.create({ data });
  }

  async outletTimezone(tx: Prisma.TransactionClient, outletId: string): Promise<string> {
    const outlet = await tx.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
    return outlet?.timezone ?? 'Asia/Kolkata';
  }

  findProductsForEightySix(tx: Prisma.TransactionClient, productIds: string[]): Promise<LedgerProduct[]> {
    return tx.product.findMany({
      where: { id: { in: productIds } },
      select: { id: true, name: true, is86: true, auto86: true, categoryId: true },
    });
  }

  /** Station of a category; products without a category route to the kitchen (as the orders module does). */
  async categoryStation(tx: Prisma.TransactionClient, categoryId: string | null): Promise<string> {
    if (!categoryId) return 'KITCHEN';
    const cat = await tx.category.findFirst({ where: { id: categoryId }, select: { station: true } });
    return cat?.station ?? 'KITCHEN';
  }

  findRecipe(tx: Prisma.TransactionClient, productId: string, variantId: string | null): Promise<LedgerRecipe | null> {
    return tx.recipe.findFirst({
      where: { productId, variantId },
      select: {
        productId: true,
        variantId: true,
        lines: {
          orderBy: { sortOrder: 'asc' },
          select: { stockItemId: true, qty: true, wastagePercent: true, sortOrder: true },
        },
      },
    });
  }

  modifierOptionStock(
    tx: Prisma.TransactionClient,
    optionIds: string[],
  ): Promise<{ id: string; stockItemId: string | null; stockQty: Prisma.Decimal | null }[]> {
    return tx.modifierOption.findMany({
      where: { id: { in: optionIds } },
      select: { id: true, stockItemId: true, stockQty: true },
    });
  }

  async recipeStockItemIdsForProduct(tx: Prisma.TransactionClient, productId: string): Promise<string[]> {
    const rows = await tx.recipeLine.findMany({
      where: { recipe: { productId } },
      select: { stockItemId: true },
    });
    return [...new Set(rows.map((r) => r.stockItemId))];
  }

  levelsAt(
    tx: Prisma.TransactionClient,
    locationId: string,
    stockItemIds: string[],
  ): Promise<{ stockItemId: string; onHand: Prisma.Decimal }[]> {
    return tx.stockLevel.findMany({
      where: { locationId, stockItemId: { in: stockItemIds } },
      select: { stockItemId: true, onHand: true },
    });
  }

  /** Products that are auto-86'd and whose recipes (any variant) use one of the given items. */
  async auto86ProductsUsing(tx: Prisma.TransactionClient, stockItemIds: string[]): Promise<string[]> {
    const rows = await tx.recipeLine.findMany({
      where: {
        stockItemId: { in: stockItemIds },
        recipe: { product: { is86: true, auto86: true } },
      },
      select: { recipe: { select: { productId: true } } },
    });
    return [...new Set(rows.map((r) => r.recipe.productId))];
  }

  setEightySix(tx: Prisma.TransactionClient, productId: string, is86: boolean, auto86: boolean): Promise<unknown> {
    return tx.product.update({ where: { id: productId }, data: { is86, auto86 } });
  }

  createWastage(tx: Prisma.TransactionClient, data: Prisma.WastageEntryUncheckedCreateInput) {
    return tx.wastageEntry.create({ data });
  }

  movementsByRef(
    tx: Prisma.TransactionClient,
    refType: string,
    refIds: string[],
    types: StockMovementType[],
  ) {
    return tx.stockMovement.findMany({
      where: { refType, refId: { in: refIds }, type: { in: types } },
      orderBy: { createdAt: 'asc' },
    });
  }

  createNotification(tx: Prisma.TransactionClient, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }
}
