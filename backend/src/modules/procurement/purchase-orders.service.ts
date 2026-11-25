import { Injectable } from '@nestjs/common';
import { Prisma, PurchaseOrder, PurchaseOrderLine, PurchaseOrderStatus } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { DocumentNumberRepository } from '../stock-core/document-number.repository';
import { nextDocNumber } from '../stock-core/stock-math';
import { dateInput, decimalInput } from '../inventory/decimal-input';
import { ZERO, inr, money2, qty3, qtyDisplay, userName, ymd } from '../inventory/inventory-views';
import {
  CancelPurchaseOrderDto,
  PurchaseOrderDto,
  PurchaseOrdersQueryDto,
  ReorderRequestDto,
  ReorderSuggestionsQueryDto,
} from './dto/procurement.dto';
import { grnSummaryViews } from './procurement-views';
import { lineTotal, suggestedPurchaseQty } from './procurement-math';
import { ProcurementRepository, Tx } from './procurement.repository';

export const PO_STATUSES: PurchaseOrderStatus[] = [
  'DRAFT',
  'PENDING_APPROVAL',
  'APPROVED',
  'SENT',
  'PARTLY_RECEIVED',
  'RECEIVED',
  'INVOICE_MISMATCH',
  'CANCELLED',
];

export interface ParsedPoLine {
  stockItemId: string;
  qty: Prisma.Decimal;
  rate: Prisma.Decimal;
}

/** Purchase orders, reorder suggestions and reorder requests (PLAN.md 1.6 and 1.7). */
@Injectable()
export class PurchaseOrdersService {
  constructor(
    private repo: ProcurementRepository,
    private docs: DocumentNumberRepository,
  ) {}

  /** Counts per status for the outlet (all orders), and the orders matching the filters. */
  async list(q: PurchaseOrdersQueryDto, auth: AuthUser) {
    const tally = await this.repo.countPurchaseOrdersByStatus(auth.outletId);
    const counts: Record<string, number> = {};
    for (const s of PO_STATUSES) counts[s] = 0;
    for (const row of tally) counts[row.status] = row._count._all;

    const items = await this.repo.listPurchaseOrders(auth.outletId, {
      ...(q.status ? { status: q.status } : {}),
      ...(q.vendorId ? { vendorId: q.vendorId } : {}),
    });
    return { counts, items: await this.summaries(auth.outletId, items) };
  }

  async get(id: string, auth: AuthUser) {
    const po = await this.load(auth.outletId, id);
    return this.fullView(auth.outletId, po);
  }

