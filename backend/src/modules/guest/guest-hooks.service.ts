import { Injectable, Logger } from '@nestjs/common';
import { GuestLifecycleService } from './guest-lifecycle.service';

/**
 * One-line hooks for the existing order, KDS, payment and floor paths (PLAN 2.6, 2.7). Fire-and-forget:
 * they never throw into the caller and never delay its response.
 */
@Injectable()
export class GuestHooks {
  private readonly logger = new Logger(GuestHooks.name);

  constructor(private lifecycle: GuestLifecycleService) {}

  orderChanged(orderId: string | null | undefined): void {
    if (orderId) this.run(() => this.lifecycle.onOrderChanged(orderId));
  }

  orderMerged(fromOrderId: string, toOrderId: string): void {
    this.run(() => this.lifecycle.onOrderMerged(fromOrderId, toOrderId));
  }

  tableChanged(tableId: string | null | undefined): void {
    if (tableId) this.run(() => this.lifecycle.onTableChanged(tableId));
  }

  private run(fn: () => Promise<unknown>) {
    fn().catch((e) => this.logger.warn(`Guest hook failed: ${(e as Error).message}`));
  }
}
