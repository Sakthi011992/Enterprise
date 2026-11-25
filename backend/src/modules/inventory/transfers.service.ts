import { Injectable } from '@nestjs/common';
import { Prisma, StockTransfer } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { dayWindow } from '../orders/business-day-window';
import { DocumentNumberRepository } from '../stock-core/document-number.repository';
import { nextDocNumber } from '../stock-core/stock-math';
import { MovementInput, StockLedgerService } from '../stock-core/stock-ledger.service';
import { RealtimeService } from '../realtime/realtime.service';
import { decimalInput, dateInput } from './decimal-input';
import { DateRangeQueryDto, TransferDto } from './dto/inventory.dto';
import { InventoryRepository } from './inventory.repository';
import { money2, qty3, qtyDisplay, userName, cost6 } from './inventory-views';
import { ledgerContext, publishLedgerEvents } from './ledger-context';
import { businessDateFor } from '../../common/pricing/business-date';

/** Stock transfers between two locations of the outlet (PLAN.md 1.7). Each line is a TRANSFER_OUT and a TRANSFER_IN. */
@Injectable()
export class TransfersService {
  constructor(
    private repo: InventoryRepository,
    private docs: DocumentNumberRepository,
    private ledger: StockLedgerService,
    private realtime: RealtimeService,
  ) {}

  /** createdAt filter in outlet business days, inclusive. */
  async list(q: DateRangeQueryDto, auth: AuthUser) {
    const tz = await this.repo.outletTimezone(auth.outletId);
    const now = new Date();
    const to = dateInput(q.to, 'to') ? q.to! : businessDateFor(now, tz, '05:00');
    const from = dateInput(q.from, 'from') ? q.from! : to;
    const createdAt = { gte: dayWindow(from, tz).start, lte: dayWindow(to, tz).end };
    const transfers = await this.repo.findTransfers(auth.outletId, createdAt);
    return this.views(auth.outletId, transfers);
  }

  async create(dto: TransferDto, auth: AuthUser) {
    if (dto.fromLocationId === dto.toLocationId) {
      throw apiError(400, 'SAME_LOCATION', 'Choose two different locations');
    }
    if (!dto.lines || dto.lines.length === 0) throw apiError(400, 'EMPTY_TRANSFER', 'Add at least one item');

    const lines = dto.lines.map((l) => ({
      stockItemId: l.stockItemId,
      qty: decimalInput(l.qty, 'qty', { dp: 3, min: 0.001 }) as Prisma.Decimal,
    }));

    const locations = await this.repo.findLocationsByIds(auth.outletId, [dto.fromLocationId, dto.toLocationId]);
    if (locations.length !== 2) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');

    const itemIds = [...new Set(lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(itemIds);
    if (items.length !== itemIds.length) throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found');

    const ctx = ledgerContext(auth);
    const transferId = await this.repo.transaction(async (tx) => {
      const n = await this.docs.next(tx, auth.tenantId, 'TR');
      const transfer = await this.repo.createTransfer(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        number: nextDocNumber('TR', n),
        fromLocationId: dto.fromLocationId,
        toLocationId: dto.toLocationId,
        note: dto.note ?? null,
        createdById: auth.userId,
      });
      await this.repo.createTransferLines(
        tx,
        lines.map((l) => ({ transferId: transfer.id, stockItemId: l.stockItemId, qty: l.qty })),
      );
      const inputs: MovementInput[] = lines.flatMap((l) => [
        {
          locationId: dto.fromLocationId,
          stockItemId: l.stockItemId,
          type: 'TRANSFER_OUT' as const,
          qty: l.qty.neg(),
          refType: 'TRANSFER',
          refId: transfer.id,
        },
        {
          locationId: dto.toLocationId,
          stockItemId: l.stockItemId,
          type: 'TRANSFER_IN' as const,
          qty: l.qty,
          refType: 'TRANSFER',
          refId: transfer.id,
        },
      ]);
      await this.ledger.post(tx, ctx, inputs);
      return transfer.id;
    });
    publishLedgerEvents(this.realtime, ctx.events);

    const saved = await this.repo.findTransfer(auth.outletId, transferId);
    if (!saved) throw apiError(404, 'TRANSFER_NOT_FOUND', 'Transfer not found');
    const [view] = await this.views(auth.outletId, [saved]);
    return view;
  }

  async views(outletId: string, transfers: StockTransfer[]) {
    if (transfers.length === 0) return [];
    const lines = await this.repo.transferLines(transfers.map((t) => t.id));
    const locationIds = [...new Set(transfers.flatMap((t) => [t.fromLocationId, t.toLocationId]))];
    const locations = await this.repo.findLocationsByIds(outletId, locationIds);
    const itemIds = [...new Set(lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(itemIds);
    const users = await this.repo.findUsers([...new Set(transfers.map((t) => t.createdById))]);
    const locationName = new Map(locations.map((l) => [l.id, l.name]));
    const itemById = new Map(items.map((i) => [i.id, i]));
    const userById = new Map(users.map((u) => [u.id, userName(u)]));

    return transfers.map((t) => ({
      id: t.id,
      number: t.number,
      fromLocation: { id: t.fromLocationId, name: locationName.get(t.fromLocationId) ?? null },
      toLocation: { id: t.toLocationId, name: locationName.get(t.toLocationId) ?? null },
      note: t.note,
      createdAt: t.createdAt.toISOString(),
      createdBy: { id: t.createdById, name: userById.get(t.createdById) ?? null },
      lines: lines
        .filter((l) => l.transferId === t.id)
        .map((l) => {
          const item = itemById.get(l.stockItemId);
          if (!item) return null;
          return {
            stockItemId: l.stockItemId,
            name: item.name,
            baseUnit: item.baseUnit,
            unitCost: cost6(item.avgCost),
            qty: qty3(l.qty),
            qtyDisplay: qtyDisplay(l.qty, item),
            value: money2(l.qty.mul(item.avgCost)),
          };
        })
        .filter((l): l is NonNullable<typeof l> => l !== null),
    }));
  }
}
