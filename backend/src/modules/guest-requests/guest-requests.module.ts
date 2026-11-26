import { Module } from '@nestjs/common';
import { ApprovalsModule } from '../approvals/approvals.module';
import { GuestModule } from '../guest/guest.module';
import { OrdersModule } from '../orders/orders.module';
import { GuestRequestsController } from './guest-requests.controller';
import { GuestRequestsService } from './guest-requests.service';

/** Staff API for guest rounds and service requests (PLAN 2.7). */
@Module({
  imports: [OrdersModule, ApprovalsModule, GuestModule],
  controllers: [GuestRequestsController],
  providers: [GuestRequestsService],
})
export class GuestRequestsModule {}
