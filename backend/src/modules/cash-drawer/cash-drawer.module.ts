import { Module } from '@nestjs/common';
import { ApprovalsModule } from '../approvals/approvals.module';
import { CashDrawerController } from './cash-drawer.controller';
import { CashDrawerRepository } from './cash-drawer.repository';
import { CashDrawerService } from './cash-drawer.service';

@Module({
  imports: [ApprovalsModule],
  controllers: [CashDrawerController],
  providers: [CashDrawerService, CashDrawerRepository],
  exports: [CashDrawerService],
})
export class CashDrawerModule {}