  async create(dto: PurchaseOrderDto, auth: AuthUser) {
    const lines = this.parseLines(dto.lines);
    await this.validateRefs(auth.outletId, dto.vendorId, dto.locationId, lines);
    const po = await this.repo.transaction(async (tx) => {
      const n = await this.docs.next(tx, auth.tenantId, 'PO');
      const created = await this.repo.createPurchaseOrder(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        number: nextDocNumber('PO', n),
        status: 'DRAFT',
        createdById: auth.userId,
        ...this.headerData(dto, lines),
      });
      await this.repo.createPoLines(tx, this.lineRows(created.id, lines));
      return created;
    });
    return this.fullView(auth.outletId, po);
  }

  /** Editing returns a PENDING_APPROVAL order to DRAFT (PLAN.md 1.7). */
  async update(id: string, dto: PurchaseOrderDto, auth: AuthUser) {
    const current = await this.load(auth.outletId, id);
    if (current.status !== 'DRAFT' && current.status !== 'PENDING_APPROVAL') {
      throw apiError(409, 'PO_NOT_EDITABLE', 'Only draft orders can be edited');
    }
    const lines = this.parseLines(dto.lines);
    await this.validateRefs(auth.outletId, dto.vendorId, dto.locationId, lines);
    await this.repo.transaction(async (tx) => {
      await this.repo.deletePoLines(tx, id);
      await this.repo.createPoLines(tx, this.lineRows(id, lines));
      await this.repo.updatePurchaseOrder(tx, id, { ...this.headerData(dto, lines), status: 'DRAFT' });
    });
    return this.get(id, auth);
  }

  async remove(id: string, auth: AuthUser): Promise<{ success: true }> {
    const current = await this.load(auth.outletId, id);
    if (current.status !== 'DRAFT') throw apiError(409, 'PO_NOT_EDITABLE', 'Only draft orders can be deleted');
    await this.repo.transaction(async (tx) => {
      await this.repo.deletePoLines(tx, id);
      await this.repo.deletePurchaseOrder(tx, id);
    });
    return { success: true };
  }

  async submit(id: string, auth: AuthUser) {
    const current = await this.load(auth.outletId, id);
    if (current.status !== 'DRAFT') throw apiError(409, 'PO_NOT_EDITABLE', 'Only draft orders can be submitted');
    await this.repo.transaction(async (tx) => {
      await this.repo.updatePurchaseOrder(tx, id, { status: 'PENDING_APPROVAL', submittedAt: new Date() });
      await this.notifyApprovers(tx, auth, current, `${current.number} is waiting for approval`);
    });
    return this.get(id, auth);
  }

  async approve(id: string, auth: AuthUser) {
    const current = await this.load(auth.outletId, id);
    if (current.status !== 'PENDING_APPROVAL') {
      throw apiError(409, 'PO_NOT_PENDING', 'This order is not waiting for approval');
    }
    await this.repo.transaction(async (tx) =>
      this.repo.updatePurchaseOrder(tx, id, { status: 'APPROVED', approvedById: auth.userId, approvedAt: new Date() }),
    );
    return this.get(id, auth);
  }

  /**
   * Allowed from APPROVED. The controller requires APPROVE, so a caller with APPROVE may also send a
   * DRAFT or PENDING_APPROVAL order; that approves it on the way (PLAN.md 1.6 and 1.7).
   */
  async send(id: string, auth: AuthUser) {
    const current = await this.load(auth.outletId, id);
    if (!['APPROVED', 'DRAFT', 'PENDING_APPROVAL'].includes(current.status)) {
      throw apiError(409, 'PO_NOT_APPROVED', 'The order must be approved before it is sent');
    }
    const now = new Date();
    const autoApprove = current.status !== 'APPROVED';
    await this.repo.transaction(async (tx) =>
      this.repo.updatePurchaseOrder(tx, id, {
        status: 'SENT',
        sentAt: now,
        ...(autoApprove ? { approvedById: auth.userId, approvedAt: now } : {}),
      }),
    );
    return this.get(id, auth);
  }

  async cancel(id: string, dto: CancelPurchaseOrderDto, auth: AuthUser) {
    const current = await this.load(auth.outletId, id);
    const lines = await this.repo.poLines([id]);
    if (current.status === 'RECEIVED' || lines.some((l) => l.receivedQty.gt(0))) {
      throw apiError(409, 'PO_RECEIVED', 'Goods have been received against this order');
    }
    if (current.status !== 'CANCELLED') {
      const note = [current.note, `Cancelled: ${dto.reason}`].filter((v): v is string => !!v).join('\n');
      await this.repo.transaction(async (tx) => this.repo.updatePurchaseOrder(tx, id, { status: 'CANCELLED', note }));
    }
    return this.get(id, auth);
  }

  // ===========================================================================
  // Reorder
  // ===========================================================================

  /** Items below par at each location, with the suggested quantity in purchase units (PLAN.md 1.7). */
  async reorderSuggestions(q: ReorderSuggestionsQueryDto, auth: AuthUser) {
    const locations = await this.repo.listLocations(auth.outletId);
    const scope = q.locationId ? locations.filter((l) => l.id === q.locationId) : locations;
    if (q.locationId && scope.length === 0) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    const locationName = new Map(scope.map((l) => [l.id, l.name]));

    const levels = await this.repo.levelsForLocations(scope.map((l) => l.id));
    const belowPar = levels.filter((lv) => lv.parLevel.gt(0) && lv.onHand.lt(lv.parLevel));
    const items = await this.repo.findItemsByIds([...new Set(belowPar.map((lv) => lv.stockItemId))]);
    const itemById = new Map(items.filter((i) => i.isActive).map((i) => [i.id, i]));
    const vendorIds = [...new Set([...itemById.values()].map((i) => i.preferredVendorId).filter((v): v is string => !!v))];
    const vendorById = new Map((await this.repo.findVendorsByIds(vendorIds)).map((v) => [v.id, v]));

    return belowPar
      .filter((lv) => itemById.has(lv.stockItemId))
      .map((lv) => {
        const item = itemById.get(lv.stockItemId)!;
        const vendor = item.preferredVendorId ? vendorById.get(item.preferredVendorId) : undefined;
        return {
          stockItemId: item.id,
          name: item.name,
          locationId: lv.locationId,
          locationName: locationName.get(lv.locationId) ?? null,
          onHand: qty3(lv.onHand),
          onHandDisplay: qtyDisplay(lv.onHand, item),
          parLevel: qty3(lv.parLevel),
          parDisplay: qtyDisplay(lv.parLevel, item),
          suggestedQty: qty3(suggestedPurchaseQty(lv.parLevel, lv.onHand, item.purchaseUnitQty)),
          purchaseUnitName: item.purchaseUnitName,
          vendor: vendor ? { id: vendor.id, name: vendor.name } : null,
          rate: money2(item.lastPurchaseRate ?? ZERO),
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  /** One PENDING_APPROVAL order per preferred vendor (PLAN.md 1.7). Lines whose item has no vendor are refused. */
  async reorderRequest(dto: ReorderRequestDto, auth: AuthUser) {
    const location = await this.repo.findLocationsByIds(auth.outletId, [dto.locationId]);
    if (location.length === 0) throw apiError(400, 'INVALID_REFERENCE', 'Location not found', { field: 'locationId' });
    if (!dto.lines || dto.lines.length === 0) throw apiError(400, 'EMPTY_PO', 'Add at least one item');

    const lines = dto.lines.map((l) => ({
      stockItemId: l.stockItemId,
      qty: decimalInput(l.qty, 'qty', { dp: 3, min: 0.001 }) as Prisma.Decimal,
    }));
    const itemIds = [...new Set(lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(itemIds);
    if (items.length !== itemIds.length) throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found');
    const itemById = new Map(items.map((i) => [i.id, i]));

    const missing = itemIds.filter((id) => !itemById.get(id)?.preferredVendorId);
    if (missing.length > 0) {
      throw apiError(400, 'VENDOR_MISSING', 'Set a preferred vendor for these items first', { stockItemIds: missing });
    }

    const byVendor = new Map<string, ParsedPoLine[]>();
    for (const l of lines) {
      const item = itemById.get(l.stockItemId)!;
      const vendorId = item.preferredVendorId!;
      const group = byVendor.get(vendorId) ?? [];
      group.push({ stockItemId: l.stockItemId, qty: l.qty, rate: item.lastPurchaseRate ?? ZERO });
      byVendor.set(vendorId, group);
    }

    const created: PurchaseOrder[] = [];
    await this.repo.transaction(async (tx) => {
      for (const [vendorId, group] of byVendor) {
        const n = await this.docs.next(tx, auth.tenantId, 'PO');
        const po = await this.repo.createPurchaseOrder(tx, {
          tenantId: auth.tenantId,
          outletId: auth.outletId,
          number: nextDocNumber('PO', n),
          vendorId,
          locationId: dto.locationId,
          status: 'PENDING_APPROVAL',
          total: this.total(group),
          note: 'Reorder request',
          createdById: auth.userId,
          submittedAt: new Date(),
        });
        await this.repo.createPoLines(tx, this.lineRows(po.id, group));
        await this.notifyApprovers(tx, auth, po, `${po.number} needs approval (reorder)`);
        created.push(po);
      }
    });
    return { purchaseOrders: await this.summaries(auth.outletId, created) };
  }

  // ===========================================================================
  // Views
  // ===========================================================================

  async summaries(outletId: string, pos: PurchaseOrder[]) {
    if (pos.length === 0) return [];
    const vendors = await this.repo.findVendorsByIds([...new Set(pos.map((p) => p.vendorId))]);
    const locations = await this.repo.findLocationsByIds(outletId, [...new Set(pos.map((p) => p.locationId))]);
    const vendorName = new Map(vendors.map((v) => [v.id, v.name]));
    const locationName = new Map(locations.map((l) => [l.id, l.name]));
    return pos.map((p) => ({
      id: p.id,
      number: p.number,
      vendor: { id: p.vendorId, name: vendorName.get(p.vendorId) ?? null },
      location: { id: p.locationId, name: locationName.get(p.locationId) ?? null },
      total: money2(p.total),
      dueDate: p.dueDate ? ymd(p.dueDate) : null,
      status: p.status,
      createdAt: p.createdAt.toISOString(),
    }));
  }

  private async fullView(outletId: string, po: PurchaseOrder) {
    const [summary] = await this.summaries(outletId, [po]);
    const lines = await this.repo.poLines([po.id]);
    const items = await this.repo.findItemsByIds([...new Set(lines.map((l) => l.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    const users = await this.repo.findUsers([po.createdById, po.approvedById].filter((v): v is string => !!v));
    const userById = new Map(users.map((u) => [u.id, userName(u)]));
    const grns = await this.repo.grnsForPurchaseOrder(outletId, po.id);

    return {
      ...summary,
      transportPermitNo: po.transportPermitNo,
      note: po.note,
      createdBy: { id: po.createdById, name: userById.get(po.createdById) ?? null },
      approvedBy: po.approvedById ? { id: po.approvedById, name: userById.get(po.approvedById) ?? null } : null,
      approvedAt: po.approvedAt ? po.approvedAt.toISOString() : null,
      sentAt: po.sentAt ? po.sentAt.toISOString() : null,
      lines: lines.map((l) => this.lineView(l, itemById.get(l.stockItemId))).filter((v): v is NonNullable<typeof v> => v !== null),
      grns: await grnSummaryViews(this.repo, outletId, grns),
    };
  }

  private lineView(l: PurchaseOrderLine, item: { name: string; purchaseUnitName: string } | undefined) {
    if (!item) return null;
    return {
      id: l.id,
      stockItemId: l.stockItemId,
      name: item.name,
      purchaseUnitName: item.purchaseUnitName,
      qty: qty3(l.qty),
      rate: money2(l.rate),
      total: money2(l.total),
      receivedQty: qty3(l.receivedQty),
    };
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  private async load(outletId: string, id: string): Promise<PurchaseOrder> {
    const po = await this.repo.findPurchaseOrder(outletId, id);
    if (!po) throw apiError(404, 'PO_NOT_FOUND', 'Purchase order not found');
    return po;
  }

  private parseLines(lines: PurchaseOrderDto['lines']): ParsedPoLine[] {
    if (!lines || lines.length === 0) throw apiError(400, 'EMPTY_PO', 'Add at least one item');
    return lines.map((l) => ({
      stockItemId: l.stockItemId,
      qty: decimalInput(l.qty, 'qty', { dp: 3, min: 0.001 }) as Prisma.Decimal,
      rate: decimalInput(l.rate, 'rate', { dp: 2, min: 0 }) as Prisma.Decimal,
    }));
  }

  private async validateRefs(outletId: string, vendorId: string, locationId: string, lines: ParsedPoLine[]) {
    if (!(await this.repo.findVendor(vendorId))) {
      throw apiError(400, 'INVALID_REFERENCE', 'Vendor not found', { field: 'vendorId' });
    }
    const location = await this.repo.findLocationsByIds(outletId, [locationId]);
    if (location.length === 0) throw apiError(400, 'INVALID_REFERENCE', 'Location not found', { field: 'locationId' });
    const ids = [...new Set(lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(ids);
    if (items.length !== ids.length) throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found');
  }

  private total(lines: ParsedPoLine[]): Prisma.Decimal {
    return lines.reduce((acc, l) => acc.plus(lineTotal(l.qty, l.rate)), ZERO);
  }

  private lineRows(poId: string, lines: ParsedPoLine[]): Prisma.PurchaseOrderLineUncheckedCreateInput[] {
    return lines.map((l, index) => ({
      poId,
      stockItemId: l.stockItemId,
      qty: l.qty,
      rate: l.rate,
      total: lineTotal(l.qty, l.rate),
      receivedQty: ZERO,
      sortOrder: index,
    }));
  }

  private headerData(dto: PurchaseOrderDto, lines: ParsedPoLine[]) {
    return {
      vendorId: dto.vendorId,
      locationId: dto.locationId,
      dueDate: dateInput(dto.dueDate ?? null, 'dueDate'),
      transportPermitNo: dto.transportPermitNo ?? null,
      total: this.total(lines),
      note: dto.note ?? null,
    };
  }

  private async notifyApprovers(tx: Tx, auth: AuthUser, po: PurchaseOrder, title: string): Promise<void> {
    await this.repo.createNotification(tx, {
      tenantId: auth.tenantId,
      outletId: auth.outletId,
      userId: null,
      permissionKey: 'stock.purchaseOrders',
      type: 'stock',
      title,
      body: `${inr(po.total)} total`,
      data: { purchaseOrderId: po.id },
    });
  }
}
