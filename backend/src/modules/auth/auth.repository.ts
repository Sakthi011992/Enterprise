import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TenantContext } from '../../common/tenancy/tenant-context';

/** Data access for login, sessions, outlet access, PINs, reset tokens and devices. */
@Injectable()
export class AuthRepository {
  constructor(private prisma: PrismaService) {}

  /** Active or not: the caller decides. Includes the tenant for the active check. */
  findUserByUsername(username: string) {
    return this.prisma.user.findFirst({
      where: { username, deletedAt: null },
      include: { tenant: true },
    });
  }

  /** Active, non-deleted user by id, with their tenant. */
  findActiveUserWithTenant(id: string) {
    return this.prisma.user.findFirst({
      where: { id, deletedAt: null, isActive: true },
      include: { tenant: true },
    });
  }

  /** Active, non-deleted user by id. Used on every authenticated request and on refresh. */
  findActiveUser(id: string) {
    return this.prisma.user.findFirst({ where: { id, deletedAt: null, isActive: true } });
  }

  /** Username or email match for password recovery. Only active accounts. */
  findUserForRecovery(usernameOrEmail: string) {
    return this.prisma.user.findFirst({
      where: {
        deletedAt: null,
        isActive: true,
        OR: [{ username: usernameOrEmail }, { email: usernameOrEmail }],
      },
    });
  }

  /** Bumps tokenVersion, which invalidates every outstanding refresh token for the user. */
  revokeTokens(userId: string) {
    return this.prisma.user.update({
      where: { id: userId },
      data: { tokenVersion: { increment: 1 } },
    });
  }

  /** Sets a new password hash and bumps tokenVersion. */
  setPasswordHash(userId: string, passwordHash: string) {
    return this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash, tokenVersion: { increment: 1 } },
    });
  }

  /** Every active outlet the user is assigned to in the tenant, with persona. */
  activeOutletRows(userId: string, tenantId: string) {
    return this.prisma.userOutlet.findMany({
      where: { userId, outlet: { tenantId, isActive: true } },
      include: { outlet: true, persona: true },
      orderBy: { outlet: { code: 'asc' } },
    });
  }

  /** The user's assignment at one outlet, with outlet and persona. */
  findUserOutletAccess(userId: string, outletId: string) {
    return this.prisma.userOutlet.findUnique({
      where: { userId_outletId: { userId, outletId } },
      include: { outlet: true, persona: true },
    });
  }

  /** Legacy feature grants (main). Deprecated. */
  async getFeatureGrants(userId: string): Promise<string[]> {
    const grants = await this.prisma.userFeatureGrant.findMany({ where: { userId } });
    return grants.map((g) => g.feature);
  }

  // Shared-tablet PIN login

  /** Users with a PIN and a PIN persona at this outlet. */
  findPinStaff(outletId: string, tenantId: string) {
    return this.prisma.userOutlet.findMany({
      where: {
        outletId,
        persona: { loginMethod: 'PIN' },
        user: { tenantId, deletedAt: null, isActive: true, staffPin: { isNot: null } },
      },
      include: {
        user: { select: { id: true, username: true, displayName: true } },
        persona: { select: { name: true } },
      },
    });
  }

  /** The assignment used by a PIN login at this outlet, with the persona and user. */
  findPinAccess(userId: string, outletId: string) {
    return this.prisma.userOutlet.findUnique({
      where: { userId_outletId: { userId, outletId } },
      include: { persona: true, user: true },
    });
  }

  findStaffPin(userId: string) {
    return this.prisma.staffPin.findUnique({ where: { userId } });
  }

  updateStaffPin(userId: string, data: { failedAttempts?: number; lockedUntil?: Date | null }) {
    return this.prisma.staffPin.update({ where: { userId }, data });
  }

  // Devices

  /**
   * Finds an active device by the sha256 of its key. The lookup runs as system because
   * the tenant is not known yet; the caller sets the tenant from the result.
   */
  findDeviceByKeyHash(keyHash: string) {
    return TenantContext.runAsSystem(() =>
      this.prisma.device.findFirst({
        where: { keyHash, isActive: true },
        include: { outlet: true },
      }),
    );
  }

  touchDevice(id: string) {
    return this.prisma.device.update({ where: { id }, data: { lastSeenAt: new Date() } });
  }

  // Password reset tokens

  /** Stores a new reset token and marks every older unused token for the user as used. */
  createResetToken(userId: string, tokenHash: string, expiresAt: Date) {
    return this.prisma.$transaction([
      this.prisma.passwordResetToken.updateMany({
        where: { userId, usedAt: null },
        data: { usedAt: new Date() },
      }),
      this.prisma.passwordResetToken.create({
        data: { userId, tokenHash, expiresAt },
      }),
    ]);
  }

  findResetTokenByHash(tokenHash: string) {
    return this.prisma.passwordResetToken.findUnique({ where: { tokenHash } });
  }

  /** Marks one token used if it is still unused. Returns the number of rows claimed (0 or 1). */
  async claimResetToken(id: string): Promise<number> {
    const result = await this.prisma.passwordResetToken.updateMany({
      where: { id, usedAt: null },
      data: { usedAt: new Date() },
    });
    return result.count;
  }

  invalidateResetTokens(userId: string) {
    return this.prisma.passwordResetToken.updateMany({
      where: { userId, usedAt: null },
      data: { usedAt: new Date() },
    });
  }
}
