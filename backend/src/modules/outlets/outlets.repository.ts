import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export const OUTLET_FIELDS = {
  id: true,
  name: true,
  code: true,
  address: true,
  timezone: true,
  isActive: true,
} as const;

export interface OutletWriteData {
  name?: string;
  code?: string;
  address?: string | null;
  timezone?: string;
  isActive?: boolean;
}

/** Data access for outlets and the user-outlet assignments that gate them. */
@Injectable()
export class OutletsRepository {
  constructor(private prisma: PrismaService) {}

  listForTenant(tenantId: string) {
    return this.prisma.outlet.findMany({
      where: { tenantId },
      select: OUTLET_FIELDS,
      orderBy: { code: 'asc' },
    });
  }

  async listAssignedTo(userId: string, tenantId: string) {
    const rows = await this.prisma.userOutlet.findMany({
      where: { userId, outlet: { tenantId, isActive: true } },
      include: { outlet: { select: OUTLET_FIELDS } },
      orderBy: { outlet: { code: 'asc' } },
    });
    return rows.map((r) => r.outlet);
  }

  async codeTaken(tenantId: string, code: string, exceptId?: string): Promise<boolean> {
    const row = await this.prisma.outlet.findFirst({
      where: { tenantId, code, ...(exceptId ? { NOT: { id: exceptId } } : {}) },
      select: { id: true },
    });
    return row !== null;
  }

  findOwned(id: string, tenantId: string) {
    return this.prisma.outlet.findFirst({ where: { id, tenantId }, select: { id: true } });
  }

  create(data: { tenantId: string; name: string; code: string; address?: string; timezone?: string }) {
    return this.prisma.outlet.create({ data, select: OUTLET_FIELDS });
  }

  update(id: string, data: OutletWriteData) {
    return this.prisma.outlet.update({ where: { id }, data, select: OUTLET_FIELDS });
  }
}
