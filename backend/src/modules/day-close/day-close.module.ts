import { Module } from '@nestjs/common';
import { ApprovalsModule } from '../approvals/approvals.module';
import { DayCloseController } from './day-close.controller';
import { DayCloseRepository } from './day-close.repository';
import { DayCloseService } from './day-close.service';

@Module({
  imports: [ApprovalsModule],
  controllers: [DayCloseController],
  providers: [DayCloseService, DayCloseRepository],
  exports: [DayCloseService],
})
export class DayCloseModule {}
