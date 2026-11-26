import { HttpException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { GuestNotificationsService } from '../notifications/guest-notifications.service';
import { NotConfiguredGateway } from '../payments/gateway/payment-gateway';
import { maskPhone } from './guest-events.port';
import { GuestEventsService } from './guest-events.service';
import { GuestSocketAuthService } from './guest-socket-auth.service';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';
import { SocketAuthService } from './socket-auth.service';
import { tableEvent } from './realtime.types';

const STAFF_SECRET = 'staff-secret';
const GUEST_SECRET = 'guest-secret';
const jwt = new JwtService({});
const config: any = { get: (k: string) => ({ JWT_ACCESS_SECRET: STAFF_SECRET, GUEST_JWT_SECRET: GUEST_SECRET })[k] };

const claims = { kind: 'guest', sessionId: 's1', participantId: 'p1', tableId: 'tb1', outletId: 'o1', tenantId: 't1' };
const guestToken = (c: object = claims, secret = GUEST_SECRET) => jwt.sign(c, { secret, expiresIn: 60 });

const staffPayload = { sub: 'u1', username: 'ravi', tenantId: 't1', outletId: 'o1', personaId: 'p1', personaKey: 'waiter', tokenVersion: 1 };
const user = { id: 'u1', username: 'ravi', tenantId: 't1', tokenVersion: 1 };
const access = { outletId: 'o1', personaId: 'p1', outlet: { isActive: true, tenantId: 't1' }, persona: { id: 'p1', key: 'waiter' } };

function setup(sessionStatus: string | null = 'OPEN') {
  const prisma: any = { guestSession: { findFirst: jest.fn(async () => (sessionStatus ? { status: sessionStatus } : null)) } };
  const authRepo: any = { findActiveUser: jest.fn(async () => user), findUserOutletAccess: jest.fn(async () => access) };
  const permissions: any = { forPersona: jest.fn(async () => ({})) };
  const staff = new SocketAuthService(jwt, config, authRepo, permissions);
  const guests = new GuestSocketAuthService(jwt, config, prisma);
  const gateway = new RealtimeGateway(new RealtimeService(), staff, guests, jwt);
  return { gateway, prisma };
}

function client(auth: object) {
  return { id: 'c1', handshake: { auth }, join: jest.fn(), disconnect: jest.fn() } as any;
}

describe('guest socket auth', () => {
  it('accepts a valid guest token and joins only the table room', async () => {
    const { gateway } = setup();
    const c = client({ token: guestToken(), stations: ['BAR', '*'] });
    await gateway.handleConnection(c);
    expect(c.join.mock.calls.map((a: unknown[]) => a[0])).toEqual(['table:tb1']);
    expect(c.disconnect).not.toHaveBeenCalled();
  });

  it('refuses a guest token whose session is closed or missing', async () => {
    for (const status of ['CLOSED', null]) {
      const { gateway } = setup(status);
      const c = client({ token: guestToken() });
      await gateway.handleConnection(c);
      expect(c.join).not.toHaveBeenCalled();
      expect(c.disconnect).toHaveBeenCalledWith(true);
    }
  });

  it('refuses a kind:guest token signed with the staff secret', async () => {
    const { gateway } = setup();
    await expect(gateway.roomsFor({ token: guestToken(claims, STAFF_SECRET) })).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('refuses a guest-secret token without kind:guest, and never treats it as staff', async () => {
    const { gateway } = setup();
    const { kind: _k, ...noKind } = claims;
    await expect(gateway.roomsFor({ token: guestToken({ ...noKind, sub: 'u1', tokenVersion: 1 }) })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('refuses a staff-secret token that also carries kind', async () => {
    const { gateway } = setup();
    const tok = jwt.sign({ ...staffPayload, kind: 'staff' }, { secret: STAFF_SECRET });
    await expect(gateway.roomsFor({ token: tok })).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('a guest token asking for stations still gets no outlet, user or station room', async () => {
    const { gateway } = setup();
    const rooms = await gateway.roomsFor({ token: guestToken(), stations: ['BAR', '*'] });
    expect(rooms).toEqual(['table:tb1']);
    expect(rooms.some((r) => r.startsWith('outlet:') || r.startsWith('user:'))).toBe(false);
  });

  it('staff sockets are unchanged', async () => {
    const { gateway } = setup();
    const tok = jwt.sign(staffPayload, { secret: STAFF_SECRET });
    expect(await gateway.roomsFor({ token: tok, stations: ['BAR'] })).toEqual(['outlet:o1', 'user:u1', 'outlet:o1:station:BAR']);
  });
});

describe('RealtimeService table scope', () => {
  it('publishes table events to table:<id>', () => {
    const emit = jest.fn();
    const svc = new RealtimeService();
    svc.attach({ to: jest.fn(() => ({ emit })) } as any);
    svc.publish([tableEvent('tb1', 'guest.order.updated', { x: 1 }), tableEvent(null, 'skip', {})]);
    expect(emit).toHaveBeenCalledTimes(1);
  });
});

describe('GuestEventsService', () => {
  function build(order: any = { guestSessionId: 's1', tableId: 'tb1', guestSession: { tableId: 'tb1' } }, view?: any) {
    const sent: { room: string; event: string; payload: any }[] = [];
    const realtime = new RealtimeService();
    realtime.attach({ to: (room: string) => ({ emit: (event: string, payload: any) => sent.push({ room, event, payload }) }) });
    const prisma: any = { order: { findUnique: jest.fn(async () => order) } };
    const notices: any = { notify: jest.fn(async () => ['u1']) };
    const svc = new GuestEventsService(realtime, prisma, notices, view ? { build: async () => view } : undefined);
    return { svc, sent, notices };
  }

  it('orderChanged emits the fallback to the table room, or the built view', async () => {
    const a = build();
    await a.svc.orderChanged('ord1');
    expect(a.sent).toEqual([{ room: 'table:tb1', event: 'guest.order.updated', payload: { orderId: 'ord1', changed: true } }]);
    const b = build(undefined, { table: 'R4', status: 'OPEN' });
    await b.svc.orderChanged('ord1');
    expect(b.sent[0].payload).toEqual({ table: 'R4', status: 'OPEN' });
  });

  it('orderChanged is a no-op for non-guest orders', async () => {
    const { svc, sent } = build({ guestSessionId: null, tableId: 'tb1', guestSession: null });
    await svc.orderChanged('ord1');
    expect(sent).toEqual([]);
  });

  it('requestNew goes to the outlet and claimer rooms with a masked phone, and notifies confirmers', async () => {
    const { svc, sent, notices } = build();
    await svc.requestNew({
      requestId: 'r1', tenantId: 't1', outletId: 'o1', table: 'R4', by: 'Deepa', phone: '+919876543210',
      lines: [{ name: 'Lager', qty: 2, lineTotal: 500 }], total: 500, claimedById: 'u9',
    });
    expect(sent.map((s) => [s.room, s.event])).toEqual([['outlet:o1', 'guest.request.new'], ['user:u9', 'guest.request.new']]);
    expect(sent[0].payload).toMatchObject({ requestId: 'r1', table: 'R4', by: 'Deepa', phone: '+91 98•••••210', total: 500 });
    expect(JSON.stringify(sent)).not.toContain('9876543210');
    expect(notices.notify).toHaveBeenCalledWith(expect.objectContaining({ permissionKey: 'guests.orders.confirm', outletId: 'o1' }));
  });

  it('requestDecided, service requests and session close use the right events', async () => {
    const { svc, sent, notices } = build();
    await svc.requestDecided({ requestId: 'r1', outletId: 'o1', status: 'CONFIRMED' });
    await svc.serviceRequestNew({ id: 'sr1', tenantId: 't1', outletId: 'o1', table: 'R4', type: 'BILL' });
    await svc.serviceRequestUpdated({ id: 'sr1', tenantId: 't1', outletId: 'o1', table: 'R4', type: 'BILL', status: 'ACKNOWLEDGED', acknowledgedById: 'u2' });
    await svc.sessionClosed('s1', 'tb1');
    expect(sent.map((s) => [s.room, s.event])).toEqual([
      ['outlet:o1', 'guest.request.decided'],
      ['outlet:o1', 'service.request.new'],
      ['outlet:o1', 'service.request.updated'],
      ['user:u2', 'service.request.updated'],
      ['table:tb1', 'guest.session.closed'],
    ]);
    expect(sent[0].payload).toEqual({ requestId: 'r1', status: 'CONFIRMED' });
    expect(sent[1].payload).toEqual({ id: 'sr1', table: 'R4', type: 'BILL' });
    expect(notices.notify).toHaveBeenCalledWith(expect.objectContaining({ permissionKey: 'sales.orders.take', title: 'Bill requested · R4' }));
  });

  it('never throws into the caller', async () => {
    const { svc } = build();
    (svc as any).prisma.order.findUnique = async () => { throw new Error('db down'); };
    await expect(svc.orderChanged('x')).resolves.toBeUndefined();
  });
});

describe('maskPhone', () => {
  it('masks Indian mobiles', () => {
    expect(maskPhone('+919876543210')).toBe('+91 98•••••210');
    expect(maskPhone('9876543210')).toBe('+91 98•••••210');
    expect(maskPhone('123')).toBe('•••••');
    expect(maskPhone(null)).toBeNull();
  });
});

describe('GuestNotificationsService', () => {
  it('targets active outlet users holding the permission at EDIT, one row each', async () => {
    const prisma: any = {
      userOutlet: { findMany: jest.fn(async () => [{ userId: 'u1' }, { userId: 'u2' }]) },
      notification: { createMany: jest.fn(async () => ({ count: 2 })) },
    };
    const svc = new GuestNotificationsService(prisma);
    const users = await svc.notify({ tenantId: 't1', outletId: 'o1', permissionKey: 'guests.orders.confirm', type: 'guest_round', title: 'New QR order · R4' });
    expect(users).toEqual(['u1', 'u2']);
    expect(prisma.userOutlet.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: {
        outletId: 'o1',
        user: { tenantId: 't1', isActive: true },
        persona: { permissions: { some: { permissionKey: 'guests.orders.confirm', level: { in: ['EDIT'] } } } },
      },
    }));
    const rows = prisma.notification.createMany.mock.calls[0][0].data;
    expect(rows.map((r: any) => r.userId)).toEqual(['u1', 'u2']);
    expect(rows[0]).toMatchObject({ tenantId: 't1', outletId: 'o1', permissionKey: null, type: 'guest_round' });
  });

  it('creates nothing when nobody qualifies', async () => {
    const prisma: any = { userOutlet: { findMany: jest.fn(async () => []) }, notification: { createMany: jest.fn() } };
    expect(await new GuestNotificationsService(prisma).notify({ tenantId: 't', outletId: 'o', permissionKey: 'k', type: 'x', title: 'y' })).toEqual([]);
    expect(prisma.notification.createMany).not.toHaveBeenCalled();
  });
});

describe('NotConfiguredGateway', () => {
  it('throws 501 NOT_AVAILABLE', async () => {
    const g = new NotConfiguredGateway();
    for (const p of [g.createIntent('o1'), g.verifyWebhook({})]) {
      const err = await p.catch((e) => e);
      expect(err).toBeInstanceOf(HttpException);
      expect(err.getStatus()).toBe(501);
      expect(err.getResponse()).toMatchObject({ code: 'NOT_AVAILABLE' });
    }
  });
});
