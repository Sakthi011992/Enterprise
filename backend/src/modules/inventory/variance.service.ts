import { Injectable } from '@nestjs/common';
import { Prisma, StockItem } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { dayWindow, addDays } from '../orders/business-day-window';
import { PermissionsService } from '../personas/permissions.service';
import { varianceRow, VarianceMath } from '../stock-core/stock-math';
import { PermissionRequirement, requireAnyPermission } from './access';
import { dateInput } from './decimal-input';
import { VarianceQueryDto } from './dto/inventory.dto';
import { InventoryRepository } from './inventory.repository';
import { HALF_UP, ZERO, cost6, indexLevels, money2, qty3, qtyDisplay } from './inventory-views';

/** Variance and inventory summary reads (PLAN.md 1.3, 1.6 and 1.7). */
const VIEW_PERMISSIONS: PermissionRequirement[] = [
  ['stock.count', 'VIEW'],
  ['reports.view', 'LIMITED'],
];

@Injectable()
export class VarianceService {
  constructor(
    private repo: InventoryRepository,
    private permissions: PermissionsService,
  ) {}

  /** GET /stock/variance. Default window: the last seven business days, liquor only. */
  async variance(q: VarianceQueryDto, auth: AuthUser) {
    requireAnyPermission(this.permissions, auth, VIEW_PERMISSIONS);
    const window = await this.window(auth.outletId, q.from, q.to);
    const result = await this.compute(auth.outletId, window.from, window.to, q.locationId ?? null, q.liquor !== 'false');
    return {
      from: window.from,
      to: window.to,
      rows: result.rows.map((r) => varianceView(r.item, r.math)),
      totals: { varianceValue: money2(result.total) },
    };
  }

  /** GET /inventory/summary: stock value, 7-day pour cost, 7-day liquor variance, items below par. */
  async summary(auth: AuthUser) {
    requireAnyPermission(this.permissions, auth, VIEW_PERMISSIONS);
    const tz = await this.repo.outletTimezone(auth.outletId);
    const today = businessDateFor(new Date(), tz, '05:00');
    const from = addDays(today, -6);

    const locations = await this.repo.listLocations(auth.outletId);
    const levels = await this.repo.levelsForLocations(locations.map((l) => l.id));
    const items = await this.repo.findItems({ isActive: true });
    const itemById = new Map(items.map((i) => [i.id, i]));

    let stockValue = ZERO;
    let belowParCount = 0;
    for (const lv of levels) {
      const item = itemById.get(lv.stockItemId);
      if (!item) continue;
      stockValue = stockValue.plus(lv.onHand.mul(item.avgCost));
      if (lv.parLevel.gt(0) && lv.onHand.lt(lv.parLevel)) belowParCount += 1;
    }

    const liquor = await this.compute(auth.outletId, from, today, null, true);
    const liquorQty = liquor.rows.reduce((acc, r) => acc.plus(r.math.variance), ZERO);

    const liquorIds = items.filter((i) => i.isLiquor).map((i) => i.id);
    const sales = liquorIds.length
      ? await this.repo.saleMovements(auth.outletId, toDateOnly(from), toDateOnly(today), liquorIds)
      : [];
    // Sales are negative, so the cost of what was sold is the negated quantity times the unit cost.
    const cost = sales.reduce((acc, s) => acc.plus(s.qty.neg().mul(s.unitCost)), ZERO);
    const productIds = liquorIds.length ? await this.repo.productIdsUsingItems(liquorIds) : [];
    const start = dayWindow(from, tz).start;
    const end = dayWindow(today, tz).end;
    const orderIds = (await this.repo.orderIdsBetween(auth.outletId, start, end)).map((o) => o.id);
    const orderItems = orderIds.length && productIds.length ? await this.repo.orderItemsFor(orderIds, productIds) : [];
    const revenue = orderItems.reduce((acc, oi) => acc.plus(oi.lineTotal.minus(oi.taxAmount)), ZERO);
    const percent = revenue.isZero()
      ? '0.0'
      : cost.div(revenue).mul(100).toDecimalPlaces(1, HALF_UP).toFixed(1);

    return {
      stockValue: money2(stockValue),
      pourCost7d: { percent, cost: money2(cost), revenue: money2(revenue) },
      liquorVariance7d: { qty: qty3(liquorQty), value: money2(liquor.total) },
      belowParCount,
    };
  }

