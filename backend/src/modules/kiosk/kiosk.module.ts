import { Module } from '@nestjs/common';
import { KioskService } from './kiosk.service';
import { KioskController, KioskAdminController } from './kiosk.controller';

@Module({
  controllers: [KioskController, KioskAdminController],
  providers: [KioskService],
  exports: [KioskService],
})
export class KioskModule {}
