import { Module } from '@nestjs/common';
import { TabsLimitService } from './tabs-limit.service';
import { TabsRepository } from './tabs.repository';

/**
 * The tab rules used by OrdersModule (limit check) and PaymentsModule (close on payment). It has no
 * imports of its own, which keeps the module graph acyclic. TabsModule imports it, not the other way round.
 */
@Module({
  providers: [TabsRepository, TabsLimitService],
  exports: [TabsLimitService, TabsRepository],
})
export class TabsLimitModule {}
