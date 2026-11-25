import { Injectable } from '@nestjs/common';
import { Prisma, StockCount } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { RealtimeService } from '../realtime/realtime.service';
import { MovementInput, StockLedgerService } from '../stock-core/stock-ledger.service';
import { decimalInput } from './decimal-input';
import { CountLineDto, CountLinesDto, CountsQueryDto } from './dto/inventory.dto';
import { InventoryRepository } from './inventory.repository';
import { countAdjustment, countDifference } from './inventory-math';
import { ZERO, indexLevels, money2, qty3, qtyDisplay, userName, ymd } from './inventory-views';
import { ledgerContext, publishLedgerEvents } from './ledger-context';

/** Stock counts (PLAN.md 1.7): OPEN, then SUBMITTED (expected snapshot), then POSTED (COUNT_ADJUST movements). */
@Injectable()
export class CountsService {
  constructor(
    private repo: InventoryRepository,
    private ledger: StockLedgerService,
    private realtime: RealtimeService,
  ) {}

  async list(q: CountsQueryDto, auth: AuthUser) {
    const counts = await this.repo.findCounts(auth.outletId, {
      ...(q.status ? { status: q.status } : {}),
      ...(q.locationId ? { locationId: q.locationId } : {}),
    });
    return this.summaries(auth.outletId, counts);
  }

  async get(id: string, auth: AuthUser) {
    const count = await this.load(auth.outletId, id);
    return this.fullView(auth.outletId, count);
  }

