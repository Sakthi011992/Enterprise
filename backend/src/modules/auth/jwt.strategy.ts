import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { ConfigService } from '@nestjs/config';
import { TenantContext } from '../../common/tenancy/tenant-context';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { PermissionsService } from '../personas/permissions.service';
import { AuthRepository } from './auth.repository';
import { legacyRoleFor } from './legacy-role';

export interface JwtPayload {
  sub: string;
  username: string;
  tenantId: string;
  outletId: string;
  personaId: string;
  personaKey: string;
  tokenVersion: number;
  /** Only set on the short-lived outlet selection token. Access tokens must not carry it. */
  purpose?: string;
  /** Guest tokens carry kind 'guest' (and a separate secret); they never authenticate staff routes. */
  kind?: string;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private repo: AuthRepository,
    private permissions: PermissionsService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_ACCESS_SECRET'),
    });
  }

  /**
   * Runs on every authenticated request. The live user and outlet assignment win over
   * the claims in the token, so removing access takes effect at once.
   */
  async validate(payload: JwtPayload): Promise<AuthUser> {
    if (!payload || payload.purpose || payload.kind || !payload.tenantId || !payload.outletId) {
      throw new UnauthorizedException('Invalid or revoked token');
    }

    const user = await this.repo.findActiveUser(payload.sub);
    if (!user || user.tokenVersion !== payload.tokenVersion || user.tenantId !== payload.tenantId) {
      throw new UnauthorizedException('Invalid or revoked token');
    }

    const access = await this.repo.findUserOutletAccess(user.id, payload.outletId);
    if (!access || !access.outlet.isActive || access.outlet.tenantId !== user.tenantId) {
      throw apiError(401, 'NO_OUTLET_ACCESS', 'Your access to this outlet has been removed');
    }

    TenantContext.set({ tenantId: user.tenantId, outletId: access.outletId, userId: user.id });
    const permissions = await this.permissions.forPersona(access.personaId);

    return {
      userId: user.id,
      username: user.username,
      tenantId: user.tenantId,
      outletId: access.outletId,
      personaId: access.persona.id,
      personaKey: access.persona.key,
      permissions,
      role: legacyRoleFor(access.persona.key),
    };
  }
}
