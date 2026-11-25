import { Injectable } from '@nestjs/common';
import { Prisma, StockItem, StockLocation } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { businessDateFor, toDateOnly } from '../../common/pricing/business-date';
import { addDays } from '../orders/business-day-window';
import { PermissionsService } from '../personas/permissions.service';
import { RealtimeService } from '../realtime/realtime.service';
import { MovementInput, StockLedgerService } from '../stock-core/stock-ledger.service';
import { PermissionRequirement, requireAnyPermission } from './access';
import { dateInput, decimalInput } from './decimal-input';
import { InventoryRepository } from './inventory.repository';
import { VARIANCE_FLAG_VALUE, statusFromFlags, StockRowStatus } from './inventory-math';
import {
  LevelCell,
  ZERO,
  cost6,
  indexLevels,
  money2,
  qty3,
  qtyDisplay,
  unitCostDisplay,
  userName,
  ymd,
} from './inventory-views';
import { ledgerContext, publishLedgerEvents } from './ledger-context';
import { LocationDto, ItemsQueryDto, MovementsQueryDto, ParDto, StockItemDto } from './dto/inventory.dto';

export interface StockItemRow {
  id: string;
  name: string;
  categoryName: string | null;
  baseUnit: StockItem['baseUnit'];
  packSize: string;
  packName: string;
  isLiquor: boolean;
  isKeg: boolean;
  onHand: string;
  onHandDisplay: string;
  parLevel: string;
  parDisplay: string;
  avgCost: string;
  unitCostDisplay: string;
  value: string;
  status: StockRowStatus;
  locationId: string | null;
}

interface RowFlags {
  variance: boolean;
  expiring: boolean;
}

interface StatusFlagSet extends RowFlags {
  negative: boolean;
  belowPar: boolean;
}

interface BuiltRow {
  row: StockItemRow;
  status: StockRowStatus;
  flags: StatusFlagSet;
}

const EDIT_PERMISSIONS: PermissionRequirement[] = [
  ['menu.edit', 'EDIT'],
  ['stock.purchaseOrders', 'EDIT'],
];

/** Status filters match any flag, not only the highest-priority status (PLAN.md 1.7). */
export function matchesStatus(flags: StatusFlagSet, status: string): boolean {
  switch (status) {
    case 'OK':
      return !flags.negative && !flags.belowPar && !flags.variance && !flags.expiring;
    case 'NEGATIVE':
      return flags.negative;
    case 'BELOW_PAR':
      return flags.belowPar;
    case 'VARIANCE':
      return flags.variance;
    case 'EXPIRES':
      return flags.expiring;
    default:
      return false;
  }
}

/** Locations, stock items, par levels and the item movement history (PLAN.md 1.7 Inventory). */
@Injectable()
export class StockItemsService {
  constructor(
    private repo: InventoryRepository,
    private permissions: PermissionsService,
    private ledger: StockLedgerService,
    private realtime: RealtimeService,
  ) {}

  // ===========================================================================
  // Summary rows shared with the variance and counts views
  // ===========================================================================

  /** Statuses that need more than the levels: a recent count variance, and GRN expiries. */
  async rowFlags(outletId: string, today: string, itemIds: string[]): Promise<Map<string, RowFlags>> {
    const weekStart = toDateOnly(addDays(today, -6));
    const adjustments = await this.repo.countAdjustmentsSince(outletId, weekStart);
    const perCount = new Map<string, Prisma.Decimal>();
    for (const a of adjustments) {
      const key = `${a.refId ?? ''}|${a.stockItemId}`;
      perCount.set(key, (perCount.get(key) ?? ZERO).plus(a.qty.mul(a.unitCost)));
    }
    const varianceItems = new Set<string>();
    for (const [key, value] of perCount) {
      if (value.abs().gte(VARIANCE_FLAG_VALUE)) varianceItems.add(key.split('|')[1]);
    }

    const recent = await this.repo.recentGrnIds(outletId, toDateOnly(addDays(today, -120)));
    const expiringItems = new Set<string>();
    if (recent.length > 0) {
      const lines = await this.repo.expiringGrnLines(
        recent.map((g) => g.id),
        toDateOnly(today),
        toDateOnly(addDays(today, 7)),
      );
      for (const l of lines) expiringItems.add(l.stockItemId);
    }

    const flags = new Map<string, RowFlags>();
    for (const id of itemIds) {
      flags.set(id, { variance: varianceItems.has(id), expiring: expiringItems.has(id) });
    }
    return flags;
  }

