import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import { randomBytes } from 'crypto';
import { apiError } from '../../common/filters/api-error';
import { AuthUser, PermissionGrant } from '../../common/decorators/current-user.decorator';
import { PermissionsService } from '../personas/permissions.service';
import { AuthRepository } from './auth.repository';
import { JwtPayload } from './jwt.strategy';
import { hashToken } from './token.util';
import { legacyRoleFor } from './legacy-role';
import { PASSWORD_RESET_NOTIFIER, PasswordResetNotifier } from './password-reset.notifier';
import { PinLoginDto } from './dto/auth.dto';

const MAX_PIN_ATTEMPTS = 3;
const PIN_LOCK_MS = 5 * 60_000;
const RESET_TOKEN_TTL_MS = 30 * 60_000;
const SELECTION_TOKEN_TTL = '5m';

/** The device resolved from X-Device-Key, with the fields a PIN login needs. */
export interface DeviceOutletContext {
  tenantId: string;
  outletId: string;
  outlet: { id: string; name: string };
}

@Injectable()
export class AuthService {
  constructor(
    private repo: AuthRepository,
    private jwt: JwtService,
    private config: ConfigService,
    private permissions: PermissionsService,
    @Inject(PASSWORD_RESET_NOTIFIER) private notifier: PasswordResetNotifier,
  ) {}

  // ---------------------------------------------------------------------------
  // Password login, outlet selection, session
  // ---------------------------------------------------------------------------

  async login(username: string, password: string) {
    const user = await this.repo.findUserByUsername(username);
    if (!user || !user.isActive || user.deletedAt || !user.tenant.isActive || !user.passwordHash) {
      throw apiError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');
    }
    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw apiError(401, 'INVALID_CREDENTIALS', 'Invalid credentials');

    return this.completeLogin(user.id, user.tenantId);
  }

  /**
   * Shared by password and OAuth login. Picks the outlet when the user has exactly one
   * assignment or exactly one default. Otherwise returns needsOutlet with a selection token.
   */
  async completeLogin(userId: string, tenantId: string) {
    const rows = await this.repo.activeOutletRows(userId, tenantId);
    if (rows.length === 0) {
      throw apiError(403, 'NO_OUTLET_ACCESS', 'No outlet is assigned to this user');
    }

    const defaults = rows.filter((r) => r.isDefault);
    const chosen = rows.length === 1 ? rows[0] : defaults.length === 1 ? defaults[0] : null;
    if (!chosen) {
      return {
        needsOutlet: true as const,
        selectionToken: await this.signSelectionToken(userId),
        outlets: rows.map((r) => this.outletSummary(r)),
      };
    }
    return this.buildSession(userId, chosen.outletId, true);
  }

  async selectOutlet(selectionToken: string, outletId: string) {
    let payload: { sub: string; purpose?: string };
    try {
      payload = await this.jwt.verifyAsync(selectionToken, {
        secret: this.config.get('JWT_ACCESS_SECRET'),
      });
    } catch {
      throw apiError(401, 'SELECTION_EXPIRED', 'Outlet selection expired. Sign in again.');
    }
    if (payload.purpose !== 'outlet-select') {
      throw apiError(401, 'SELECTION_EXPIRED', 'Outlet selection expired. Sign in again.');
    }
    return this.buildSession(payload.sub, outletId, true);
  }

  async switchOutlet(auth: AuthUser, outletId: string) {
    return this.buildSession(auth.userId, outletId, true);
  }

