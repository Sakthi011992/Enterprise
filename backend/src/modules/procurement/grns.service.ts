import { Injectable } from '@nestjs/common';
import { GoodsReceipt, GoodsReceiptLine, Prisma, PurchaseOrder, PurchaseOrderLine, StockItem } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { round2 } from '../../common/utils/money.util';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { RealtimeService } from '../realtime/realtime.service';
import { DocumentNumberRepository } from '../stock-core/document-number.repository';
import { MovementInput, StockLedgerService } from '../stock-core/stock-ledger.service';
import { nextDocNumber, toBase } from '../stock-core/stock-math';
import { dateInput, decimalInput } from '../inventory/decimal-input';
import { HALF_UP, ZERO, money2, qty3, qtyDisplay, ymd } from '../inventory/inventory-views';
import { ledgerContext, publishLedgerEvents } from '../inventory/ledger-context';
import { GrnCreateDto, GrnLineDto, GrnUpdateDto, GrnsQueryDto } from './dto/procurement.dto';
import {
  GrnCalcLine,
  calculateGrn,
  debitNoteReason,
  lineStatus,
  outstandingQty,
  purchaseOrderStatusAfterReceipt,
} from './procurement-math';
import { grnSummaryViews } from './procurement-views';
import { ProcurementRepository, RECEIVABLE_PO_STATUSES } from './procurement.repository';

export interface ParsedGrnLine {
  poLineId: string | null;
  stockItemId: string;
  orderedQty: Prisma.Decimal;
  invoicedQty: Prisma.Decimal;
  receivedQty: Prisma.Decimal;
  damagedQty: Prisma.Decimal;
  rate: Prisma.Decimal;
  batch: string | null;
  expiry: Date | null;
}

interface GrnHeader {
  vendorId: string;
  locationId: string;
  vendorInvoiceNo: string | null;
  invoiceDate: Date | null;
  receivedOn: Date;
  transportPermitNo: string | null;
  invoicePhotoUrl: string | null;
}

/** Goods receipts (GRN): drafts with live preview, and the post transaction of PLAN.md 1.7. */
@Injectable()
export class GrnsService {
  constructor(
    private repo: ProcurementRepository,
    private docs: DocumentNumberRepository,
    private ledger: StockLedgerService,
    private realtime: RealtimeService,
  ) {}

