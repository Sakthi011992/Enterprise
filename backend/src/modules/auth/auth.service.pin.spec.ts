import { HttpException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { AuthService, DeviceOutletContext } from './auth.service';
import { AuthRepository } from './auth.repository';
import { PermissionsService } from '../personas/permissions.service';
import { PersonasRepository } from '../personas/personas.repository';

const TENANT = 'tenant-1';
const OUTLET = 'outlet-1';
const USER = 'user-1';

function setup(initial: { failedAttempts?: number; lockedUntil?: Date | null } = {}) {
  // In-memory staff PIN row. The update mock writes into it so the service sees its own changes.
  const staffPin = {
    userId: USER,
    pinHash: bcrypt.hashSync('2580', 4),
    failedAttempts: initial.failedAttempts ?? 0,
    lockedUntil: initial.lockedUntil ?? null,
  };

  const outletRow = {
    outletId: OUTLET,
    personaId: 'persona-bar',
    isDefault: true,
    outlet: { id: OUTLET, name: 'Main outlet', code: 'MAIN', tenantId: TENANT, isActive: true },
    persona: { id: 'persona-bar', key: 'bartender', name: 'Bartender', homeRoute: '/pos', loginMethod: 'PIN', tenantId: TENANT },
    user: { id: USER, tenantId: TENANT, deletedAt: null, isActive: true },
  };

  const prisma: any = {
    userOutlet: {
      findUnique: jest.fn(async () => outletRow),
      findMany: jest.fn(async () => [outletRow]),
    },
    staffPin: {
      findUnique: jest.fn(async () => staffPin),
      update: jest.fn(async ({ data }: { data: Partial<typeof staffPin> }) => Object.assign(staffPin, data)),
    },
    user: {
      findFirst: jest.fn(async () => ({
        id: USER,
        username: 'bartender1',
        displayName: 'Bart',
        email: 'bart@example.com',
        tenantId: TENANT,
        tokenVersion: 0,
        isActive: true,
        deletedAt: null,
        tenant: { id: TENANT, name: 'Venue', isActive: true },
      })),
    },
    permission: { findMany: jest.fn(async () => []) },
    personaPermission: { findMany: jest.fn(async () => []) },
    userFeatureGrant: { findMany: jest.fn(async () => []) },
  };

  const config = new ConfigService({
    JWT_ACCESS_SECRET: 'access-secret',
    JWT_REFRESH_SECRET: 'refresh-secret',
    JWT_ACCESS_EXPIRES: '15m',
    JWT_REFRESH_EXPIRES: '7d',
  });
  const notifier = { notify: jest.fn() };
  const service = new AuthService(
    new AuthRepository(prisma as any),
    new JwtService({}),
    config,
    new PermissionsService(new PersonasRepository(prisma as any)),
    notifier,
  );

  const device: DeviceOutletContext = { tenantId: TENANT, outletId: OUTLET, outlet: { id: OUTLET, name: 'Main outlet' } };
  return { service, staffPin, device, prisma };
}

async function caught(promise: Promise<unknown>): Promise<HttpException> {
  try {
    await promise;
  } catch (err) {
    return err as HttpException;
  }
  throw new Error('expected the call to reject');
}

describe('AuthService.pinLogin', () => {
  it('reports attempts left after each wrong PIN, then locks for 5 minutes on the third', async () => {
    const { service, device } = setup();
    const dto = { userId: USER, pin: '0000' };

    const first = await caught(service.pinLogin(device, dto));
    expect(first.getStatus()).toBe(401);
    expect(first.getResponse()).toMatchObject({ code: 'PIN_INVALID', details: { attemptsLeft: 2 } });

    const second = await caught(service.pinLogin(device, dto));
    expect(second.getResponse()).toMatchObject({ code: 'PIN_INVALID', details: { attemptsLeft: 1 } });

    const third = await caught(service.pinLogin(device, dto));
    expect(third.getStatus()).toBe(423);
    const body = third.getResponse() as any;
    expect(body.code).toBe('PIN_LOCKED');
    expect(new Date(body.details.lockedUntil).getTime()).toBeGreaterThan(Date.now() + 4 * 60_000);
  });

  it('keeps refusing while locked, even with the right PIN', async () => {
    const { service, device } = setup({ failedAttempts: 3, lockedUntil: new Date(Date.now() + 60_000) });
    const err = await caught(service.pinLogin(device, { userId: USER, pin: '2580' }));
    expect(err.getStatus()).toBe(423);
    expect(err.getResponse()).toMatchObject({ code: 'PIN_LOCKED' });
  });

  it('starts a fresh set of attempts once the lock has expired', async () => {
    const { service, device, staffPin } = setup({ failedAttempts: 3, lockedUntil: new Date(Date.now() - 1_000) });
    const err = await caught(service.pinLogin(device, { userId: USER, pin: '0000' }));
    expect(err.getResponse()).toMatchObject({ code: 'PIN_INVALID', details: { attemptsLeft: 2 } });
    expect(staffPin.failedAttempts).toBe(1);
    expect(staffPin.lockedUntil).toBeNull();
  });

  it('a correct PIN resets the wrong-attempt counter and returns a session', async () => {
    const { service, device, staffPin } = setup();
    await caught(service.pinLogin(device, { userId: USER, pin: '0000' }));
    await caught(service.pinLogin(device, { userId: USER, pin: '0000' }));
    expect(staffPin.failedAttempts).toBe(2);

    const session: any = await service.pinLogin(device, { userId: USER, pin: '2580' });
    expect(typeof session.accessToken).toBe('string');
    expect(typeof session.refreshToken).toBe('string');
    expect(session.persona).toMatchObject({ key: 'bartender', homeRoute: '/pos' });
    expect(session.outlet).toMatchObject({ id: OUTLET, code: 'MAIN' });
    expect(staffPin.failedAttempts).toBe(0);

    const next = await caught(service.pinLogin(device, { userId: USER, pin: '0000' }));
    expect(next.getResponse()).toMatchObject({ details: { attemptsLeft: 2 } });
  });

  it('refuses a user who has no assignment at the device outlet', async () => {
    const { service, device, prisma } = setup();
    prisma.userOutlet.findUnique.mockResolvedValueOnce(null as any);
    const err = await caught(service.pinLogin(device, { userId: USER, pin: '2580' }));
    expect(err.getStatus()).toBe(403);
    expect(err.getResponse()).toMatchObject({ code: 'NO_OUTLET_ACCESS' });
  });
});
