import { Global, Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthModule } from '../auth/auth.module';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';
import { SocketAuthService } from './socket-auth.service';

/** Global so any service can publish realtime messages without importing this module. */
@Global()
@Module({
  imports: [JwtModule.register({}), AuthModule],
  providers: [RealtimeService, RealtimeGateway, SocketAuthService],
  exports: [RealtimeService],
})
export class RealtimeModule {}