  /** GET /stock/kegs: keg items, full kegs in the outlet and the keg on tap at the Bar (remainder in the bar stock). */
  async kegs(auth: AuthUser) {
    const locations = await this.repo.listLocations(auth.outletId);
    const levels = indexLevels(await this.repo.levelsForLocations(locations.map((l) => l.id)));
    const kegs = await this.repo.findItems({ isActive: true, isKeg: true });
    return kegs.map((item) => {
      const cells = levels.get(item.id);
      let total = ZERO;
      let onBar = ZERO;
      const breakdown: { locationId: string; name: string; qty: string; qtyDisplay: string }[] = [];
      for (const loc of locations) {
        const cell = cells?.get(loc.id);
        if (!cell) continue;
        total = total.plus(cell.onHand);
        if (loc.kind === 'BAR') onBar = onBar.plus(cell.onHand);
        breakdown.push({
          locationId: loc.id,
          name: loc.name,
          qty: qty3(cell.onHand),
          qtyDisplay: qtyDisplay(cell.onHand, item),
        });
      }
      const fullKegs = item.packSize.gt(0)
        ? total.div(item.packSize).toDecimalPlaces(0, 3 /* ROUND_FLOOR */).toNumber()
        : 0;
      const onTap = item.packSize.gt(0) ? onBar.mod(item.packSize) : ZERO;
      return {
        stockItemId: item.id,
        name: item.name,
        fullKegs,
        onTapMl: qty3(onTap),
        onTapDisplay: qtyDisplay(onTap, item),
        locationBreakdown: breakdown,
      };
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  private async window(outletId: string, from?: string, to?: string): Promise<{ from: string; to: string }> {
    const tz = await this.repo.outletTimezone(outletId);
    const end = dateInput(to, 'to') ? (to as string) : businessDateFor(new Date(), tz, '05:00');
    const start = dateInput(from, 'from') ? (from as string) : addDays(end, -6);
    return { from: start, to: end };
  }

  /** The variance formula of PLAN.md 1.3 for every matching item, in business dates `from..to`. */
  private async compute(
    outletId: string,
    from: string,
    to: string,
    locationId: string | null,
    liquorOnly: boolean,
  ): Promise<{ rows: { item: StockItem; math: VarianceMath }[]; total: Prisma.Decimal }> {
    if (locationId) {
      const location = await this.repo.findLocation(outletId, locationId);
      if (!location) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    }
    const items = await this.repo.findItems({ isActive: true, ...(liquorOnly ? { isLiquor: true } : {}) });
    const ids = items.map((i) => i.id);
    const movements = ids.length
      ? await this.repo.movementsWhere({
          outletId,
          stockItemId: { in: ids },
          businessDate: { gte: toDateOnly(from), lte: toDateOnly(to) },
          ...(locationId ? { locationId } : {}),
        })
      : [];
    const opening = await this.repo.openingSums(outletId, toDateOnly(from), locationId, ids);
    const openingById = new Map(opening.map((o) => [o.stockItemId, o._sum.qty ?? ZERO]));

    const byItem = new Map<string, typeof movements>();
    for (const m of movements) {
      const list = byItem.get(m.stockItemId) ?? [];
      list.push(m);
      byItem.set(m.stockItemId, list);
    }

    const rows = items.map((item) => ({
      item,
      math: varianceRow(byItem.get(item.id) ?? [], openingById.get(item.id) ?? ZERO),
    }));
    const total = rows.reduce((acc, r) => acc.plus(r.math.varianceValue), ZERO);
    return { rows, total };
  }
}

function varianceView(item: StockItem, m: VarianceMath) {
  return {
    stockItemId: item.id,
    name: item.name,
    baseUnit: item.baseUnit,
    unitCost: cost6(item.avgCost),
    opening: qty3(m.opening),
    openingDisplay: qtyDisplay(m.opening, item),
    received: qty3(m.received),
    receivedDisplay: qtyDisplay(m.received, item),
    transfersIn: qty3(m.transfersIn),
    transfersInDisplay: qtyDisplay(m.transfersIn, item),
    transfersOut: qty3(m.transfersOut),
    transfersOutDisplay: qtyDisplay(m.transfersOut, item),
    sold: qty3(m.sold),
    soldDisplay: qtyDisplay(m.sold, item),
    wastage: qty3(m.wastage),
    wastageDisplay: qtyDisplay(m.wastage, item),
    expected: qty3(m.expected),
    expectedDisplay: qtyDisplay(m.expected, item),
    counted: m.counted === null ? null : qty3(m.counted),
    countedDisplay: m.counted === null ? null : qtyDisplay(m.counted, item),
    variance: qty3(m.variance),
    varianceDisplay: qtyDisplay(m.variance, item),
    varianceValue: money2(m.varianceValue),
  };
}
