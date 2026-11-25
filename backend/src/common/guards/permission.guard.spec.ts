import { ExecutionContext, HttpException, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Can } from '../decorators/can.decorator';
import { Public } from '../decorators/public.decorator';
import { PermissionGuard } from './permission.guard';
import { PermissionsService } from '../../modules/personas/permissions.service';

class Routes {
  @Can('menu.edit', 'EDIT')
  writeMenu() {}

  @Can('menu.edit')
  readMenu() {}

  @Public()
  @Can('admin.users', 'EDIT')
  publicRoute() {}

  open() {}
}

const reflector = new Reflector();
const guard = new PermissionGuard(reflector, new PermissionsService({} as any));

function ctx(method: keyof Routes, user?: unknown): ExecutionContext {
  return {
    getHandler: () => Routes.prototype[method],
    getClass: () => Routes,
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  } as unknown as ExecutionContext;
}

const grants = (menu: { level: string; limit?: number | null }) => ({
  'menu.edit': { level: menu.level, limit: menu.limit ?? null },
});

async function codeOf(fn: () => boolean): Promise<{ status: number; code: string }> {
  try {
    fn();
  } catch (err) {
    const res = (err as HttpException).getResponse() as any;
    return { status: (err as HttpException).getStatus(), code: res.code };
  }
  throw new Error('expected the guard to throw');
}

describe('PermissionGuard', () => {
  it('lets routes without @Can through for any authenticated user', () => {
    expect(guard.canActivate(ctx('open', { permissions: {} }))).toBe(true);
  });

  it('lets public routes through without a user', () => {
    expect(guard.canActivate(ctx('publicRoute'))).toBe(true);
  });

  it('allows a grant at or above the required level', () => {
    expect(guard.canActivate(ctx('writeMenu', { permissions: grants({ level: 'EDIT' }) }))).toBe(true);
    expect(guard.canActivate(ctx('readMenu', { permissions: grants({ level: 'VIEW' }) }))).toBe(true);
  });

  it('denies a grant below the required level with PERMISSION_DENIED', async () => {
    const result = await codeOf(() => guard.canActivate(ctx('writeMenu', { permissions: grants({ level: 'LIMITED', limit: 5 }) })));
    expect(result).toEqual({ status: 403, code: 'PERMISSION_DENIED' });
  });

  it('denies when the persona has no row for the key (NONE)', async () => {
    const result = await codeOf(() => guard.canActivate(ctx('readMenu', { permissions: {} })));
    expect(result).toEqual({ status: 403, code: 'PERMISSION_DENIED' });
  });

  it('rejects a missing user on a protected route', () => {
    expect(() => guard.canActivate(ctx('writeMenu', undefined))).toThrow(UnauthorizedException);
  });
});
