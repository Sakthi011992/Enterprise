import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ACCESS_LEVELS, AccessLevel } from '../../common/permissions/catalog';
import { PrismaService } from '../../prisma/prisma.service';

export interface WaiterNotice {
  tenantId: string;
  outletId: string;
  /** Permission the recipients must hold at EDIT, e.g. `guests.orders.confirm`. */
  permissionKey: string;
  type: string;
  title: string;
  body?: string | null;
  data?: Prisma.InputJsonValue;
}

/**
 * Waiter notifications for guest rounds and service requests (PLAN 2.6, Q-5: alert every waiter and captain
 * in the outlet). Same Notification rows as the KDS "ready" notice, but one row per user who holds the
 * permission at EDIT: the permissionKey broadcast row would also reach VIEW holders such as cashiers.
 */
@Injectable()
export class GuestNotificationsService {
  constructor(private prisma: PrismaService) {}

  /** Active users assigned to the outlet whose persona holds `permissionKey` at `min` or above. */
  async recipients(tenantId: string, outletId: string, permissionKey: string, min: AccessLevel = 'EDIT'): Promise<string[]> {
    const levels = ACCESS_LEVELS.slice(ACCESS_LEVELS.indexOf(min)) as AccessLevel[];
    const rows = await this.prisma.userOutlet.findMany({
      where: {
        outletId,
        user: { tenantId, isActive: true },
        persona: { permissions: { some: { permissionKey, level: { in: levels } } } },
      },
      select: { userId: true },
    });
    return [...new Set(rows.map((r) => r.userId))];
  }

  /** Creates one notification per recipient and returns their user ids. */
  async notify(n: WaiterNotice): Promise<string[]> {
    const users = await this.recipients(n.tenantId, n.outletId, n.permissionKey);
    if (users.length === 0) return [];
    await this.prisma.notification.createMany({
      data: users.map((userId) => ({
        tenantId: n.tenantId,
        outletId: n.outletId,
        userId,
        permissionKey: null,
        type: n.type,
        title: n.title,
        body: n.body ?? null,
        data: n.data,
      })),
    });
    return users;
  }
}
