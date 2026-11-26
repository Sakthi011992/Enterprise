import { HttpException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { JwtStrategy } from '../auth/jwt.strategy';
import { GuestAuthGuard } from './guest-auth.guard';
import { GuestJwtService } from './guest-jwt.service';

const config = new ConfigService({ GUEST_JWT_SECRET: 'guest-secret', JWT_ACCESS_SECRET: 'staff-secret' });
const jwt = new JwtService({});
const guestJwt = new GuestJwtService(jwt, config);

const claims = { sessionId: 's1', participantId: 'p1', tableId: 'tb1', outletId: 'o1', tenantId: 't1' };
const staffToken = jwt.sign(
  { sub: 'u1', username: 'waiter1', tenantId: 't1', outletId: 'o1', personaId: 'x', personaKey: 'waiter', tokenVersion: 0 },
  { secret: 'staff-secret', expiresIn: 900 },
);

function ctx(token?: string) {
  const req: any = { headers: token ? { authorization: `Bearer ${token}` } : {} };
  return { req, context: { switchToHttp: () => ({ getRequest: () => req }) } as any };
}
const codeOf = async (p: Promise<unknown>) => {
  try {
    await p;
  } catch (e) {
    return ((e as HttpException).getResponse() as any).code;
  }
  return 'OK';
};

describe('GuestAuthGuard', () => {
  let status: string | null;
  const repo: any = { sessionStatus: jest.fn(async () => status) };
  beforeEach(() => {
    status = 'OPEN';
    repo.sessionStatus.mockClear();
  });

  it('accepts a guest token for an open session and sets request.guest', async () => {
    const guard = new GuestAuthGuard(guestJwt, repo);
    const { req, context } = ctx(guestJwt.sign(claims));
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(req.guest).toEqual({ kind: 'guest', ...claims });
  });

  it('rejects a staff token on a guest route', async () => {
    const guard = new GuestAuthGuard(guestJwt, repo);
    expect(await codeOf(guard.canActivate(ctx(staffToken).context))).toBe('GUEST_TOKEN_INVALID');
  });

  it('rejects a token signed with the guest secret but without kind guest', async () => {
    const guard = new GuestAuthGuard(guestJwt, repo);
    const forged = jwt.sign({ ...claims, kind: 'staff' }, { secret: 'guest-secret' });
    expect(await codeOf(guard.canActivate(ctx(forged).context))).toBe('GUEST_TOKEN_INVALID');
  });

  it('rejects a missing token', async () => {
    const guard = new GuestAuthGuard(guestJwt, repo);
    expect(await codeOf(guard.canActivate(ctx().context))).toBe('GUEST_TOKEN_REQUIRED');
  });

  it('rejects a closed session, caching the session state for 30 s', async () => {
    const guard = new GuestAuthGuard(guestJwt, repo);
    const token = guestJwt.sign(claims);
    await guard.canActivate(ctx(token).context);
    await guard.canActivate(ctx(token).context);
    expect(repo.sessionStatus).toHaveBeenCalledTimes(1);
    status = 'CLOSED';
    guard.forget('s1');
    expect(await codeOf(guard.canActivate(ctx(token).context))).toBe('SESSION_CLOSED');
  });

  it('refuses to start when the guest secret equals the staff secret', () => {
    expect(() => new GuestJwtService(jwt, { get: () => 'same' } as any)).toThrow();
  });
});

describe('staff JwtStrategy', () => {
  it('rejects a guest token (wrong secret) at signature verification', () => {
    expect(() => jwt.verify(guestJwt.sign(claims), { secret: 'staff-secret' })).toThrow();
  });

  it('rejects any payload carrying kind, even if it were signed with the staff secret', async () => {
    const repo: any = { findActiveUser: jest.fn() };
    const strategy = new JwtStrategy(config, repo, {} as any);
    await expect(
      strategy.validate({ ...claims, kind: 'guest', sub: 'u1', username: 'x', personaId: 'p', personaKey: 'k', tokenVersion: 0 } as any),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    expect(repo.findActiveUser).not.toHaveBeenCalled();
  });
});
