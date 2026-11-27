import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { PrismaService } from '../../prisma/prisma.service';

/** Claims of a guest token (same shape as guest-auth GuestTokenClaims, PLAN 2.3). */
export interface GuestSocketSession {
  kind: 'guest';
  sessionId: string;
  participantId: string;
  tableId: string;
  outletId: string;
  tenantId: string;
}

/**
 * Checks a guest token sent in the socket handshake. It verifies with GUEST_JWT_SECRET only (never the staff
 * secret), requires `kind: 'guest'` and every claim, and requires the guest session to still be OPEN.
 */
@Injectable()
export class GuestSocketAuthService {
  constructor(
    private jwt: JwtService,
    private config: ConfigService,
    private prisma: PrismaService,
  ) {}

  /** True when the token claims to be a guest token. Unverified: it only picks which check runs. */
  static looksLikeGuest(jwt: JwtService, token: unknown): boolean {
    if (typeof token !== 'string' || token.length === 0) return false;
    try {
      const p = jwt.decode(token) as { kind?: unknown } | null;
      return !!p && typeof p === 'object' && p.kind === 'guest';
    } catch {
      return false;
    }
  }

  async authenticate(token: unknown): Promise<GuestSocketSession> {
    if (typeof token !== 'string' || token.length === 0) throw new UnauthorizedException('Missing token');
    const secret = this.config.get<string>('GUEST_JWT_SECRET');
    if (!secret || secret === this.config.get<string>('JWT_ACCESS_SECRET')) {
      throw new UnauthorizedException('Guest sockets are not configured');
    }

    let p: Partial<GuestSocketSession> | null;
    try {
      p = await this.jwt.verifyAsync<GuestSocketSession>(token, { secret });
    } catch {
      throw new UnauthorizedException('Invalid or expired token');
    }
    if (!p || p.kind !== 'guest' || !p.sessionId || !p.participantId || !p.tableId || !p.outletId || !p.tenantId) {
      throw new UnauthorizedException('Invalid guest token');
    }

    const session = await this.prisma.guestSession.findFirst({
      where: { id: p.sessionId, tenantId: p.tenantId, tableId: p.tableId },
      select: { status: true },
    });
    if (!session || session.status !== 'OPEN') throw new UnauthorizedException('Session closed');

    return {
      kind: 'guest',
      sessionId: p.sessionId,
      participantId: p.participantId,
      tableId: p.tableId,
      outletId: p.outletId,
      tenantId: p.tenantId,
    };
  }
}