  /** One row for an item in a scope: a single location, or every location of the outlet when `locationId` is null. */
  private buildRow(
    item: StockItem,
    cells: Map<string, LevelCell> | undefined,
    scope: string[],
    locationId: string | null,
    flags: RowFlags,
  ): BuiltRow {
    let onHand = ZERO;
    let par = ZERO;
    let negative = false;
    let belowPar = false;
    for (const locId of scope) {
      const cell = cells?.get(locId);
      if (!cell) continue;
      onHand = onHand.plus(cell.onHand);
      par = par.plus(cell.parLevel);
      if (cell.onHand.lt(0)) negative = true;
      if (cell.parLevel.gt(0) && cell.onHand.lt(cell.parLevel)) belowPar = true;
    }
    const expiring = flags.expiring && onHand.gt(0);
    const status = statusFromFlags({ negative, belowPar, variance: flags.variance, expiring });
    const row: StockItemRow = {
      id: item.id,
      name: item.name,
      categoryName: item.categoryName,
      baseUnit: item.baseUnit,
      packSize: qty3(item.packSize),
      packName: item.packName,
      isLiquor: item.isLiquor,
      isKeg: item.isKeg,
      onHand: qty3(onHand),
      onHandDisplay: qtyDisplay(onHand, item),
      parLevel: qty3(par),
      parDisplay: qtyDisplay(par, item),
      avgCost: cost6(item.avgCost),
      unitCostDisplay: unitCostDisplay(item.avgCost, item),
      value: money2(onHand.mul(item.avgCost)),
      status,
      locationId,
    };
    return { row, status, flags: { negative, belowPar, variance: flags.variance, expiring } };
  }

  // ===========================================================================
  // Locations
  // ===========================================================================

  async listLocations(auth: AuthUser) {
    const locations = await this.repo.listLocations(auth.outletId);
    return this.locationViews(auth.outletId, locations);
  }

  async createLocation(dto: LocationDto, auth: AuthUser) {
    this.assertStockEdit(auth);
    const created = await this.repo.transaction(async (tx) => {
      if (await this.repo.findLocationByName(auth.outletId, dto.name)) {
        throw apiError(409, 'LOCATION_EXISTS', 'A location with this name already exists', { name: dto.name });
      }
      if (dto.isDefaultSales) await this.repo.clearDefaultSales(tx, auth.outletId);
      return this.repo.createLocation(tx, {
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        name: dto.name,
        kind: dto.kind,
        stations: dto.stations ?? [],
        isDefaultSales: dto.isDefaultSales ?? false,
      });
    });
    return this.locationView(auth.outletId, created);
  }

  async updateLocation(id: string, dto: LocationDto, auth: AuthUser) {
    this.assertStockEdit(auth);
    const updated = await this.repo.transaction(async (tx) => {
      const current = await this.repo.findLocation(auth.outletId, id);
      if (!current) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
      const clash = await this.repo.findLocationByName(auth.outletId, dto.name);
      if (clash && clash.id !== id) {
        throw apiError(409, 'LOCATION_EXISTS', 'A location with this name already exists', { name: dto.name });
      }
      if (dto.isDefaultSales) await this.repo.clearDefaultSales(tx, auth.outletId, id);
      return this.repo.updateLocation(tx, id, {
        name: dto.name,
        kind: dto.kind,
        stations: dto.stations ?? [],
        isDefaultSales: dto.isDefaultSales ?? false,
      });
    });
    return this.locationView(auth.outletId, updated);
  }

  private async locationView(outletId: string, location: StockLocation) {
    const [view] = await this.locationViews(outletId, [location]);
    return view;
  }

  private async locationViews(outletId: string, locations: StockLocation[]) {
    const levels = await this.repo.levelsForLocations(locations.map((l) => l.id));
    const items = await this.repo.findItemsByIds([...new Set(levels.map((l) => l.stockItemId))]);
    const itemById = new Map(items.map((i) => [i.id, i]));
    return locations.map((loc) => {
      let itemCount = 0;
      let value = ZERO;
      for (const lv of levels) {
        if (lv.locationId !== loc.id || lv.onHand.lte(0)) continue;
        itemCount += 1;
        const item = itemById.get(lv.stockItemId);
        if (item) value = value.plus(lv.onHand.mul(item.avgCost));
      }
      return {
        id: loc.id,
        name: loc.name,
        kind: loc.kind,
        stations: loc.stations,
        isDefaultSales: loc.isDefaultSales,
        itemCount,
        value: money2(value),
      };
    });
  }

  // ===========================================================================
  // Stock items
  // ===========================================================================

