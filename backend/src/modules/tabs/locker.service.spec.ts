import { HttpException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { LockerService } from './locker.service';
import { AuthUser } from '../../common/decorators/current-user.decorator';

const D = (v: number | string) => new Prisma.Decimal(v);
const codeOf = (e: unknown) => (e as HttpException).getResponse() as { code: string; details?: Record<string, unknown> };
const auth = { userId: 'u1', tenantId: 't1', outletId: 'o1', permissions: {} } as unknown as AuthUser;

function entry(over: Record<string, unknown> = {}) {
  return {
    id: 'lk1', tenantId: 't1', outletId: 'o1', guestName: 'Vikram S', mobile: null, cardLast4: '7720', stockItemId: null,
    bottleName: 'Single Malt 12Y 750 ml', bottleMl: 750, remainingMl: 610, storedAt: new Date('2026-11-20T10:00:00Z'),
    expiresAt: new Date('2026-12-31'), status: 'ACTIVE', orderItemId: null, note: null, createdById: 'u1',
    events: [{ kind: 'STORE', ml: 610, byId: 'u1', note: 'Stored', createdAt: new Date('2026-11-20T10:00:00Z') }],
    ...over,
  };
}

function build(start = entry()) {
  const state = { entry: start as any, events: [] as any[] };
  const repo: any = {
    transaction: (fn: (tx: unknown) => unknown) => fn({}),
    findEntry: jest.fn(async () => state.entry),
    addEvent: jest.fn(async (_tx: unknown, data: any) => {
      state.events.push(data);
      return data;
    }),
    updateEntry: jest.fn(async (_tx: unknown, _id: string, data: any) => {
      state.entry = { ...state.entry, ...data, events: [...state.entry.events, ...state.events.map((e) => ({ ...e, createdAt: new Date() }))] };
      state.events = [];
      return state.entry;
    }),
    userNames: jest.fn(async () => new Map([['u1', 'Meera']])),
  };
  const ordersRepo: any = { getOutletTimezone: jest.fn(async () => 'Asia/Kolkata') };
  return { svc: new LockerService(repo, ordersRepo), repo, state };
}

describe('LockerService.serve', () => {
  it('serves ml and leaves the rest on the bottle, with a SERVE event', async () => {
    const { svc, repo } = build();
    const view = await svc.serve('lk1', { ml: 60 }, auth);
    expect(repo.addEvent).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ kind: 'SERVE', ml: 60 }));
    expect(view.remainingMl).toBe(550);
    expect(view.status).toBe('ACTIVE');
    expect(view.guestLabel).toBe('Vikram S · ••7720');
  });

  it('refuses more than is left', async () => {
    const { svc } = build();
    const err = await svc.serve('lk1', { ml: 700 }, auth).catch((e) => e);
    expect(codeOf(err).code).toBe('NOT_ENOUGH_LEFT');
    expect(codeOf(err).details).toEqual({ remainingMl: 610 });
  });

  it('finishes the entry when the last ml is served', async () => {
    const { svc } = build(entry({ remainingMl: 60 }));
    const view = await svc.serve('lk1', { ml: 60 }, auth);
    expect(view.remainingMl).toBe(0);
    expect(view.status).toBe('FINISHED');
  });

  it('refuses a bottle past its locker date', async () => {
    const { svc } = build(entry({ expiresAt: new Date('2020-01-01') }));
    const err = await svc.serve('lk1', { ml: 60 }, auth).catch((e) => e);
    expect(codeOf(err).code).toBe('LOCKER_EXPIRED');
  });
});

describe('LockerService.create', () => {
  it('refuses remaining ml above the bottle size', async () => {
    const { svc } = build();
    const err = await svc
      .create({ guestName: 'Vikram S', bottleName: 'Gin 750 ml', bottleMl: 750, remainingMl: 800, expiresAt: '2026-12-31' }, auth)
      .catch((e) => e);
    expect(codeOf(err).code).toBe('INVALID_ML');
  });
});

describe('LockerService.update', () => {
  it('writes an ADJUST event for a changed volume and finishes the bottle at zero', async () => {
    const { svc, repo } = build();
    const view = await svc.update('lk1', { remainingMl: 0 }, auth);
    expect(repo.addEvent).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ kind: 'ADJUST', ml: -610 }));
    expect(view.status).toBe('FINISHED');
  });
});
