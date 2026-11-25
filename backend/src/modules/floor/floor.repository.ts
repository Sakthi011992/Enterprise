import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Order statuses that still hold a table. */
export const OPEN_ORDER_STATUSES = ['OPEN', 'SENT', 'BILLED'] as const;

@Injectable()
export class FloorRepository {
  constructor(private prisma: PrismaService) {}

  // ---- areas -------------------------------------------------------------

  listAreas(outletId: string) {
    return this.prisma.area.findMany({ where: { outletId }, orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] });
  }

  findArea(id: string, outletId: string) {
    return this.prisma.area.findFirst({ where: { id, outletId } });
  }

  createArea(data: Prisma.AreaUncheckedCreateInput) {
    return this.prisma.area.create({ data });
  }

  updateArea(id: string, data: Prisma.AreaUncheckedUpdateInput) {
    return this.prisma.area.update({ where: { id }, data });
  }

  countActiveTablesInArea(areaId: string) {
    return this.prisma.diningTable.count({ where: { areaId, isActive: true } });
  }

  // ---- tables ------------------------------------------------------------

  listActiveTables(outletId: string) {
    return this.prisma.diningTable.findMany({
      where: { outletId, isActive: true },
      orderBy: [{ name: 'asc' }],
    });
  }

  findTable(id: string, outletId: string) {
    return this.prisma.diningTable.findFirst({ where: { id, outletId } });
  }

  findTableByName(outletId: string, name: string) {
    return this.prisma.diningTable.findFirst({ where: { outletId, name }, select: { id: true } });
  }

  createTable(data: Prisma.DiningTableUncheckedCreateInput) {
    return this.prisma.diningTable.create({ data });
  }

  updateTable(id: string, data: Prisma.DiningTableUncheckedUpdateInput) {
    return this.prisma.diningTable.update({ where: { id }, data });
  }

  /** Open orders (OPEN, SENT, BILLED) on the given tables, oldest first. */
  openOrdersOnTables(tableIds: string[]) {
    return this.prisma.order.findMany({
      where: { tableId: { in: tableIds }, status: { in: [...OPEN_ORDER_STATUSES] } },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        tableId: true,
        orderNumber: true,
        covers: true,
        grandTotal: true,
        createdAt: true,
        waiterId: true,
      },
    });
  }

  countOpenOrdersOnTable(tableId: string) {
    return this.prisma.order.count({ where: { tableId, status: { in: [...OPEN_ORDER_STATUSES] } } });
  }

  findUsers(ids: string[]) {
    if (ids.length === 0) return Promise.resolve([]);
    return this.prisma.user.findMany({
      where: { id: { in: ids } },
      select: { id: true, displayName: true, username: true },
    });
  }
}
