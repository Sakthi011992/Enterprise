import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export interface NotificationScope {
  tenantId: string;
  outletId: string;
  userId: string;
  /** Permission keys the caller holds at VIEW or above. */
  permissionKeys: string[];
}

const LIST_LIMIT = 50;

/** Data access for notifications. Owns the visibility rule, since it is a query shape. */
@Injectable()
export class NotificationsRepository {
  constructor(private prisma: PrismaService) {}

  /**
   * Rows the scope may see: tenant-wide or for this outlet, and either addressed to
   * the user, sent to everyone in the tenant, or sent to a permission the user holds.
   */
  private visibleWhere(scope: NotificationScope): Prisma.NotificationWhereInput {
    return {
      tenantId: scope.tenantId,
      AND: [
        { OR: [{ outletId: null }, { outletId: scope.outletId }] },
        {
          OR: [
            { userId: scope.userId },
            { userId: null, permissionKey: null },
            { userId: null, permissionKey: { in: scope.permissionKeys } },
          ],
        },
      ],
    };
  }

  async list(scope: NotificationScope, unreadOnly: boolean) {
    const base = this.visibleWhere(scope);
    const where: Prisma.NotificationWhereInput = unreadOnly ? { ...base, readAt: null } : base;
    const [data, unreadCount] = await Promise.all([
      this.prisma.notification.findMany({ where, orderBy: { createdAt: 'desc' }, take: LIST_LIMIT }),
      this.prisma.notification.count({ where: { ...base, readAt: null } }),
    ]);
    return { data, unreadCount };
  }

  findVisible(id: string, scope: NotificationScope) {
    return this.prisma.notification.findFirst({ where: { id, ...this.visibleWhere(scope) } });
  }

  markRead(id: string) {
    return this.prisma.notification.update({ where: { id }, data: { readAt: new Date() } });
  }

  async markAllRead(scope: NotificationScope): Promise<number> {
    const result = await this.prisma.notification.updateMany({
      where: { ...this.visibleWhere(scope), readAt: null },
      data: { readAt: new Date() },
    });
    return result.count;
  }
}
