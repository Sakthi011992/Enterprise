import { Injectable } from '@nestjs/common';
import { LoginMethod } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Data access for OAuth accounts and the users they link to. */
@Injectable()
export class OAuthRepository {
  constructor(private prisma: PrismaService) {}

  findAccountUser(provider: LoginMethod, providerUserId: string) {
    return this.prisma.oAuthAccount.findUnique({
      where: { provider_providerUserId: { provider, providerUserId } },
      include: { user: true },
    });
  }

  /** Active or deleted-filtered by the caller. Used to link a Google email to an existing user. */
  findUserByEmail(email: string) {
    return this.prisma.user.findFirst({ where: { email, deletedAt: null } });
  }

  /** The tenant that new OAuth users join. Phase 1 has one tenant in practice. */
  findDefaultTenant() {
    return this.prisma.tenant.findFirst({ where: { isActive: true }, orderBy: { createdAt: 'asc' } });
  }

  findRoleIdByName(name: string) {
    return this.prisma.role.findUnique({ where: { name }, select: { id: true } });
  }

  createUser(data: { tenantId: string; username: string; email?: string; roleId: string }) {
    return this.prisma.user.create({ data });
  }

  createAccount(data: { userId: string; provider: LoginMethod; providerUserId: string; email?: string }) {
    return this.prisma.oAuthAccount.create({ data });
  }
}
