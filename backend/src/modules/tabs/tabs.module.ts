import { Module } from '@nestjs/common';
import { ApprovalsModule } from '../approvals/approvals.module';
import { OrdersModule } from '../orders/orders.module';
import { PaymentsModule } from '../payments/payments.module';
import { LockerController } from './locker.controller';
import { LockerRepository } from './locker.repository';
import { LockerService } from './locker.service';
import { TabsController } from './tabs.controller';
import { TabsLimitModule } from './tabs-limit.module';
import { TabsService } from './tabs.service';

/**
 * Bar tabs and the bottle locker. Imports OrdersModule and PaymentsModule, so neither of them may import
 * this module. They import TabsLimitModule instead.
 */
@Module({
  imports: [TabsLimitModule, OrdersModule, PaymentsModule, ApprovalsModule],
  controllers: [TabsController, LockerController],
  providers: [TabsService, LockerService, LockerRepository],
  exports: [TabsService],
})
export class TabsModule {}
