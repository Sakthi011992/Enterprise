import { applyDecorators, CanActivate, ExecutionContext, Injectable, UseGuards } from '@nestjs/common';
import { ApiBearerAuth } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { apiError } from '../../common/filters/api-error';
import { TenantContext } from '../../common/tenancy/tenant-context';
import { GuestAuthRepository } from './guest-auth.repository';
import { GuestJwtService, GuestTokenClaims } from './guest-jwt.service';

/** request.guest on guest routes. Same fields as the token claims. */
export type GuestPrincipal = GuestTokenClaims;

const SESSION_CACHE_MS = 30_000;

/**
 * Accepts only guest tokens (`kind: 'guest'`, signed with GUEST_JWT_SECRET). Staff JWTs fail here
 * because they are signed with another secret and carry no `kind`. The session must still be OPEN
 * (checked against the database, cached for 30 s), so closing a session revokes its tokens.
 */
@Injectable()
export class GuestAuthGuard implements CanActivate {
  private sessionCache = new Map<string, { open: boolean; at: number }>();

  constructor(
    private jwt: GuestJwtService,
    private repo: GuestAuthRepository,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();
    const header: string | undefined = req.headers?.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7).trim() : null;
    if (!token) throw apiError(401, 'GUEST_TOKEN_REQUIRED', 'Scan the table QR code to start');

    const claims = this.jwt.verify(token);
    if (!claims) throw apiError(401, 'GUEST_TOKEN_INVALID', 'Your table session has expired. Scan the QR code again.');

    if (!(await this.isSessionOpen(claims.sessionId))) {
      throw apiError(401, 'SESSION_CLOSED', "This table's session has ended");
    }

    req.guest = claims;
    TenantContext.set({ tenantId: claims.tenantId, outletId: claims.outletId });
    return true;
  }

  /** Drops the cached state, e.g. right after G-B closes a session. */
  forget(sessionId: string) {
    this.sessionCache.delete(sessionId);
  }

  private async isSessionOpen(sessionId: string): Promise<boolean> {
    const hit = this.sessionCache.get(sessionId);
    if (hit && Date.now() - hit.at < SESSION_CACHE_MS) return hit.open;
    const status = await this.repo.sessionStatus(sessionId);
    const open = status === 'OPEN';
    this.sessionCache.set(sessionId, { open, at: Date.now() });
    return open;
  }
}

/**
 * Marks a controller or handler as a guest route: skips the global staff JWT guard and runs
 * GuestAuthGuard instead. Use with @CurrentGuest().
 */
export const GuestRoute = () => applyDecorators(Public(), UseGuards(GuestAuthGuard), ApiBearerAuth());
