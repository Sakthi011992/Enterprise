import { Global, Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { GUEST_EVENTS } from './guest-events.port';
import { GuestEventsService } from './guest-events.service';
import { GuestSocketAuthService } from './guest-socket-auth.service';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';
import { SocketAuthService } from './socket-auth.service';

/**
 * Global so any service can publish realtime messages without importing this module. Also binds the
 * GUEST_EVENTS port that G-B's guest ordering injects.
 */
@Global()
@Module({
  imports: [JwtModule.register({}), AuthModule, NotificationsModule],
  providers: [
    RealtimeService,
    RealtimeGateway,
    SocketAuthService,
    GuestSocketAuthService,
    GuestEventsService,
    { provide: GUEST_EVENTS, useExisting: GuestEventsService },
  ],
  exports: [RealtimeService, GuestEventsService, GUEST_EVENTS],
})
export class RealtimeModule {}
