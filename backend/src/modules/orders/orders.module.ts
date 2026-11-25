import { Module } from '@nestjs/common';
import { TaxModule } from '../tax/tax.module';
import { ApprovalsModule } from '../approvals/approvals.module';
import { TabsLimitModule } from '../tabs/tabs-limit.module';
import { OrdersController } from './orders.controller';
import { OrdersRepository } from './orders.repository';
import { OrdersService } from './orders.service';
import { OrderLineResolver } from './order-line-resolver';
import { OrderPricingService } from './order-pricing.service';

/** Orders, lines, discounts, voids, table moves and bills. PaymentsModule builds on the exported pricing service. */
@Module({
  imports: [TaxModule, ApprovalsModule, TabsLimitModule],
  controllers: [OrdersController],
  providers: [OrdersService, OrdersRepository, OrderLineResolver, OrderPricingService],
  exports: [OrdersService, OrdersRepository, OrderPricingService],
})
export class OrdersModule {}