  async refresh(refreshToken: string) {
    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync(refreshToken, {
        secret: this.config.get('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }

    const user = await this.repo.findActiveUser(payload.sub);
    if (!user || user.tokenVersion !== payload.tokenVersion || user.tenantId !== payload.tenantId) {
      throw new UnauthorizedException('Refresh token revoked');
    }
    const access = await this.repo.findUserOutletAccess(user.id, payload.outletId);
    if (!access || !access.outlet.isActive || access.outlet.tenantId !== user.tenantId) {
      throw new UnauthorizedException('Refresh token revoked');
    }

    const accessToken = await this.signAccessToken({
      sub: user.id,
      username: user.username,
      tenantId: user.tenantId,
      outletId: access.outletId,
      personaId: access.persona.id,
      personaKey: access.persona.key,
      tokenVersion: user.tokenVersion,
    });
    return { accessToken };
  }

  /** Revokes every refresh token by bumping tokenVersion. */
  async logout(userId: string) {
    await this.repo.revokeTokens(userId);
    return { success: true };
  }

  async me(auth: AuthUser) {
    return this.buildSession(auth.userId, auth.outletId, false);
  }

  /** Session payload used by every login path (PLAN 1.5). Tokens are added when withTokens is true. */
  async buildSession(userId: string, outletId: string, withTokens: boolean) {
    const user = await this.repo.findActiveUserWithTenant(userId);
    if (!user || !user.tenant.isActive) throw new UnauthorizedException('Session is no longer valid');

    const access = await this.repo.findUserOutletAccess(userId, outletId);
    if (!access || !access.outlet.isActive || access.outlet.tenantId !== user.tenantId) {
      throw apiError(403, 'NO_OUTLET_ACCESS', 'You do not have access to this outlet');
    }

    const permissions: Record<string, PermissionGrant> = await this.permissions.forPersona(access.persona.id);
    const outlets = (await this.repo.activeOutletRows(user.id, user.tenantId)).map((r) => this.outletSummary(r));
    const features = await this.repo.getFeatureGrants(user.id);

    const session = {
      user: {
        id: user.id,
        username: user.username,
        displayName: user.displayName ?? user.username,
        email: user.email,
        features,
      },
      tenant: { id: user.tenant.id, name: user.tenant.name },
      outlet: { id: access.outlet.id, name: access.outlet.name, code: access.outlet.code },
      persona: {
        id: access.persona.id,
        key: access.persona.key,
        name: access.persona.name,
        homeRoute: access.persona.homeRoute,
      },
      permissions,
      outlets,
      role: legacyRoleFor(access.persona.key),
    };
    if (!withTokens) return session;

    const claims: JwtPayload = {
      sub: user.id,
      username: user.username,
      tenantId: user.tenantId,
      outletId: access.outletId,
      personaId: access.persona.id,
      personaKey: access.persona.key,
      tokenVersion: user.tokenVersion,
    };
    const accessToken = await this.signAccessToken(claims);
    const refreshToken = await this.jwt.signAsync(claims, {
      secret: this.config.get('JWT_REFRESH_SECRET'),
      expiresIn: this.config.get('JWT_REFRESH_EXPIRES', '7d'),
    });
    return { accessToken, refreshToken, ...session };
  }

  // ---------------------------------------------------------------------------
  // Forgot / reset password
  // ---------------------------------------------------------------------------

  async forgotPassword(usernameOrEmail: string) {
    const user = await this.repo.findUserForRecovery(usernameOrEmail);
    if (user) {
      const raw = randomBytes(32).toString('base64url');
      await this.repo.createResetToken(user.id, hashToken(raw), new Date(Date.now() + RESET_TOKEN_TTL_MS));
      const base = this.config.get<string>('APP_BASE_URL', 'http://localhost:5173');
      await this.notifier.notify(
        { userId: user.id, username: user.username, email: user.email },
        `${base}/reset-password?token=${raw}`,
      );
    }
    // Always the same answer, so the endpoint does not reveal which accounts exist.
    return { success: true };
  }

  async resetPassword(token: string, newPassword: string) {
    const record = await this.repo.findResetTokenByHash(hashToken(token));
    if (!record || record.usedAt || record.expiresAt.getTime() <= Date.now()) {
      throw apiError(400, 'RESET_TOKEN_INVALID', 'This reset link is invalid or has expired');
    }

    // Claim the token first so two concurrent requests cannot both succeed.
    if ((await this.repo.claimResetToken(record.id)) !== 1) {
      throw apiError(400, 'RESET_TOKEN_INVALID', 'This reset link is invalid or has expired');
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await this.repo.setPasswordHash(record.userId, passwordHash);
    await this.repo.invalidateResetTokens(record.userId);
    return { success: true };
  }

  // ---------------------------------------------------------------------------
  // Shared tablet PIN login
  // ---------------------------------------------------------------------------

  async pinStaff(device: DeviceOutletContext) {
    const rows = await this.repo.findPinStaff(device.outletId, device.tenantId);

    const staff = rows
      .map((r) => ({
        userId: r.user.id,
        displayName: r.user.displayName ?? r.user.username,
        personaName: r.persona.name,
      }))
      .sort((a, b) => a.displayName.localeCompare(b.displayName));

    return { outlet: { id: device.outlet.id, name: device.outlet.name }, staff };
  }

  async pinLogin(device: DeviceOutletContext, dto: PinLoginDto) {
    const access = await this.repo.findPinAccess(dto.userId, device.outletId);
    if (
      !access ||
      access.persona.loginMethod !== 'PIN' ||
      access.user.tenantId !== device.tenantId ||
      access.user.deletedAt !== null ||
      !access.user.isActive
    ) {
      throw apiError(403, 'NO_OUTLET_ACCESS', 'This user cannot sign in on this device');
    }

    const staffPin = await this.repo.findStaffPin(dto.userId);
    if (!staffPin) throw apiError(401, 'PIN_INVALID', 'Incorrect PIN');

    const now = new Date();
    if (staffPin.lockedUntil && staffPin.lockedUntil > now) {
      throw this.lockedError(staffPin.lockedUntil);
    }
    // An expired lock starts a fresh cycle of attempts.
    let failed = staffPin.lockedUntil ? 0 : staffPin.failedAttempts;

    const ok = await bcrypt.compare(dto.pin, staffPin.pinHash);
    if (ok) {
      await this.repo.updateStaffPin(dto.userId, { failedAttempts: 0, lockedUntil: null });
      return this.buildSession(dto.userId, device.outletId, true);
    }

    failed += 1;
    if (failed >= MAX_PIN_ATTEMPTS) {
      const lockedUntil = new Date(now.getTime() + PIN_LOCK_MS);
      await this.repo.updateStaffPin(dto.userId, { failedAttempts: failed, lockedUntil });
      throw this.lockedError(lockedUntil);
    }
    await this.repo.updateStaffPin(dto.userId, { failedAttempts: failed, lockedUntil: null });
    throw apiError(401, 'PIN_INVALID', 'Incorrect PIN', { attemptsLeft: MAX_PIN_ATTEMPTS - failed });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  private lockedError(lockedUntil: Date) {
    return apiError(423, 'PIN_LOCKED', 'Too many wrong PINs. Try again later.', {
      lockedUntil: lockedUntil.toISOString(),
    });
  }

  private outletSummary(row: {
    outlet: { id: string; name: string; code: string };
    persona: { key: string; name: string };
    isDefault: boolean;
  }) {
    return {
      id: row.outlet.id,
      name: row.outlet.name,
      code: row.outlet.code,
      persona: { key: row.persona.key, name: row.persona.name },
      isDefault: row.isDefault,
    };
  }

  private signAccessToken(claims: JwtPayload) {
    return this.jwt.signAsync(claims, {
      secret: this.config.get('JWT_ACCESS_SECRET'),
      expiresIn: this.config.get('JWT_ACCESS_EXPIRES', '15m'),
    });
  }

  private signSelectionToken(userId: string) {
    return this.jwt.signAsync(
      { sub: userId, purpose: 'outlet-select' },
      { secret: this.config.get('JWT_ACCESS_SECRET'), expiresIn: SELECTION_TOKEN_TTL },
    );
  }
}
