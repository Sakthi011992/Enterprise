import { Injectable, NotFoundException, Optional } from '@nestjs/common';
import { GuestHooks } from '../guest/guest-hooks.service';
import { GuestRepository } from '../guest/guest.repository';
import { GuestConfigService } from '../guest-config/guest-config.service';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { CreateAreaDto, CreateTableDto, TableStatusDto, UpdateAreaDto, UpdateTableDto } from './dto/floor.dto';
import { FloorRepository } from './floor.repository';

@Injectable()
export class FloorService {
  constructor(
    private repo: FloorRepository,
    @Optional() private guestHooks?: GuestHooks,
    @Optional() private guestRepo?: GuestRepository,
    @Optional() private guestConfig?: GuestConfigService,
  ) {}

  // ---- areas -------------------------------------------------------------

  listAreas(auth: AuthUser) {
    return this.repo.listAreas(auth.outletId);
  }

  createArea(dto: CreateAreaDto, auth: AuthUser) {
    return this.repo.createArea({
      tenantId: auth.tenantId,
      outletId: auth.outletId,
      name: dto.name,
      sortOrder: dto.sortOrder ?? 0,
      priceMarkupPercent: new Prisma.Decimal(dto.priceMarkupPercent ?? 0),
      isSmoking: dto.isSmoking ?? false,
      isActive: dto.isActive ?? true,
    });
  }

  async updateArea(id: string, dto: UpdateAreaDto, auth: AuthUser) {
    await this.requireArea(id, auth);
    return this.repo.updateArea(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.sortOrder !== undefined ? { sortOrder: dto.sortOrder } : {}),
      ...(dto.priceMarkupPercent !== undefined ? { priceMarkupPercent: new Prisma.Decimal(dto.priceMarkupPercent) } : {}),
      ...(dto.isSmoking !== undefined ? { isSmoking: dto.isSmoking } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
    });
  }

  /** Soft delete. An area with active tables cannot be removed. */
  async removeArea(id: string, auth: AuthUser) {
    await this.requireArea(id, auth);
    const count = await this.repo.countActiveTablesInArea(id);
    if (count > 0) throw apiError(409, 'AREA_IN_USE', 'Move or remove the tables in this area first', { count });
    await this.repo.updateArea(id, { isActive: false });
    return { success: true };
  }

  // ---- tables ------------------------------------------------------------

  /** Live floor view: every active table with its open order, if any. */
  async listTables(auth: AuthUser) {
    const tables = await this.repo.listActiveTables(auth.outletId);
    const orders = await this.repo.openOrdersOnTables(tables.map((t) => t.id));
    const firstOrder = new Map<string, (typeof orders)[number]>();
    for (const order of orders) {
      if (order.tableId && !firstOrder.has(order.tableId)) firstOrder.set(order.tableId, order);
    }
    const waiterIds = [...new Set([...firstOrder.values()].map((o) => o.waiterId).filter((w): w is string => !!w))];
    const users = await this.repo.findUsers(waiterIds);
    const names = new Map(users.map((u) => [u.id, u.displayName ?? u.username] as const));
    // Guest ordering badges (Phase 4): PIN in TABLE_PIN mode, pending rounds, bill asked.
    const guest = this.guestRepo ? await this.guestRepo.floorGuestInfo(tables.map((t) => t.id)) : null;
    const pinMode = this.guestConfig
      ? (await this.guestConfig.get(auth.tenantId)).verification.method === 'TABLE_PIN'
      : false;

    return tables.map((t) => {
      const order = firstOrder.get(t.id);
      return {
        id: t.id,
        name: t.name,
        areaId: t.areaId,
        seats: t.seats,
        shape: t.shape,
        posX: t.posX,
        posY: t.posY,
        status: t.status,
        mergedIntoId: t.mergedIntoId,
        guestPin: pinMode && t.status === 'OCCUPIED' ? t.guestPin ?? null : null,
        pendingRounds: guest?.pending.get(t.id) ?? 0,
        billAsked: guest?.bill.has(t.id) ?? false,
        order: order
          ? {
              id: order.id,
              orderNumber: order.orderNumber,
              covers: order.covers,
              grandTotal: order.grandTotal,
              openedAt: order.createdAt,
              waiterName: order.waiterId ? names.get(order.waiterId) ?? null : null,
            }
          : null,
      };
    });
  }

  async createTable(dto: CreateTableDto, auth: AuthUser) {
    const area = await this.repo.findArea(dto.areaId, auth.outletId);
    if (!area) throw new NotFoundException('Area not found');
    await this.assertNameFree(auth.outletId, dto.name);
    return this.repo.createTable({
      tenantId: auth.tenantId,
      outletId: auth.outletId,
      areaId: area.id,
      name: dto.name,
      seats: dto.seats ?? 4,
      shape: dto.shape ?? 'SQUARE',
      posX: dto.posX ?? 0,
      posY: dto.posY ?? 0,
      isActive: dto.isActive ?? true,
    });
  }

  async updateTable(id: string, dto: UpdateTableDto, auth: AuthUser) {
    const table = await this.requireTable(id, auth);
    if (dto.areaId !== undefined) {
      const area = await this.repo.findArea(dto.areaId, auth.outletId);
      if (!area) throw new NotFoundException('Area not found');
    }
    if (dto.name !== undefined && dto.name !== table.name) await this.assertNameFree(auth.outletId, dto.name);
    return this.repo.updateTable(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.areaId !== undefined ? { areaId: dto.areaId } : {}),
      ...(dto.seats !== undefined ? { seats: dto.seats } : {}),
      ...(dto.shape !== undefined ? { shape: dto.shape } : {}),
      ...(dto.posX !== undefined ? { posX: dto.posX } : {}),
      ...(dto.posY !== undefined ? { posY: dto.posY } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
    });
  }

  /** Soft delete. A table with an open order cannot be removed. */
  async removeTable(id: string, auth: AuthUser) {
    await this.requireTable(id, auth);
    if ((await this.repo.countOpenOrdersOnTable(id)) > 0) {
      throw apiError(409, 'TABLE_HAS_OPEN_ORDER', 'Close or move the order on this table first');
    }
    await this.repo.updateTable(id, { isActive: false });
    return { success: true };
  }

  /** Staff set FREE, CLEANING or RESERVED. A table with an open order can only be set to CLEANING. */
  async setStatus(id: string, dto: TableStatusDto, auth: AuthUser) {
    await this.requireTable(id, auth);
    if (dto.status !== 'CLEANING' && (await this.repo.countOpenOrdersOnTable(id)) > 0) {
      throw apiError(409, 'TABLE_HAS_OPEN_ORDER', 'This table has an open order', { status: dto.status });
    }
    const updated = await this.repo.updateTable(id, { status: dto.status });
    this.guestHooks?.tableChanged(id);
    return updated;
  }

  private async requireArea(id: string, auth: AuthUser) {
    const area = await this.repo.findArea(id, auth.outletId);
    if (!area) throw new NotFoundException('Area not found');
    return area;
  }

  private async requireTable(id: string, auth: AuthUser) {
    const table = await this.repo.findTable(id, auth.outletId);
    if (!table) throw new NotFoundException('Table not found');
    return table;
  }

  private async assertNameFree(outletId: string, name: string) {
    if (await this.repo.findTableByName(outletId, name)) {
      throw apiError(409, 'TABLE_NAME_TAKEN', `A table named ${name} already exists`);
    }
  }
}
