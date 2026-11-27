import { Module } from '@nestjs/common';
import { GuestConfigController } from './guest-config.controller';
import { GuestConfigRepository } from './guest-config.repository';
import { GuestConfigService } from './guest-config.service';

@Module({
  controllers: [GuestConfigController],
  providers: [GuestConfigService, GuestConfigRepository],
  exports: [GuestConfigService],
})
export class GuestConfigModule {}
