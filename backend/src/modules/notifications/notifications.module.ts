import { Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { NotificationsRepository } from './notifications.repository';
import { GuestNotificationsService } from './guest-notifications.service';

@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsRepository, GuestNotificationsService],
  exports: [NotificationsService, GuestNotificationsService],
})
export class NotificationsModule {}
