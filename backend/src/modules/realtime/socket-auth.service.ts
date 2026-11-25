import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { AuthRepository } from '../auth/auth.repository';
import { JwtPayload } from '../auth/jwt.strategy';
import { legacyRoleFor } from '../auth/legacy-role';
import { PermissionsService } from '../personas/permissions.service';

export interface SocketSession {
  auth: AuthUser;
  /** Station names the client asked for in the handshake (strings only). */
  stations: string[];
}

/**
 * Checks the access token sent in the socket handshake (`auth.token`). It verifies the signature with the
 * same secret as JwtStrategy, then applies the same live-user, token-version and outlet checks, so a socket
 * cannot outlive a revoked login.
 */
@Injectable()
export class SocketAuthService {
  constructor(
    private jwt: JwtService,
    private config: ConfigService,
    private authRepo: AuthRepository,
    private permissions: PermissionsService,
  ) {}

  async authenticate(token: unknown, stations: unknown): Promise<SocketSession> {
    if (typeof token !== 'string' || token.length === 0) throw new UnauthorizedException('Missing token');

    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(token, { secret: this.config.get<string>('JWT_ACCESS_SECRET') });
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }
    return this.toSession(payload, stations);
  }

  /** Same rule as JwtStrategy.validate: the live user and outlet assignment win over the token claims. */
  async toSession(payload: JwtPayload, stations: unknown): Promise<SocketSession> {
    if (!payload || payload.purpose || !payload.tenantId || !payload.outletId) {
      throw new UnauthorizedException('Invalid or revoked token');
    }

    const user = await this.authRepo.findActiveUser(payload.sub);
    if (!user || user.tokenVersion !== payload.tokenVersion || user.tenantId !== payload.tenantId) {
      throw new UnauthorizedException('Invalid or revoked token');
    }

    const access = await this.authRepo.findUserOutletAccess(user.id, payload.outletId);
    if (!access || !access.outlet.isActive || access.outlet.tenantId !== user.tenantId) {
      throw new UnauthorizedException('Your access to this outlet has been removed');
    }

    const permissions = await this.permissions.forPersona(access.personaId);
    const auth: AuthUser = {
      userId: user.id,
      username: user.username,
      tenantId: user.tenantId,
      outletId: access.outletId,
      personaId: access.persona.id,
      personaKey: access.persona.key,
      permissions,
      role: legacyRoleFor(access.persona.key),
    };

    const list = Array.isArray(stations) ? stations.filter((s): s is string => typeof s === 'string' && s.length > 0 && s.length <= 40) : [];
    return { auth, stations: [...new Set(list)] };
  }
}
