import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { InvoiceModule } from '../invoice/invoice.module';
import { ApprovalsModule } from '../approvals/approvals.module';
import { TabsLimitModule } from '../tabs/tabs-limit.module';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { OrderPaymentsController } from './order-payments.controller';
import { PaymentsRepository } from './payments.repository';

@Module({
  imports: [OrdersModule, InvoiceModule, ApprovalsModule, TabsLimitModule],
  controllers: [PaymentsController, OrderPaymentsController],
  providers: [PaymentsService, PaymentsRepository],
  exports: [PaymentsService],
})
export class PaymentsModule {}
