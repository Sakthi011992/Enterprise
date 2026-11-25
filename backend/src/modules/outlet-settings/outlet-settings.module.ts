import { Module } from '@nestjs/common';
import { OutletSettingsController } from './outlet-settings.controller';
import { OutletSettingsRepository } from './outlet-settings.repository';
import { OutletSettingsService } from './outlet-settings.service';

@Module({
  controllers: [OutletSettingsController],
  providers: [OutletSettingsService, OutletSettingsRepository],
  exports: [OutletSettingsService],
})
export class OutletSettingsModule {}