  async list(q: ItemsQueryDto, auth: AuthUser) {
    const locations = await this.repo.listLocations(auth.outletId);
    const locationIds = locations.map((l) => l.id);
    if (q.locationId && !locationIds.includes(q.locationId)) {
      throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    }
    const search = q.search?.trim();
    const where: Prisma.StockItemWhereInput = {
      isActive: true,
      ...(q.liquor === 'true' ? { isLiquor: true } : {}),
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: Prisma.QueryMode.insensitive } },
              { sku: { contains: search, mode: Prisma.QueryMode.insensitive } },
            ],
          }
        : {}),
    };
    const items = await this.repo.findItems(where);
    const today = await this.today(auth.outletId);
    const flags = await this.rowFlags(auth.outletId, today, items.map((i) => i.id));
    const levels = indexLevels(await this.repo.levelsForLocations(locationIds));
    const scope = q.locationId ? [q.locationId] : locationIds;

    const built = items.map((item) =>
      this.buildRow(item, levels.get(item.id), scope, q.locationId ?? null, flags.get(item.id) ?? { variance: false, expiring: false }),
    );
    return built.filter((b) => !q.status || matchesStatus(b.flags, q.status)).map((b) => b.row);
  }

  async detail(id: string, auth: AuthUser) {
    const item = await this.repo.findItem(id);
    if (!item) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');
    const locations = await this.repo.listLocations(auth.outletId);
    const locationIds = locations.map((l) => l.id);
    const levels = indexLevels(await this.repo.levelsForLocations(locationIds));
    const today = await this.today(auth.outletId);
    const flags = await this.rowFlags(auth.outletId, today, [item.id]);
    const { row } = this.buildRow(item, levels.get(item.id), locationIds, null, flags.get(item.id) ?? { variance: false, expiring: false });

    const vendor = item.preferredVendorId ? await this.repo.findVendor(item.preferredVendorId) : null;
    const cells = levels.get(item.id);
    return {
      ...row,
      name: item.name,
      sku: item.sku,
      categoryName: item.categoryName,
      baseUnit: item.baseUnit,
      packSize: qty3(item.packSize),
      packName: item.packName,
      purchaseUnitName: item.purchaseUnitName,
      purchaseUnitQty: qty3(item.purchaseUnitQty),
      costingMethod: item.costingMethod,
      preferredVendorId: item.preferredVendorId,
      isLiquor: item.isLiquor,
      isKeg: item.isKeg,
      shelfLifeDays: item.shelfLifeDays,
      isActive: item.isActive,
      preferredVendor: vendor ? { id: vendor.id, name: vendor.name } : null,
      lastPurchaseRate: item.lastPurchaseRate === null ? null : money2(item.lastPurchaseRate),
      levels: locations.map((loc) => {
        const cell = cells?.get(loc.id);
        const onHand = cell?.onHand ?? ZERO;
        return {
          locationId: loc.id,
          locationName: loc.name,
          onHand: qty3(onHand),
          onHandDisplay: qtyDisplay(onHand, item),
          parLevel: qty3(cell?.parLevel ?? ZERO),
        };
      }),
    };
  }

  async create(dto: StockItemDto, auth: AuthUser) {
    this.assertStockEdit(auth);
    const data = await this.parseItem(dto);
    const ctx = ledgerContext(auth);
    const id = await this.repo.transaction(async (tx) => {
      if (await this.repo.findItemByName(data.name)) {
        throw apiError(409, 'STOCK_ITEM_EXISTS', 'A stock item with this name already exists', { name: data.name });
      }
      const item = await this.repo.createItem(tx, { tenantId: auth.tenantId, ...data });
      const inputs = await this.openingInputs(auth.outletId, item.id, dto.opening ?? []);
      if (inputs.length > 0) await this.ledger.post(tx, ctx, inputs);
      return item.id;
    });
    publishLedgerEvents(this.realtime, ctx.events);
    return this.detail(id, auth);
  }

  async update(id: string, dto: StockItemDto, auth: AuthUser) {
    this.assertStockEdit(auth);
    const current = await this.repo.findItem(id);
    if (!current) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');
    const data = await this.parseItem(dto);
    await this.repo.transaction(async (tx) => {
      if (await this.repo.findItemByName(data.name, id)) {
        throw apiError(409, 'STOCK_ITEM_EXISTS', 'A stock item with this name already exists', { name: data.name });
      }
      await this.repo.updateItem(tx, id, data);
    });
    return this.detail(id, auth);
  }

  async setPar(id: string, dto: ParDto, auth: AuthUser) {
    this.assertStockEdit(auth);
    const item = await this.repo.findItem(id);
    if (!item) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');
    const ids = dto.levels.map((l) => l.locationId);
    const found = await this.repo.findLocationsByIds(auth.outletId, [...new Set(ids)]);
    if (found.length !== new Set(ids).size) {
      throw apiError(400, 'INVALID_REFERENCE', 'A location does not belong to this outlet');
    }
    const pars = dto.levels.map((l) => ({
      locationId: l.locationId,
      parLevel: decimalInput(l.parLevel, 'parLevel', { dp: 3, min: 0 }) as Prisma.Decimal,
    }));
    await this.repo.transaction(async (tx) => {
      for (const p of pars) await this.repo.upsertPar(tx, p.locationId, id, p.parLevel);
    });
    return this.detail(id, auth);
  }

  async movements(id: string, q: MovementsQueryDto, auth: AuthUser) {
    const item = await this.repo.findItem(id);
    if (!item) throw apiError(404, 'STOCK_ITEM_NOT_FOUND', 'Stock item not found');
    if (q.locationId) {
      const location = await this.repo.findLocation(auth.outletId, q.locationId);
      if (!location) throw apiError(404, 'LOCATION_NOT_FOUND', 'Location not found');
    }
    const from = dateInput(q.from, 'from');
    const to = dateInput(q.to, 'to');
    const rows = await this.repo.itemMovements(
      {
        outletId: auth.outletId,
        stockItemId: id,
        ...(q.locationId ? { locationId: q.locationId } : {}),
        ...(from || to ? { businessDate: { ...(from ? { gte: from } : {}), ...(to ? { lte: to } : {}) } } : {}),
      },
      q.limit ?? 100,
    );
    const users = await this.userNames([...new Set(rows.map((r) => r.createdById).filter((v): v is string => !!v))]);
    return rows.map((m) => ({
      id: m.id,
      type: m.type,
      qty: qty3(m.qty),
      qtyDisplay: qtyDisplay(m.qty, item),
      unitCost: cost6(m.unitCost),
      value: money2(m.qty.mul(m.unitCost)),
      refType: m.refType,
      refId: m.refId,
      note: m.note,
      businessDate: ymd(m.businessDate),
      createdAt: m.createdAt.toISOString(),
      createdBy: m.createdById ? { id: m.createdById, name: users.get(m.createdById) ?? null } : null,
    }));
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  assertStockEdit(auth: AuthUser): void {
    requireAnyPermission(this.permissions, auth, EDIT_PERMISSIONS);
  }

  /** Business date of the outlet now (05:00 cut-off), as YYYY-MM-DD. */
  async today(outletId: string): Promise<string> {
    const tz = await this.repo.outletTimezone(outletId);
    return businessDateFor(new Date(), tz, '05:00');
  }

  private async userNames(ids: string[]): Promise<Map<string, string | null>> {
    const users = ids.length ? await this.repo.findUsers(ids) : [];
    return new Map(users.map((u) => [u.id, userName(u)]));
  }

  private async parseItem(dto: StockItemDto) {
    const packSize = decimalInput(dto.packSize, 'packSize', { dp: 3, min: 0.001 }) as Prisma.Decimal;
    const purchaseUnitQty = decimalInput(dto.purchaseUnitQty, 'purchaseUnitQty', { dp: 3, min: 0.001 }) as Prisma.Decimal;
    if (dto.preferredVendorId && !(await this.repo.findVendor(dto.preferredVendorId))) {
      throw apiError(400, 'INVALID_REFERENCE', 'Preferred vendor not found', { field: 'preferredVendorId' });
    }
    return {
      name: dto.name.trim(),
      sku: dto.sku ?? null,
      categoryName: dto.categoryName ?? null,
      baseUnit: dto.baseUnit,
      packSize,
      packName: dto.packName,
      purchaseUnitName: dto.purchaseUnitName,
      purchaseUnitQty,
      costingMethod: dto.costingMethod,
      preferredVendorId: dto.preferredVendorId ?? null,
      isLiquor: dto.isLiquor,
      isKeg: dto.isKeg,
      shelfLifeDays: dto.shelfLifeDays ?? null,
      isActive: dto.isActive ?? true,
    };
  }

  /** OPENING movements for an opening stock list. Quantities are base units and may be negative (PLAN.md 1.3). */
  private async openingInputs(
    outletId: string,
    stockItemId: string,
    rows: { locationId: string; qty: number | string }[],
  ): Promise<MovementInput[]> {
    if (rows.length === 0) return [];
    const ids = [...new Set(rows.map((r) => r.locationId))];
    const found = await this.repo.findLocationsByIds(outletId, ids);
    if (found.length !== ids.length) throw apiError(400, 'INVALID_REFERENCE', 'A location does not belong to this outlet');
    const inputs: MovementInput[] = [];
    for (const r of rows) {
      const qty = decimalInput(r.qty, 'opening.qty', { dp: 3 }) as Prisma.Decimal;
      if (!qty.isZero()) {
        inputs.push({ locationId: r.locationId, stockItemId, type: 'OPENING', qty, refType: 'ITEM', refId: stockItemId });
      }
    }
    return inputs;
  }

}
