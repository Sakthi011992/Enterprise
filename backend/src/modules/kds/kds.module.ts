import { Module } from '@nestjs/common';
import { KdsController } from './kds.controller';
import { KdsRepository } from './kds.repository';
import { KdsService } from './kds.service';

/** Kitchen and bar display. Uses the global RealtimeModule, PermissionsModule and PrismaModule. */
@Module({
  controllers: [KdsController],
  providers: [KdsService, KdsRepository],
  exports: [KdsService],
})
export class KdsModule {}
