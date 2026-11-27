import { Inject, Module, OnModuleInit, Optional } from '@nestjs/common';
import { MenuModule } from '../menu/menu.module';
import { OrdersModule } from '../orders/orders.module';
import { GuestEventsService } from '../realtime/guest-events.service';
import { GuestController, GuestPublicMenuController } from './guest.controller';
import { GuestMenuService } from './guest-menu.service';
import { GuestOrderViewService } from './guest-order-view.service';
import { GuestOrderingService } from './guest-ordering.service';

/** Guest API (PLAN 2.4, 2.5). GuestCoreModule (global) supplies the repository, lifecycle and auth pieces. */
@Module({
  imports: [OrdersModule, MenuModule],
  controllers: [GuestPublicMenuController, GuestController],
  providers: [GuestMenuService, GuestOrderViewService, GuestOrderingService],
  exports: [GuestOrderingService, GuestOrderViewService, GuestMenuService],
})
export class GuestModule implements OnModuleInit {
  constructor(
    private views: GuestOrderViewService,
    @Optional() @Inject(GuestEventsService) private events?: GuestEventsService,
  ) {}

  /** Gives G-C's guest events the GuestOrderView builder for guest.order.updated. */
  onModuleInit() {
    this.events?.registerViewBuilder({ build: (orderId) => this.views.build(orderId) });
  }
}
