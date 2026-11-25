import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { AccessLevel } from '../permissions/catalog';

export interface PermissionGrant {
  level: AccessLevel;
  limit: number | null;
}

/** Set by JwtStrategy.validate; available as request.user on authenticated routes. */
export interface AuthUser {
  userId: string;
  username: string;
  tenantId: string;
  outletId: string;
  personaId: string;
  personaKey: string;
  permissions: Record<string, PermissionGrant>;
  /** Legacy: 'ADMIN' for the admin persona, 'KIOSK' for the kiosk persona, otherwise 'USER'. */
  role: 'ADMIN' | 'USER' | 'KIOSK';
}

export const CurrentUser = createParamDecorator(
  (data: keyof AuthUser | undefined, ctx: ExecutionContext): AuthUser | any => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as AuthUser;
    return data ? user?.[data] : user;
  },
);
