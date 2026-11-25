import { RealtimeService } from './realtime.service';
import { outletEvent, stationEvent, userEvent } from './realtime.types';

describe('RealtimeService', () => {
  it('does nothing when no server is attached (unit tests, before the gateway starts)', () => {
    const svc = new RealtimeService();
    expect(svc.isReady).toBe(false);
    expect(() => svc.publish([outletEvent('o1', 'menu.item86', { productId: 'p1' })])).not.toThrow();
  });

  it('sends station events to the station room and the all-stations room', () => {
    const emit = jest.fn();
    const to = jest.fn(() => ({ emit }));
    const svc = new RealtimeService();
    svc.attach({ to });

    svc.publish([stationEvent('o1', 'BAR', 'kds.ticket.created', { id: 't1' })]);

    expect(to.mock.calls.map((c) => c[0])).toEqual(['outlet:o1:station:BAR', 'outlet:o1:station:*']);
    expect(emit).toHaveBeenCalledWith('kds.ticket.created', { id: 't1' });
  });

  it('routes outlet and user events to their rooms and skips events missing their ids', () => {
    const emit = jest.fn();
    const to = jest.fn(() => ({ emit }));
    const svc = new RealtimeService();
    svc.attach({ to });

    svc.publish([
      outletEvent('o1', 'order.updated', { orderId: 'ord1' }),
      userEvent('u9', 'kds.ready', { ticketId: 't1' }),
      { scope: 'station', event: 'broken', payload: {} },
    ]);

    expect(to.mock.calls.map((c) => c[0])).toEqual(['outlet:o1', 'user:u9']);
  });
});