  async start(locationId: string, auth: AuthUser) {
    const location = await this.repo.findLocation(auth.outletId, locationId);
    if (!location) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    const tz = await this.repo.outletTimezone(auth.outletId);
    const businessDate = toDateOnly(businessDateFor(new Date(), tz, '05:00'));

    const count = await this.repo.transaction(async (tx) => {
      const live = await this.repo.findLiveCount(auth.outletId, location.id);
      if (live) {
        throw apiError(409, 'COUNT_ALREADY_OPEN', 'A count is already open for this location', { countId: live.id });
      }
      const levels = await this.repo.levelsForLocations([location.id]);
      const items = await this.repo.findItemsByIds([...new Set(levels.map((l) => l.stockItemId))]);
      const activeIds = items.filter((i) => i.isActive).map((i) => i.id);
      const created = await this.repo.createCount(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        locationId: location.id,
        status: 'OPEN',
        businessDate,
        startedById: auth.userId,
      });
      if (activeIds.length > 0) {
        await this.repo.createCountLines(
          tx,
          activeIds.map((stockItemId) => ({ countId: created.id, stockItemId })),
        );
      }
      return created;
    });
    return this.fullView(auth.outletId, count);
  }

  /** Idempotent upsert of counted lines. Offline replays send the same body (PLAN.md 1.7). */
  async saveLines(id: string, dto: CountLinesDto, auth: AuthUser) {
    const count = await this.load(auth.outletId, id);
    if (count.status !== 'OPEN') throw apiError(409, 'COUNT_NOT_OPEN', 'This count is no longer open');

    const itemIds = [...new Set(dto.lines.map((l) => l.stockItemId))];
    const items = await this.repo.findItemsByIds(itemIds);
    if (items.length !== itemIds.length) throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found');

    const now = new Date();
    const rows = dto.lines.map((l) => ({ stockItemId: l.stockItemId, data: this.lineData(l, auth, now) }));
    await this.repo.transaction(async (tx) => {
      for (const row of rows) await this.repo.upsertCountLine(tx, id, row.stockItemId, row.data);
    });
    return this.fullView(auth.outletId, await this.load(auth.outletId, id));
  }

  async submit(id: string, auth: AuthUser) {
    const count = await this.load(auth.outletId, id);
    if (count.status !== 'OPEN') throw apiError(409, 'COUNT_NOT_OPEN', 'This count is no longer open');
    const lines = await this.repo.countLines([id]);
    if (!lines.some((l) => l.countedQty !== null)) {
      throw apiError(400, 'NOTHING_COUNTED', 'Count at least one item before submitting');
    }
    const levels = indexLevels(await this.repo.levelsForLocations([count.locationId]));
    await this.repo.transaction(async (tx) => {
      for (const line of lines) {
        const expected = levels.get(line.stockItemId)?.get(count.locationId)?.onHand ?? ZERO;
        await this.repo.setCountLineExpected(tx, id, line.stockItemId, expected);
      }
      await this.repo.updateCount(tx, id, { status: 'SUBMITTED', submittedAt: new Date() });
    });
    return this.fullView(auth.outletId, await this.load(auth.outletId, id));
  }

  /** Posts COUNT_ADJUST = counted − expected at submit, for counted lines only (PLAN.md 1.7). */
  async post(id: string, auth: AuthUser) {
    const count = await this.load(auth.outletId, id);
    if (count.status !== 'SUBMITTED') throw apiError(409, 'COUNT_NOT_SUBMITTED', 'Submit the count before posting it');
    const lines = await this.repo.countLines([id]);
    const levels = indexLevels(await this.repo.levelsForLocations([count.locationId]));
    const ctx = ledgerContext(auth);

    await this.repo.transaction(async (tx) => {
      if ((await this.repo.claimSubmittedCount(tx, id)) === 0) {
        throw apiError(409, 'COUNT_NOT_SUBMITTED', 'Submit the count before posting it');
      }
      const inputs: MovementInput[] = [];
      for (const line of lines) {
        if (line.countedQty === null) continue;
        const expected = line.expectedQty ?? levels.get(line.stockItemId)?.get(count.locationId)?.onHand ?? ZERO;
        const adjust = countAdjustment(expected, line.countedQty);
        if (adjust.isZero()) continue;
        inputs.push({
          locationId: count.locationId,
          stockItemId: line.stockItemId,
          type: 'COUNT_ADJUST',
          qty: adjust,
          refType: 'COUNT',
          refId: id,
          note: 'Stock count',
        });
      }
      if (inputs.length > 0) await this.ledger.post(tx, ctx, inputs);
      await this.repo.updateCount(tx, id, { status: 'POSTED', postedAt: new Date(), postedById: auth.userId });
    });
    publishLedgerEvents(this.realtime, ctx.events);
    return this.fullView(auth.outletId, await this.load(auth.outletId, id));
  }

  async cancel(id: string, auth: AuthUser) {
    const count = await this.load(auth.outletId, id);
    if (count.status === 'POSTED') throw apiError(409, 'COUNT_POSTED', 'A posted count cannot be cancelled');
    if (count.status !== 'CANCELLED') {
      await this.repo.transaction(async (tx) => this.repo.updateCount(tx, id, { status: 'CANCELLED' }));
    }
    return this.fullView(auth.outletId, await this.load(auth.outletId, id));
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  private async load(outletId: string, id: string): Promise<StockCount> {
    const count = await this.repo.findCount(outletId, id);
    if (!count) throw apiError(404, 'COUNT_NOT_FOUND', 'Count not found');
    return count;
  }

  /** Only the keys the client sent change; a missing key keeps the stored value. */
  private lineData(l: CountLineDto, auth: AuthUser, now: Date) {
    const data: {
      countedQty?: Prisma.Decimal | null;
      note?: string | null;
      confirmedOutlier?: boolean;
      countedAt?: Date | null;
      countedById?: string | null;
    } = {};
    if (l.countedQty !== undefined) {
      data.countedQty =
        l.countedQty === null ? null : (decimalInput(l.countedQty, 'countedQty', { dp: 3, min: 0 }) as Prisma.Decimal);
      data.countedById = auth.userId;
      data.countedAt = l.countedAt ? parseInstant(l.countedAt) : now;
    }
    if (l.note !== undefined) data.note = l.note ?? null;
    if (l.confirmedOutlier !== undefined) data.confirmedOutlier = l.confirmedOutlier;
    return data;
  }

  private async summaries(outletId: string, counts: StockCount[]) {
    if (counts.length === 0) return [];
    const lines = await this.repo.countLines(counts.map((c) => c.id));
    const locations = await this.repo.findLocationsByIds(outletId, [...new Set(counts.map((c) => c.locationId))]);
    const users = await this.repo.findUsers([...new Set(counts.map((c) => c.startedById))]);
    const locationById = new Map(locations.map((l) => [l.id, l.name]));
    const userById = new Map(users.map((u) => [u.id, userName(u)]));
    return counts.map((c) => {
      const own = lines.filter((l) => l.countId === c.id);
      return {
        id: c.id,
        location: { id: c.locationId, name: locationById.get(c.locationId) ?? null },
        status: c.status,
        businessDate: ymd(c.businessDate),
        startedBy: { id: c.startedById, name: userById.get(c.startedById) ?? null },
        countedLines: own.filter((l) => l.countedQty !== null).length,
        totalLines: own.length,
        submittedAt: c.submittedAt ? c.submittedAt.toISOString() : null,
        postedAt: c.postedAt ? c.postedAt.toISOString() : null,
      };
    });
  }

  private async fullView(outletId: string, count: StockCount) {
    const [summary] = await this.summaries(outletId, [count]);
    const lines = await this.repo.countLines([count.id]);
    const items = await this.repo.findItemsByIds([...new Set(lines.map((l) => l.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    const levels = indexLevels(await this.repo.levelsForLocations([count.locationId]));

    let varianceValue: string | null = null;
    if (count.status === 'POSTED') {
      const adjustments = await this.repo.countAdjustmentsOf(count.id);
      varianceValue = money2(adjustments.reduce((acc, a) => acc.plus(a.qty.mul(a.unitCost)), ZERO));
    }

    const views = lines
      .map((line) => {
        const item = itemById.get(line.stockItemId);
        if (!item) return null;
        const live = levels.get(line.stockItemId)?.get(count.locationId)?.onHand ?? ZERO;
        const expected = line.expectedQty ?? (count.status === 'OPEN' ? live : null);
        const counted = line.countedQty;
        const diff = countDifference(expected, counted);
        return {
          stockItemId: line.stockItemId,
          name: item.name,
          baseUnit: item.baseUnit,
          packSize: qty3(item.packSize),
          packName: item.packName,
          countedQty: counted === null ? null : qty3(counted),
          countedDisplay: counted === null ? null : qtyDisplay(counted, item),
          expectedQty: expected === null ? null : qty3(expected),
          expectedDisplay: expected === null ? null : qtyDisplay(expected, item),
          differencePercent: diff.differencePercent,
          outlier: diff.outlier,
          confirmedOutlier: line.confirmedOutlier,
          note: line.note,
          countedAt: line.countedAt ? line.countedAt.toISOString() : null,
        };
      })
      .filter((v): v is NonNullable<typeof v> => v !== null)
      .sort((a, b) => a.name.localeCompare(b.name));

    return { ...summary, lines: views, varianceValue };
  }
}

/** ISO instant from the client (offline replays keep the time the count was taken). */
function parseInstant(value: string): Date {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) throw apiError(400, 'VALIDATION_FAILED', 'countedAt must be an ISO date', { field: 'countedAt' });
  return d;
}
