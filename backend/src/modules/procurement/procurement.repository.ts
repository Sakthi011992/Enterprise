import { Injectable } from '@nestjs/common';
import { Prisma, PurchaseOrderStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export type Tx = Prisma.TransactionClient;

/** Data access for vendors, purchase orders, goods receipts, debit notes and the reads they need. */
@Injectable()
export class ProcurementRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

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

  createNotification(tx: Tx, data: Prisma.NotificationUncheckedCreateInput) {
    return tx.notification.create({ data });
  }

  // ---------------------------------------------------------------------------
  // Vendors
  // ---------------------------------------------------------------------------

  listVendors(where: Prisma.VendorWhereInput) {
    return this.prisma.vendor.findMany({ where, orderBy: { name: 'asc' } });
  }

  findVendor(id: string) {
    return this.prisma.vendor.findFirst({ where: { id } });
  }

  findVendorsByIds(ids: string[]) {
    return this.prisma.vendor.findMany({ where: { id: { in: ids } } });
  }

  findVendorByName(name: string, exceptId?: string) {
    return this.prisma.vendor.findFirst({ where: { name, ...(exceptId ? { id: { not: exceptId } } : {}) } });
  }

  createVendor(data: Prisma.VendorUncheckedCreateInput) {
    return this.prisma.vendor.create({ data });
  }

  updateVendor(id: string, data: Prisma.VendorUncheckedUpdateInput) {
    return this.prisma.vendor.update({ where: { id }, data });
  }

  /** Purchase orders of the outlet that are not received or cancelled, by vendor. */
  openPurchaseOrdersByVendor(outletId: string) {
    return this.prisma.purchaseOrder.findMany({
      where: { outletId, status: { notIn: ['RECEIVED', 'CANCELLED'] } },
      select: { vendorId: true },
    });
  }

  // ---------------------------------------------------------------------------
  // Locations, items, levels
  // ---------------------------------------------------------------------------

  listLocations(outletId: string) {
    return this.prisma.stockLocation.findMany({
      where: { outletId, isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  findLocationsByIds(outletId: string, ids: string[]) {
    return this.prisma.stockLocation.findMany({ where: { outletId, id: { in: ids } } });
  }

  findItemsByIds(ids: string[]) {
    return this.prisma.stockItem.findMany({ where: { id: { in: ids } } });
  }

  findItems(where: Prisma.StockItemWhereInput) {
    return this.prisma.stockItem.findMany({ where, orderBy: { name: 'asc' } });
  }

  levelsForLocations(locationIds: string[]) {
    return this.prisma.stockLevel.findMany({ where: { locationId: { in: locationIds } } });
  }

  /** Stores the latest purchase rate on the item (PLAN.md 1.7, GRN post step 1). */
  updateItemRate(tx: Tx, stockItemId: string, rate: Prisma.Decimal) {
    return tx.stockItem.update({ where: { id: stockItemId }, data: { lastPurchaseRate: rate } });
  }

  // ---------------------------------------------------------------------------
  // Purchase orders
  // ---------------------------------------------------------------------------

  listPurchaseOrders(outletId: string, where: Prisma.PurchaseOrderWhereInput) {
    return this.prisma.purchaseOrder.findMany({
      where: { outletId, ...where },
      orderBy: { createdAt: 'desc' },
    });
  }

  countPurchaseOrdersByStatus(outletId: string) {
    return this.prisma.purchaseOrder.groupBy({
      by: ['status'],
      where: { outletId },
      _count: { _all: true },
    });
  }

  findPurchaseOrder(outletId: string, id: string) {
    return this.prisma.purchaseOrder.findFirst({ where: { id, outletId } });
  }

  poLines(poIds: string[]) {
    return this.prisma.purchaseOrderLine.findMany({
      where: { poId: { in: poIds } },
      orderBy: { sortOrder: 'asc' },
    });
  }

  poLinesIn(tx: Tx, poId: string) {
    return tx.purchaseOrderLine.findMany({ where: { poId }, orderBy: { sortOrder: 'asc' } });
  }

  createPurchaseOrder(tx: Tx, data: Prisma.PurchaseOrderUncheckedCreateInput) {
    return tx.purchaseOrder.create({ data });
  }

  updatePurchaseOrder(tx: Tx, id: string, data: Prisma.PurchaseOrderUncheckedUpdateInput) {
    return tx.purchaseOrder.update({ where: { id }, data });
  }

  deletePurchaseOrder(tx: Tx, id: string) {
    return tx.purchaseOrder.delete({ where: { id } });
  }

  deletePoLines(tx: Tx, poId: string) {
    return tx.purchaseOrderLine.deleteMany({ where: { poId } });
  }

  createPoLines(tx: Tx, rows: Prisma.PurchaseOrderLineUncheckedCreateInput[]) {
    return tx.purchaseOrderLine.createMany({ data: rows });
  }

  /** Adds a posted quantity to a PO line (PLAN.md 1.7, GRN post step 4). */
  addPoLineReceived(tx: Tx, poLineId: string, qty: Prisma.Decimal) {
    return tx.purchaseOrderLine.update({ where: { id: poLineId }, data: { receivedQty: { increment: qty } } });
  }

  // ---------------------------------------------------------------------------
  // Goods receipts
  // ---------------------------------------------------------------------------

  listGoodsReceipts(outletId: string, where: Prisma.GoodsReceiptWhereInput) {
    return this.prisma.goodsReceipt.findMany({
      where: { outletId, ...where },
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
  }

  findGoodsReceipt(outletId: string, id: string) {
    return this.prisma.goodsReceipt.findFirst({ where: { id, outletId } });
  }

  grnLines(grnIds: string[]) {
    return this.prisma.goodsReceiptLine.findMany({ where: { grnId: { in: grnIds } } });
  }

  grnLinesIn(tx: Tx, grnId: string) {
    return tx.goodsReceiptLine.findMany({ where: { grnId } });
  }

  grnsForPurchaseOrder(outletId: string, poId: string) {
    return this.prisma.goodsReceipt.findMany({
      where: { outletId, poId },
      orderBy: { createdAt: 'asc' },
    });
  }

  createGoodsReceipt(tx: Tx, data: Prisma.GoodsReceiptUncheckedCreateInput) {
    return tx.goodsReceipt.create({ data });
  }

  /** Marks a DRAFT receipt POSTED; returns 0 when another request posted it first. */
  claimDraftGrn(tx: Tx, id: string) {
    return tx.goodsReceipt.updateMany({ where: { id, status: 'DRAFT' }, data: { status: 'POSTED' } }).then((r) => r.count);
  }

  updateGoodsReceipt(tx: Tx, id: string, data: Prisma.GoodsReceiptUncheckedUpdateInput) {
    return tx.goodsReceipt.update({ where: { id }, data });
  }

  deleteGrnLines(tx: Tx, grnId: string) {
    return tx.goodsReceiptLine.deleteMany({ where: { grnId } });
  }

  createGrnLines(tx: Tx, rows: Prisma.GoodsReceiptLineUncheckedCreateInput[]) {
    return tx.goodsReceiptLine.createMany({ data: rows });
  }

  // ---------------------------------------------------------------------------
  // Debit notes
  // ---------------------------------------------------------------------------

  listDebitNotes(outletId: string, where: Prisma.DebitNoteWhereInput) {
    return this.prisma.debitNote.findMany({
      where: { outletId, ...where },
      orderBy: { createdAt: 'desc' },
    });
  }

  findDebitNote(outletId: string, id: string) {
    return this.prisma.debitNote.findFirst({ where: { id, outletId } });
  }

  createDebitNote(tx: Tx, data: Prisma.DebitNoteUncheckedCreateInput) {
    return tx.debitNote.create({ data });
  }

  createWastage(tx: Tx, data: Prisma.WastageEntryUncheckedCreateInput) {
    return tx.wastageEntry.create({ data });
  }

  settleDebitNote(tx: Tx, id: string) {
    return tx.debitNote.update({ where: { id }, data: { status: 'SETTLED' } });
  }

  grnsByIds(ids: string[]) {
    return this.prisma.goodsReceipt.findMany({ where: { id: { in: ids } }, select: { id: true, number: true } });
  }

  posByIds(ids: string[]) {
    return this.prisma.purchaseOrder.findMany({ where: { id: { in: ids } }, select: { id: true, number: true } });
  }
}

/** PO statuses that can receive goods (PLAN.md 1.7, GRN create). */
export const RECEIVABLE_PO_STATUSES: PurchaseOrderStatus[] = ['SENT', 'PARTLY_RECEIVED', 'INVOICE_MISMATCH'];
