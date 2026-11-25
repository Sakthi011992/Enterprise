import { Injectable } from '@nestjs/common';
import { Prisma, WastageEntry } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { addDays } from '../orders/business-day-window';
import { RealtimeService } from '../realtime/realtime.service';
import { StockLedgerService } from '../stock-core/stock-ledger.service';
import { decimalInput, dateInput } from './decimal-input';
import { ALL_WASTAGE_REASONS, WastageDto, WastageQueryDto } from './dto/inventory.dto';
import { InventoryRepository } from './inventory.repository';
import { WASTAGE_PHOTO_THRESHOLD, wastageValue } from './inventory-math';
import { money2, qty3, qtyDisplay, userName, ymd, inr, ZERO } from './inventory-views';
import { ledgerContext, publishLedgerEvents } from './ledger-context';

/** Wastage log (PLAN.md 1.7). Each entry is a WASTAGE movement and a WastageEntry in the same transaction. */
@Injectable()
export class WastageService {
  constructor(
    private repo: InventoryRepository,
    private ledger: StockLedgerService,
    private realtime: RealtimeService,
  ) {}

  async list(q: WastageQueryDto, auth: AuthUser) {
    const tz = await this.repo.outletTimezone(auth.outletId);
    const to = dateInput(q.to, 'to') ? (q.to as string) : businessDateFor(new Date(), tz, '05:00');
    const from = dateInput(q.from, 'from') ? (q.from as string) : addDays(to, -6);
    const entries = await this.repo.findWastage(auth.outletId, {
      businessDate: { gte: toDateOnly(from), lte: toDateOnly(to) },
      ...(q.locationId ? { locationId: q.locationId } : {}),
    });
    const views = await this.views(auth.outletId, entries);
    const totalValue = entries.reduce((acc, e) => acc.plus(e.value), ZERO);
    return { items: views, totalValue: money2(totalValue) };
  }

  async create(dto: WastageDto, auth: AuthUser) {
    if (!ALL_WASTAGE_REASONS.includes(dto.reason) || dto.reason === 'VOID' || dto.reason === 'DAMAGED_DELIVERY') {
      throw apiError(400, 'INVALID_REASON', 'This reason is recorded by the system, not logged by hand');
    }
    const qty = decimalInput(dto.qty, 'qty', { dp: 3, min: 0.001 }) as Prisma.Decimal;
    const location = await this.repo.findLocation(auth.outletId, dto.locationId);
    if (!location) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    const item = await this.repo.findItem(dto.stockItemId);
    if (!item) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');

    const value = wastageValue(qty, item.avgCost);
    if (value.gt(WASTAGE_PHOTO_THRESHOLD) && !dto.photoUrl) {
      throw apiError(400, 'PHOTO_REQUIRED', 'Add a photo for wastage above ₹2,000', { value: money2(value) });
    }

    const tz = await this.repo.outletTimezone(auth.outletId);
    const businessDate = toDateOnly(businessDateFor(new Date(), tz, '05:00'));
    const ctx = ledgerContext(auth);
    const entry = await this.repo.transaction(async (tx) => {
      const onHand = await this.ledger.onHand(tx, location.id, item.id);
      if (qty.gt(onHand)) {
        throw apiError(409, 'INSUFFICIENT_STOCK', `Only ${qtyDisplay(onHand, item)} in ${location.name} stock`, {
          onHand: qty3(onHand),
          onHandDisplay: qtyDisplay(onHand, item),
        });
      }
      const created = await this.repo.createWastage(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        locationId: location.id,
        stockItemId: item.id,
        qty,
        value,
        reason: dto.reason,
        note: dto.note ?? null,
        photoUrl: dto.photoUrl ?? null,
        refType: null,
        refId: null,
        businessDate,
        createdById: auth.userId,
      });
      await this.ledger.post(tx, ctx, [
        {
          locationId: location.id,
          stockItemId: item.id,
          type: 'WASTAGE',
          qty: qty.neg(),
          refType: 'WASTAGE',
          refId: created.id,
          note: dto.reason,
        },
      ]);
      if (value.gt(WASTAGE_PHOTO_THRESHOLD)) {
        await this.repo.createNotification(tx, {
          tenantId: auth.tenantId,
          outletId: auth.outletId,
          userId: null,
          permissionKey: 'stock.purchaseOrders',
          type: 'stock',
          title: `Wastage of ${inr(value)} logged: ${item.name}`,
          body: `${location.name}, ${dto.reason.toLowerCase().replace('_', ' ')}`,
          data: { wastageId: created.id },
        });
      }
      return created;
    });
    publishLedgerEvents(this.realtime, ctx.events);

    const [view] = await this.views(auth.outletId, [entry]);
    return view;
  }

  private async views(outletId: string, entries: WastageEntry[]) {
    if (entries.length === 0) return [];
    const locations = await this.repo.findLocationsByIds(outletId, [...new Set(entries.map((e) => e.locationId))]);
    const items = await this.repo.findItemsByIds([...new Set(entries.map((e) => e.stockItemId))]);
    const users = await this.repo.findUsers([...new Set(entries.map((e) => e.createdById))]);
    const locationById = new Map(locations.map((l) => [l.id, l.name]));
    const itemById = new Map(items.map((i) => [i.id, i]));
    const userById = new Map(users.map((u) => [u.id, userName(u)]));
    return entries.map((e) => {
      const item = itemById.get(e.stockItemId);
      return {
        id: e.id,
        location: { id: e.locationId, name: locationById.get(e.locationId) ?? null },
        stockItem: { id: e.stockItemId, name: item?.name ?? null },
        qty: qty3(e.qty),
        qtyDisplay: item ? qtyDisplay(e.qty, item) : qty3(e.qty),
        value: money2(e.value),
        reason: e.reason,
        note: e.note,
        photoUrl: e.photoUrl,
        businessDate: ymd(e.businessDate),
        createdAt: e.createdAt.toISOString(),
        createdBy: { id: e.createdById, name: userById.get(e.createdById) ?? null },
      };
    });
  }
}
