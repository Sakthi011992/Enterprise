import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';

/** Claims of a guest token (PLAN 2.3). `kind: 'guest'` marks it; staff tokens never carry it. */
export interface GuestTokenClaims {
  kind: 'guest';
  sessionId: string;
  participantId: string;
  tableId: string;
  outletId: string;
  tenantId: string;
}

export const GUEST_TOKEN_TTL_SECONDS = 6 * 60 * 60;

/**
 * Signs and verifies guest tokens with GUEST_JWT_SECRET, a secret separate from the staff
 * JWT_ACCESS_SECRET, so neither kind of token validates on the other side.
 */
@Injectable()
export class GuestJwtService {
  private readonly secret: string;

  constructor(
    private jwt: JwtService,
    config: ConfigService,
  ) {
    const secret = config.get<string>('GUEST_JWT_SECRET');
    if (!secret) throw new Error('GUEST_JWT_SECRET is not set');
    if (secret === config.get<string>('JWT_ACCESS_SECRET') || secret === config.get<string>('JWT_REFRESH_SECRET')) {
      throw new Error('GUEST_JWT_SECRET must differ from the staff JWT secrets');
    }
    this.secret = secret;
  }

  sign(claims: Omit<GuestTokenClaims, 'kind'>): string {
    return this.jwt.sign({ ...claims, kind: 'guest' }, { secret: this.secret, expiresIn: GUEST_TOKEN_TTL_SECONDS });
  }

  /** Returns the claims, or null when the token is invalid, expired or not a guest token. */
  verify(token: string): GuestTokenClaims | null {
    try {
      const p = this.jwt.verify<GuestTokenClaims & { iat?: number; exp?: number }>(token, { secret: this.secret });
      if (!p || p.kind !== 'guest' || !p.sessionId || !p.participantId || !p.tableId || !p.outletId || !p.tenantId) {
        return null;
      }
      return {
        kind: 'guest',
        sessionId: p.sessionId,
        participantId: p.participantId,
        tableId: p.tableId,
        outletId: p.outletId,
        tenantId: p.tenantId,
      };
    } catch {
      return null;
    }
  }
}
