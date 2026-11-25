import { UnauthorizedException } from '@nestjs/common';
import { SocketAuthService } from './socket-auth.service';

function build(opts: { verify?: () => Promise<unknown>; user?: unknown; access?: unknown } = {}) {
  const jwt: any = { verifyAsync: jest.fn(opts.verify ?? (async () => payload)) };
  const config: any = { get: jest.fn(() => 'secret') };
  const authRepo: any = {
    findActiveUser: jest.fn(async () => (opts.user === undefined ? user : opts.user)),
    findUserOutletAccess: jest.fn(async () => (opts.access === undefined ? access : opts.access)),
  };
  const permissions: any = { forPersona: jest.fn(async () => ({ 'kds.bump': { level: 'EDIT', limit: null } })) };
  return { svc: new SocketAuthService(jwt, config, authRepo, permissions), jwt };
}

const payload = { sub: 'u1', username: 'chef', tenantId: 't1', outletId: 'o1', personaId: 'p1', personaKey: 'chef', tokenVersion: 3 };
const user = { id: 'u1', username: 'chef', tenantId: 't1', tokenVersion: 3 };
const access = { outletId: 'o1', personaId: 'p1', outlet: { isActive: true, tenantId: 't1' }, persona: { id: 'p1', key: 'chef' } };

describe('SocketAuthService', () => {
  it('rejects a handshake without a token', async () => {
    const { svc, jwt } = build();
    await expect(svc.authenticate(undefined, [])).rejects.toBeInstanceOf(UnauthorizedException);
    expect(jwt.verifyAsync).not.toHaveBeenCalled();
  });

  it('rejects a token that fails verification', async () => {
    const { svc } = build({ verify: async () => { throw new Error('invalid signature'); } });
    await expect(svc.authenticate('bad.token', [])).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an outlet-selection token', async () => {
    const { svc } = build({ verify: async () => ({ ...payload, purpose: 'outlet-select' }) });
    await expect(svc.authenticate('tok', [])).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a token issued before the user last signed out', async () => {
    const { svc } = build({ user: { ...user, tokenVersion: 4 } });
    await expect(svc.authenticate('tok', [])).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a user whose outlet access has been removed', async () => {
    const { svc } = build({ access: null });
    await expect(svc.authenticate('tok', [])).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('returns the AuthUser and only the string station names', async () => {
    const { svc } = build();
    const session = await svc.authenticate('tok', ['BAR', 42, '', 'BAR', 'KITCHEN']);
    expect(session.auth).toMatchObject({
      userId: 'u1',
      tenantId: 't1',
      outletId: 'o1',
      personaKey: 'chef',
      role: 'USER',
      permissions: { 'kds.bump': { level: 'EDIT', limit: null } },
    });
    expect(session.stations).toEqual(['BAR', 'KITCHEN']);
  });
});
