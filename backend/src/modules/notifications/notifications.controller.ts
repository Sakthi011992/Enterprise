import { Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { NotificationsService } from './notifications.service';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';

@ApiTags('notifications')
@ApiBearerAuth()
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  @ApiOperation({ summary: 'Notifications visible to the caller in the current outlet' })
  list(@CurrentUser() auth: AuthUser, @Query('unreadOnly') unreadOnly?: string) {
    return this.notifications.list(auth, unreadOnly === 'true');
  }

  @Post('read-all')
  readAll(@CurrentUser() auth: AuthUser) {
    return this.notifications.markAllRead(auth);
  }

  @Post(':id/read')
  read(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.notifications.markRead(id, auth);
  }
}
