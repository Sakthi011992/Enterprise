import { Injectable } from '@nestjs/common';
import { DeviceType } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export const DEVICE_FIELDS = {
  id: true,
  name: true,
  type: true,
  outletId: true,
  isActive: true,
  lastSeenAt: true,
  createdAt: true,
  outlet: { select: { name: true } },
} as const;

/** Data access for registered devices. */
@Injectable()
export class DevicesRepository {
  constructor(private prisma: PrismaService) {}

  listForTenant(tenantId: string, outletId?: string) {
    return this.prisma.device.findMany({
      where: { tenantId, ...(outletId ? { outletId } : {}) },
      select: DEVICE_FIELDS,
      orderBy: { createdAt: 'desc' },
    });
  }

  findActiveOutlet(id: string, tenantId: string) {
    return this.prisma.outlet.findFirst({ where: { id, tenantId, isActive: true }, select: { id: true } });
  }

  findOwned(id: string, tenantId: string) {
    return this.prisma.device.findFirst({ where: { id, tenantId }, select: { id: true } });
  }

  create(data: { tenantId: string; outletId: string; name: string; type: DeviceType; keyHash: string }) {
    return this.prisma.device.create({ data, select: DEVICE_FIELDS });
  }

  deactivate(id: string) {
    return this.prisma.device.update({ where: { id }, data: { isActive: false } });
  }
}
