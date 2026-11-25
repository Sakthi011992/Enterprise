import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export type Tx = Prisma.TransactionClient;

/**
 * Data access for locations, stock items, levels, movements, transfers, counts, wastage, recipes and
 * the outlet reads the inventory views need. Writes to stock go through StockLedgerService, never here;
 * the only movement-adjacent write is the par level upsert on StockLevel.
 */
@Injectable()
export class InventoryRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  // ---------------------------------------------------------------------------
  // Outlet, users, vendors
  // ---------------------------------------------------------------------------

  async outletTimezone(outletId: string): Promise<string> {
    const outlet = await this.prisma.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
    return outlet?.timezone ?? 'Asia/Kolkata';
  }

  findUsers(ids: string[]) {
    return this.prisma.user.findMany({
      where: { id: { in: ids } },
      select: { id: true, username: true, displayName: true },
    });
  }

  findVendor(id: string) {
    return this.prisma.vendor.findFirst({ where: { id } });
  }

  findVendorsByIds(ids: string[]) {
    return this.prisma.vendor.findMany({ where: { id: { in: ids } } });
  }

  createNotification(tx: Tx, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }

  // ---------------------------------------------------------------------------
  // Locations and levels
  // ---------------------------------------------------------------------------

  listLocations(outletId: string) {
    return this.prisma.stockLocation.findMany({
      where: { outletId, isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  findLocation(outletId: string, id: string) {
    return this.prisma.stockLocation.findFirst({ where: { id, outletId } });
  }

  findLocationsByIds(outletId: string, ids: string[]) {
    return this.prisma.stockLocation.findMany({ where: { outletId, id: { in: ids } } });
  }

  findLocationByName(outletId: string, name: string) {
    return this.prisma.stockLocation.findFirst({ where: { outletId, name } });
  }

  createLocation(tx: Tx, data: Prisma.StockLocationUncheckedCreateInput) {
    return tx.stockLocation.create({ data });
  }

  updateLocation(tx: Tx, id: string, data: Prisma.StockLocationUncheckedUpdateInput) {
    return tx.stockLocation.update({ where: { id }, data });
  }

  clearDefaultSales(tx: Tx, outletId: string, exceptId?: string) {
    return tx.stockLocation.updateMany({
      where: { outletId, isDefaultSales: true, ...(exceptId ? { id: { not: exceptId } } : {}) },
      data: { isDefaultSales: false },
    });
  }

  levelsForLocations(locationIds: string[]) {
    return this.prisma.stockLevel.findMany({ where: { locationId: { in: locationIds } } });
  }

  findLevel(locationId: string, stockItemId: string) {
    return this.prisma.stockLevel.findUnique({
      where: { locationId_stockItemId: { locationId, stockItemId } },
    });
  }

  upsertPar(tx: Tx, locationId: string, stockItemId: string, parLevel: Prisma.Decimal) {
    return tx.stockLevel.upsert({
      where: { locationId_stockItemId: { locationId, stockItemId } },
      create: { locationId, stockItemId, parLevel },
      update: { parLevel },
    });
  }

  // ---------------------------------------------------------------------------
  // Stock items
  // ---------------------------------------------------------------------------

  findItems(where: Prisma.StockItemWhereInput) {
    return this.prisma.stockItem.findMany({ where, orderBy: { name: 'asc' } });
  }

  findItem(id: string) {
    return this.prisma.stockItem.findFirst({ where: { id } });
  }

  findItemsByIds(ids: string[]) {
    return this.prisma.stockItem.findMany({ where: { id: { in: ids } } });
  }

  findItemByName(name: string, exceptId?: string) {
    return this.prisma.stockItem.findFirst({
      where: { name, ...(exceptId ? { id: { not: exceptId } } : {}) },
    });
  }

  createItem(tx: Tx, data: Prisma.StockItemUncheckedCreateInput) {
    return tx.stockItem.create({ data });
  }

  updateItem(tx: Tx, id: string, data: Prisma.StockItemUncheckedUpdateInput) {
    return tx.stockItem.update({ where: { id }, data });
  }

  // ---------------------------------------------------------------------------
  // Movements (reads only)
  // ---------------------------------------------------------------------------

  itemMovements(where: Prisma.StockMovementWhereInput, take: number) {
    return this.prisma.stockMovement.findMany({ where, orderBy: { createdAt: 'desc' }, take });
  }

  movementsWhere(where: Prisma.StockMovementWhereInput) {
    return this.prisma.stockMovement.findMany({ where, orderBy: [{ businessDate: 'asc' }, { createdAt: 'asc' }] });
  }

  /** Sum of movement quantities per item before a date, the "opening" of the variance formula. */
  openingSums(outletId: string, before: Date, locationId: string | null, stockItemIds: string[] | null) {
    return this.prisma.stockMovement.groupBy({
      by: ['stockItemId'],
      where: {
        outletId,
        businessDate: { lt: before },
        ...(locationId ? { locationId } : {}),
        ...(stockItemIds ? { stockItemId: { in: stockItemIds } } : {}),
      },
      _sum: { qty: true },
    });
  }

  /** COUNT_ADJUST movements since a business date, used for the VARIANCE flag. */
  countAdjustmentsSince(outletId: string, since: Date) {
    return this.prisma.stockMovement.findMany({
      where: { outletId, type: 'COUNT_ADJUST', businessDate: { gte: since } },
      select: { stockItemId: true, refId: true, qty: true, unitCost: true },
    });
  }

  countAdjustmentsOf(countId: string) {
    return this.prisma.stockMovement.findMany({
      where: { refType: 'COUNT', refId: countId, type: 'COUNT_ADJUST' },
    });
  }

  saleMovements(outletId: string, from: Date, to: Date, stockItemIds: string[]) {
    return this.prisma.stockMovement.findMany({
      where: {
        outletId,
        type: 'SALE',
        businessDate: { gte: from, lte: to },
        stockItemId: { in: stockItemIds },
      },
      select: { stockItemId: true, qty: true, unitCost: true },
    });
  }

  // ---------------------------------------------------------------------------
  // Transfers
  // ---------------------------------------------------------------------------

  findTransfers(outletId: string, createdAt?: { gte: Date; lte: Date }) {
    return this.prisma.stockTransfer.findMany({
      where: { outletId, ...(createdAt ? { createdAt } : {}) },
      orderBy: { createdAt: 'desc' },
    });
  }

  findTransfer(outletId: string, id: string) {
    return this.prisma.stockTransfer.findFirst({ where: { id, outletId } });
  }

  transferLines(transferIds: string[]) {
    return this.prisma.stockTransferLine.findMany({ where: { transferId: { in: transferIds } } });
  }

  createTransfer(tx: Tx, data: Prisma.StockTransferUncheckedCreateInput) {
    return tx.stockTransfer.create({ data });
  }

  createTransferLines(tx: Tx, rows: Prisma.StockTransferLineUncheckedCreateInput[]) {
    return tx.stockTransferLine.createMany({ data: rows });
  }

  // ---------------------------------------------------------------------------
  // Stock counts
  // ---------------------------------------------------------------------------

  findCounts(outletId: string, where: Prisma.StockCountWhereInput) {
    return this.prisma.stockCount.findMany({ where: { outletId, ...where }, orderBy: { createdAt: 'desc' } });
  }

  findCount(outletId: string, id: string) {
    return this.prisma.stockCount.findFirst({ where: { id, outletId } });
  }

  /** A count at this location that is still open or submitted (one live count per location). */
  findLiveCount(outletId: string, locationId: string) {
    return this.prisma.stockCount.findFirst({
      where: { outletId, locationId, status: { in: ['OPEN', 'SUBMITTED'] } },
    });
  }

  countLines(countIds: string[]) {
    return this.prisma.stockCountLine.findMany({ where: { countId: { in: countIds } } });
  }

  createCount(tx: Tx, data: Prisma.StockCountUncheckedCreateInput) {
    return tx.stockCount.create({ data });
  }

  /** Moves a SUBMITTED count to POSTED; returns 0 when another request posted it first. */
  claimSubmittedCount(tx: Prisma.TransactionClient, id: string) {
    return tx.stockCount.updateMany({ where: { id, status: 'SUBMITTED' }, data: { status: 'POSTED' } }).then((r) => r.count);
  }

  updateCount(tx: Tx, id: string, data: Prisma.StockCountUncheckedUpdateInput) {
    return tx.stockCount.update({ where: { id }, data });
  }

  createCountLines(tx: Tx, rows: Prisma.StockCountLineUncheckedCreateInput[]) {
    return tx.stockCountLine.createMany({ data: rows });
  }

  /** Upserts one count line; only the keys present in `data` change (idempotent offline replays, PLAN.md 1.7). */
  upsertCountLine(
    tx: Tx,
    countId: string,
    stockItemId: string,
    data: {
      countedQty?: Prisma.Decimal | null;
      note?: string | null;
      confirmedOutlier?: boolean;
      countedAt?: Date | null;
      countedById?: string | null;
    },
  ) {
    return tx.stockCountLine.upsert({
      where: { countId_stockItemId: { countId, stockItemId } },
      create: {
        countId,
        stockItemId,
        countedQty: data.countedQty ?? null,
        note: data.note ?? null,
        confirmedOutlier: data.confirmedOutlier ?? false,
        countedAt: data.countedAt ?? null,
        countedById: data.countedById ?? null,
      },
      update: data,
    });
  }

  setCountLineExpected(tx: Tx, countId: string, stockItemId: string, expectedQty: Prisma.Decimal) {
    return tx.stockCountLine.updateMany({ where: { countId, stockItemId }, data: { expectedQty } });
  }

  updateCountLine(tx: Tx, id: string, data: Prisma.StockCountLineUncheckedUpdateInput) {
    return tx.stockCountLine.update({ where: { id }, data });
  }

  // ---------------------------------------------------------------------------
  // Wastage
  // ---------------------------------------------------------------------------

  findWastage(outletId: string, where: Prisma.WastageEntryWhereInput) {
    return this.prisma.wastageEntry.findMany({
      where: { outletId, ...where },
      orderBy: { createdAt: 'desc' },
    });
  }

  createWastage(tx: Tx, data: Prisma.WastageEntryUncheckedCreateInput) {
    return tx.wastageEntry.create({ data });
  }

  // ---------------------------------------------------------------------------
  // GRN expiries (EXPIRES flag)
  // ---------------------------------------------------------------------------

  recentGrnIds(outletId: string, receivedSince: Date) {
    return this.prisma.goodsReceipt.findMany({
      where: { outletId, receivedOn: { gte: receivedSince } },
      select: { id: true },
    });
  }

  expiringGrnLines(grnIds: string[], from: Date, to: Date) {
    return this.prisma.goodsReceiptLine.findMany({
      where: { grnId: { in: grnIds }, expiry: { gte: from, lte: to } },
      select: { stockItemId: true },
    });
  }

  // ---------------------------------------------------------------------------
  // Pour cost (liquor recipes and sales)
  // ---------------------------------------------------------------------------

  /** Products whose recipe (any variant) uses one of these stock items. */
  async productIdsUsingItems(stockItemIds: string[]): Promise<string[]> {
    const lines = await this.prisma.recipeLine.findMany({
      where: { stockItemId: { in: stockItemIds } },
      select: { recipeId: true },
    });
    const recipeIds = [...new Set(lines.map((l) => l.recipeId))];
    if (recipeIds.length === 0) return [];
    const recipes = await this.prisma.recipe.findMany({ where: { id: { in: recipeIds } }, select: { productId: true } });
    return [...new Set(recipes.map((r) => r.productId))];
  }

  orderIdsBetween(outletId: string, from: Date, to: Date) {
    return this.prisma.order.findMany({
      where: { outletId, createdAt: { gte: from, lt: to } },
      select: { id: true },
    });
  }

  orderItemsFor(orderIds: string[], productIds: string[]) {
    return this.prisma.orderItem.findMany({
      where: { orderId: { in: orderIds }, productId: { in: productIds }, voidedAt: null },
      select: { productId: true, lineTotal: true, taxAmount: true },
    });
  }

  // ---------------------------------------------------------------------------
  // Recipes
  // ---------------------------------------------------------------------------

  findProduct(id: string) {
    return this.prisma.product.findFirst({ where: { id, deletedAt: null } });
  }

  findProductsByIds(ids: string[]) {
    return this.prisma.product.findMany({ where: { id: { in: ids } } });
  }

  productVariants(productId: string) {
    return this.prisma.productVariant.findMany({ where: { productId }, orderBy: { sortOrder: 'asc' } });
  }

  recipesForProduct(productId: string) {
    return this.prisma.recipe.findMany({
      where: { productId },
      include: { lines: { orderBy: { sortOrder: 'asc' } } },
    });
  }

  taxClassesByIds(ids: string[]) {
    return this.prisma.taxClass.findMany({ where: { id: { in: ids } } });
  }

  deleteRecipesForProduct(tx: Tx, productId: string) {
    return tx.recipe.deleteMany({ where: { productId } });
  }

  createRecipe(tx: Tx, data: Prisma.RecipeUncheckedCreateInput) {
    return tx.recipe.create({ data });
  }
}