  async list(q: GrnsQueryDto, auth: AuthUser) {
    const from = dateInput(q.from ?? null, 'from');
    const to = dateInput(q.to ?? null, 'to');
    const grns = await this.repo.listGoodsReceipts(auth.outletId, {
      ...(q.vendorId ? { vendorId: q.vendorId } : {}),
      ...(from || to ? { receivedOn: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } } : {}),
    });
    return grnSummaryViews(this.repo, auth.outletId, grns);
  }

  async get(id: string, auth: AuthUser) {
    const grn = await this.load(auth.outletId, id);
    return this.fullView(auth.outletId, grn);
  }

  /** With a PO and no lines, the lines are the PO's outstanding quantities (PLAN.md 1.7). */
  async create(dto: GrnCreateDto, auth: AuthUser) {
    const po = dto.poId ? await this.loadReceivablePo(auth.outletId, dto.poId) : null;
    const poLines = po ? await this.repo.poLines([po.id]) : [];
    const vendorId = dto.vendorId ?? po?.vendorId;
    const locationId = dto.locationId ?? po?.locationId;
    if (!vendorId) throw apiError(400, 'VALIDATION_FAILED', 'Choose a vendor', { field: 'vendorId' });
    if (!locationId) throw apiError(400, 'VALIDATION_FAILED', 'Choose where the goods go', { field: 'locationId' });
    await this.validateRefs(auth.outletId, vendorId, locationId);

    const lines = dto.lines && dto.lines.length > 0
      ? await this.parseLines(dto.lines, poLines)
      : po
        ? this.prefillFromPo(poLines)
        : [];
    const invoiceInput = this.optionalMoney(dto.invoiceValue);
    const calc = await this.calc(lines, invoiceInput);
    const tz = await this.repo.outletTimezone(auth.outletId);
    const header: GrnHeader = {
      vendorId,
      locationId,
      vendorInvoiceNo: dto.vendorInvoiceNo ?? null,
      invoiceDate: dateInput(dto.invoiceDate ?? null, 'invoiceDate'),
      receivedOn: dateInput(dto.receivedOn ?? null, 'receivedOn') ?? toDateOnly(businessDateFor(new Date(), tz, '05:00')),
      transportPermitNo: dto.transportPermitNo ?? null,
      invoicePhotoUrl: dto.invoicePhotoUrl ?? null,
    };

    const grn = await this.repo.transaction(async (tx) => {
      const n = await this.docs.next(tx, auth.tenantId, 'GRN');
      const created = await this.repo.createGoodsReceipt(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        number: nextDocNumber('GRN', n),
        poId: po ? po.id : null,
        createdById: auth.userId,
        ...this.grnData(header, calc, po),
      });
      await this.repo.createGrnLines(tx, this.lineRows(created.id, lines));
      return created;
    });
    return this.fullView(auth.outletId, grn);
  }

  /** Replaces the header and, when given, the lines. Without lines the stored lines are kept. */
  async update(id: string, dto: GrnUpdateDto, auth: AuthUser) {
    const grn = await this.load(auth.outletId, id);
    if (grn.status === 'POSTED') throw apiError(409, 'GRN_POSTED', 'A posted receipt cannot be changed');
    const poLines = grn.poId ? await this.repo.poLines([grn.poId]) : [];
    const lines = dto.lines !== undefined
      ? await this.parseLines(dto.lines, poLines)
      : (await this.repo.grnLines([id])).map((l) => this.fromRow(l));
    const vendorId = dto.vendorId ?? grn.vendorId;
    const locationId = dto.locationId ?? grn.locationId;
    if (dto.vendorId !== undefined || dto.locationId !== undefined) {
      await this.validateRefs(auth.outletId, vendorId, locationId);
    }
    const calc = await this.calc(lines, this.optionalMoney(dto.invoiceValue));
    const header: GrnHeader = {
      vendorId,
      locationId,
      vendorInvoiceNo: dto.vendorInvoiceNo !== undefined ? dto.vendorInvoiceNo ?? null : grn.vendorInvoiceNo,
      invoiceDate: dto.invoiceDate !== undefined ? dateInput(dto.invoiceDate, 'invoiceDate') : grn.invoiceDate,
      receivedOn: dto.receivedOn !== undefined ? (dateInput(dto.receivedOn, 'receivedOn') as Date) : grn.receivedOn,
      transportPermitNo: dto.transportPermitNo !== undefined ? dto.transportPermitNo ?? null : grn.transportPermitNo,
      invoicePhotoUrl: dto.invoicePhotoUrl !== undefined ? dto.invoicePhotoUrl ?? null : grn.invoicePhotoUrl,
    };
    await this.repo.transaction(async (tx) => {
      await this.repo.deleteGrnLines(tx, id);
      await this.repo.createGrnLines(tx, this.lineRows(id, lines));
      await this.repo.updateGoodsReceipt(tx, id, this.grnData(header, calc, null));
    });
    return this.get(id, auth);
  }

  /**
   * Posts the receipt in one transaction (PLAN.md 1.7 GRN post): RECEIPT per line at rate ÷ purchase unit qty,
   * WASTAGE for damaged goods, the debit note for invoiced but not received, PO quantities and status, GRN totals.
   */
  async post(id: string, auth: AuthUser) {
    const grn = await this.load(auth.outletId, id);
    if (grn.status === 'POSTED') throw apiError(409, 'GRN_POSTED', 'This receipt is already posted');
    const rows = await this.repo.grnLines([id]);
    const items = await this.repo.findItemsByIds([...new Set(rows.map((r) => r.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    const lines = rows.map((r) => this.fromRow(r));

    if (!grn.vendorInvoiceNo || grn.vendorInvoiceNo.trim() === '') {
      throw apiError(400, 'INVOICE_NO_REQUIRED', 'Enter the vendor invoice number before posting');
    }
    if (lines.some((l) => itemById.get(l.stockItemId)?.isLiquor) && !grn.transportPermitNo) {
      throw apiError(400, 'PERMIT_REQUIRED', 'Liquor needs a transport permit number before posting');
    }
    lines.forEach((l, index) => this.assertPostable(l, index));

    const po = grn.poId ? await this.repo.findPurchaseOrder(auth.outletId, grn.poId) : null;
    if (grn.poId && (!po || !RECEIVABLE_PO_STATUSES.includes(po.status))) {
      throw apiError(409, 'PO_NOT_RECEIVABLE', 'The purchase order cannot receive goods in its current state');
    }

    const calc = calculateGrn(this.calcLines(lines, itemById), grn.invoiceValue);
    const tz = await this.repo.outletTimezone(auth.outletId);
    const today = toDateOnly(businessDateFor(new Date(), tz, '05:00'));
    const ctx = ledgerContext(auth);

    await this.repo.transaction(async (tx) => {
      // Claim the draft first so two simultaneous posts can't both add the stock.
      if ((await this.repo.claimDraftGrn(tx, id)) === 0) {
        throw apiError(409, 'GRN_POSTED', 'This receipt is already posted');
      }
      // Step 1: receipts at the invoice rate per base unit, and the item's last purchase rate.
      const receipts: MovementInput[] = [];
      for (const line of lines) {
        if (!line.receivedQty.gt(0)) continue;
        const item = itemById.get(line.stockItemId)!;
        receipts.push({
          locationId: grn.locationId,
          stockItemId: line.stockItemId,
          type: 'RECEIPT',
          qty: toBase(line.receivedQty, item.purchaseUnitQty),
          unitCost: line.rate.div(item.purchaseUnitQty).toDecimalPlaces(6, HALF_UP),
          refType: 'GRN_LINE',
          refId: line.id,
        });
        await this.repo.updateItemRate(tx, line.stockItemId, line.rate);
      }
      await this.ledger.post(tx, ctx, receipts);

      // Step 2: damaged goods are received and written off the same moment.
      for (const line of lines) {
        if (!line.damagedQty.gt(0)) continue;
        const item = itemById.get(line.stockItemId)!;
        const qty = toBase(line.damagedQty, item.purchaseUnitQty);
        const entry = await this.repo.createWastage(tx, {
          tenantId: auth.tenantId,
          outletId: auth.outletId,
          locationId: grn.locationId,
          stockItemId: line.stockItemId,
          qty,
          value: round2(line.damagedQty.mul(line.rate)),
          reason: 'DAMAGED_DELIVERY',
          note: `GRN ${grn.number}`,
          photoUrl: null,
          refType: 'GRN_LINE',
          refId: line.id,
          businessDate: today,
          createdById: auth.userId,
        });
        await this.ledger.post(tx, ctx, [
          {
            locationId: grn.locationId,
            stockItemId: line.stockItemId,
            type: 'WASTAGE',
            qty: qty.neg(),
            refType: 'WASTAGE',
            refId: entry.id,
            note: 'DAMAGED_DELIVERY',
          },
        ]);
      }

      // Step 3: debit note for invoiced but not received.
      if (calc.debitNoteAmount.gt(0)) {
        const n = await this.docs.next(tx, auth.tenantId, 'DN');
        await this.repo.createDebitNote(tx, {
          tenantId: auth.tenantId,
          outletId: auth.outletId,
          number: nextDocNumber('DN', n),
          vendorId: grn.vendorId,
          grnId: grn.id,
          amount: calc.debitNoteAmount,
          reason: debitNoteReason(calc.shortLines),
          status: 'OPEN',
        });
      }

      // Step 4: purchase order quantities and status.
      if (grn.poId) {
        for (const line of lines) {
          if (line.poLineId) await this.repo.addPoLineReceived(tx, line.poLineId, line.receivedQty);
        }
        const poLines = await this.repo.poLinesIn(tx, grn.poId);
        const status = purchaseOrderStatusAfterReceipt(
          poLines.map((l) => ({ qty: l.qty, receivedQty: l.receivedQty })),
          calc.mismatch,
        );
        await this.repo.updatePurchaseOrder(tx, grn.poId, { status });
      }

      // Step 5: the receipt itself.
      await this.repo.updateGoodsReceipt(tx, id, {
        status: 'POSTED',
        receivedValue: calc.receivedValue,
        damagedValue: calc.damagedValue,
        debitNoteAmount: calc.debitNoteAmount,
        invoiceValue: calc.invoiceValue,
        payable: calc.payable,
        mismatch: calc.mismatch,
        postedById: auth.userId,
        postedAt: new Date(),
      });
    });
    publishLedgerEvents(this.realtime, ctx.events);
    return this.get(id, auth);
  }

  // ===========================================================================
  // Views
  // ===========================================================================

  private async fullView(outletId: string, grn: GoodsReceipt) {
    const [summary] = await grnSummaryViews(this.repo, outletId, [grn]);
    const rows = await this.repo.grnLines([grn.id]);
    const items = await this.repo.findItemsByIds([...new Set(rows.map((r) => r.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    const po = grn.poId ? await this.repo.findPurchaseOrder(outletId, grn.poId) : null;
    const lines = rows.map((r) => this.fromRow(r));
    const calcLines = this.calcLines(lines, itemById);
    const calc = calculateGrn(calcLines, grn.invoiceValue);

    const lineViews = rows
      .map((r, index) => {
        const item = itemById.get(r.stockItemId);
        if (!item) return null;
        return {
          id: r.id,
          poLineId: r.poLineId,
          stockItemId: r.stockItemId,
          name: item.name,
          purchaseUnitName: item.purchaseUnitName,
          orderedQty: qty3(r.orderedQty),
          invoicedQty: qty3(r.invoicedQty),
          receivedQty: qty3(r.receivedQty),
          damagedQty: qty3(r.damagedQty),
          rate: money2(r.rate),
          batch: r.batch,
          expiry: r.expiry ? ymd(r.expiry) : null,
          status: lineStatus(calcLines[index]),
        };
      })
      .filter((v): v is NonNullable<typeof v> => v !== null);

    const stockAdded = calc.stockAddedQty
      .map((net, index) => ({ net, index }))
      .filter(({ net }) => net.gt(0))
      .map(({ net, index }) => {
        const item = itemById.get(rows[index].stockItemId);
        return {
          name: item?.name ?? null,
          qty: qty3(net),
          purchaseUnitName: item?.purchaseUnitName ?? null,
          display: item ? qtyDisplay(calc.stockAddedBase[index], item) : qty3(calc.stockAddedBase[index]),
        };
      });

    return {
      ...summary,
      poId: grn.poId,
      vendorInvoiceNo: grn.vendorInvoiceNo,
      invoiceDate: grn.invoiceDate ? ymd(grn.invoiceDate) : null,
      transportPermitNo: grn.transportPermitNo,
      invoicePhotoUrl: grn.invoicePhotoUrl,
      poValue: money2(po ? po.total : grn.poValue),
      receivedValue: money2(grn.receivedValue),
      debitNoteAmount: money2(grn.debitNoteAmount),
      damagedValue: money2(grn.damagedValue),
      lines: lineViews,
      preview: {
        stockAdded,
        debitNote: calc.debitNoteAmount.gt(0)
          ? { amount: money2(calc.debitNoteAmount), reason: debitNoteReason(calc.shortLines) }
          : null,
        wastage: calc.damagedLines.map((d) => ({ name: d.name, qty: qty3(d.qty), value: money2(d.value) })),
        payable: money2(calc.payable),
      },
    };
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  private async load(outletId: string, id: string): Promise<GoodsReceipt> {
    const grn = await this.repo.findGoodsReceipt(outletId, id);
    if (!grn) throw apiError(404, 'GRN_NOT_FOUND', 'Goods receipt not found');
    return grn;
  }

  private async loadReceivablePo(outletId: string, poId: string): Promise<PurchaseOrder> {
    const po = await this.repo.findPurchaseOrder(outletId, poId);
    if (!po) throw apiError(404, 'PO_NOT_FOUND', 'Purchase order not found');
    if (!RECEIVABLE_PO_STATUSES.includes(po.status)) {
      throw apiError(409, 'PO_NOT_RECEIVABLE', 'The purchase order cannot receive goods in its current state', {
        status: po.status,
      });
    }
    return po;
  }

  private async validateRefs(outletId: string, vendorId: string, locationId: string): Promise<void> {
    if (!(await this.repo.findVendor(vendorId))) throw apiError(400, 'INVALID_REFERENCE', 'Vendor not found', { field: 'vendorId' });
    const locations = await this.repo.findLocationsByIds(outletId, [locationId]);
    if (locations.length === 0) throw apiError(400, 'INVALID_REFERENCE', 'Location not found', { field: 'locationId' });
  }

  private prefillFromPo(poLines: PurchaseOrderLine[]): ParsedGrnLine[] {
    return poLines
      .map((l) => ({ l, left: outstandingQty(l.qty, l.receivedQty) }))
      .filter(({ left }) => left.gt(0))
      .map(({ l, left }) => ({
        poLineId: l.id,
        stockItemId: l.stockItemId,
        orderedQty: left,
        invoicedQty: left,
        receivedQty: left,
        damagedQty: ZERO,
        rate: l.rate,
        batch: null,
        expiry: null,
      }));
  }

  private async parseLines(lines: GrnLineDto[], poLines: PurchaseOrderLine[]): Promise<ParsedGrnLine[]> {
    const poLineIds = new Set(poLines.map((l) => l.id));
    for (const l of lines) {
      if (l.poLineId && !poLineIds.has(l.poLineId)) {
        throw apiError(400, 'INVALID_REFERENCE', 'A PO line does not belong to this purchase order', { poLineId: l.poLineId });
      }
    }
    const ids = [...new Set(lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(ids);
    if (items.length !== ids.length) throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found');
    return lines.map((l) => ({
      poLineId: l.poLineId ?? null,
      stockItemId: l.stockItemId,
      orderedQty: decimalInput(l.orderedQty ?? 0, 'orderedQty', { dp: 3 }) as Prisma.Decimal,
      invoicedQty: decimalInput(l.invoicedQty ?? 0, 'invoicedQty', { dp: 3 }) as Prisma.Decimal,
      receivedQty: decimalInput(l.receivedQty ?? 0, 'receivedQty', { dp: 3 }) as Prisma.Decimal,
      damagedQty: decimalInput(l.damagedQty ?? 0, 'damagedQty', { dp: 3 }) as Prisma.Decimal,
      rate: decimalInput(l.rate, 'rate', { dp: 2 }) as Prisma.Decimal,
      batch: l.batch ?? null,
      expiry: dateInput(l.expiry ?? null, 'expiry'),
    }));
  }

  /** Posting rules: no negatives and no more damaged than received (PLAN.md 1.7, INVALID_QTY). */
  private assertPostable(l: ParsedGrnLine, index: number): void {
    const checks: [string, Prisma.Decimal][] = [
      ['orderedQty', l.orderedQty],
      ['invoicedQty', l.invoicedQty],
      ['receivedQty', l.receivedQty],
      ['damagedQty', l.damagedQty],
    ];
    for (const [field, value] of checks) {
      if (value.lt(0)) throw apiError(400, 'INVALID_QTY', 'Must be 0 or more', { line: index, field });
    }
    if (l.damagedQty.gt(l.receivedQty)) {
      throw apiError(400, 'INVALID_QTY', 'Damaged cannot be more than received', { line: index, field: 'damagedQty' });
    }
  }

  private optionalMoney(value: unknown): Prisma.Decimal | null {
    return decimalInput(value, 'invoiceValue', { dp: 2, min: 0, optional: true });
  }

  private async calc(lines: ParsedGrnLine[], invoiceInput: Prisma.Decimal | null) {
    const items = await this.repo.findItemsByIds([...new Set(lines.map((l) => l.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    return calculateGrn(this.calcLines(lines, itemById), invoiceInput);
  }

  private calcLines(lines: ParsedGrnLine[], itemById: Map<string, StockItem>): GrnCalcLine[] {
    return lines.map((l) => ({
      name: itemById.get(l.stockItemId)?.name ?? '',
      hasPoLine: l.poLineId !== null,
      orderedQty: l.orderedQty,
      invoicedQty: l.invoicedQty,
      receivedQty: l.receivedQty,
      damagedQty: l.damagedQty,
      rate: l.rate,
      purchaseUnitQty: itemById.get(l.stockItemId)?.purchaseUnitQty ?? new Prisma.Decimal(1),
    }));
  }

  private fromRow(r: GoodsReceiptLine): ParsedGrnLine {
    return {
      poLineId: r.poLineId,
      stockItemId: r.stockItemId,
      orderedQty: r.orderedQty,
      invoicedQty: r.invoicedQty,
      receivedQty: r.receivedQty,
      damagedQty: r.damagedQty,
      rate: r.rate,
      batch: r.batch,
      expiry: r.expiry,
    };
  }

  private lineRows(grnId: string, lines: ParsedGrnLine[]): Prisma.GoodsReceiptLineUncheckedCreateInput[] {
    return lines.map((l) => ({ grnId, ...l }));
  }

  /** Header and computed totals. `poValue` is only set when a PO is linked at creation. */
  private grnData(header: GrnHeader, calc: ReturnType<typeof calculateGrn>, po: PurchaseOrder | null) {
    return {
      vendorId: header.vendorId,
      locationId: header.locationId,
      vendorInvoiceNo: header.vendorInvoiceNo,
      invoiceDate: header.invoiceDate,
      receivedOn: header.receivedOn,
      transportPermitNo: header.transportPermitNo,
      invoicePhotoUrl: header.invoicePhotoUrl,
      ...(po ? { poValue: po.total } : {}),
      invoiceValue: calc.invoiceValue,
      receivedValue: calc.receivedValue,
      damagedValue: calc.damagedValue,
      debitNoteAmount: calc.debitNoteAmount,
      payable: calc.payable,
      mismatch: calc.mismatch,
    };
  }
}
