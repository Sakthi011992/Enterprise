import { AuthUser } from '../../common/decorators/current-user.decorator';
import { RealtimeEvent } from '../realtime/realtime.types';
import { RealtimeService } from '../realtime/realtime.service';
import { MovementContext } from '../stock-core/stock-ledger.service';

/** A fresh ledger context for one request. Events queued by the ledger are published after commit. */
export function ledgerContext(auth: AuthUser, now: Date = new Date()): MovementContext & { events: NonNullable<MovementContext['events']> } {
  return { tenantId: auth.tenantId, outletId: auth.outletId, userId: auth.userId, now, events: [] };
}

/** Publishes the events a ledger call queued, after its transaction has committed. */
export function publishLedgerEvents(realtime: RealtimeService, events: RealtimeEvent[] | undefined): void {
  if (events && events.length > 0) realtime.publish(events);
}
