import { Injectable, NotFoundException } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { levelAtLeast } from '../../common/permissions/catalog';
import { NotificationScope, NotificationsRepository } from './notifications.repository';

@Injectable()
export class NotificationsService {
  constructor(private repo: NotificationsRepository) {}

  /** Scope from the caller's session: their outlet and every permission at VIEW or above. */
  private scopeOf(auth: AuthUser): NotificationScope {
    const permissionKeys = Object.entries(auth.permissions)
      .filter(([, grant]) => levelAtLeast(grant.level, 'VIEW'))
      .map(([key]) => key);
    return { tenantId: auth.tenantId, outletId: auth.outletId, userId: auth.userId, permissionKeys };
  }

  list(auth: AuthUser, unreadOnly: boolean) {
    return this.repo.list(this.scopeOf(auth), unreadOnly);
  }

  async markRead(id: string, auth: AuthUser) {
    const scope = this.scopeOf(auth);
    const row = await this.repo.findVisible(id, scope);
    if (!row) throw new NotFoundException('Notification not found');
    if (!row.readAt) await this.repo.markRead(id);
    return { success: true };
  }

  async markAllRead(auth: AuthUser) {
    const count = await this.repo.markAllRead(this.scopeOf(auth));
    return { success: true, count };
  }
}
