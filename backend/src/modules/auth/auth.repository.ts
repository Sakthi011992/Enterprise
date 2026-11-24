import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class AuthRepository {
  constructor(private prisma: PrismaService) {}

  findUserByUsername(username: string) {
    return this.prisma.user.findFirst({
      where: { username, deletedAt: null },
      include: { role: true },
    });
  }

  findUserById(id: string) {
    return this.prisma.user.findUnique({
      where: { id },
      include: { role: true },
    });
  }

  findActiveUserById(id: string) {
    return this.prisma.user.findFirst({
      where: { id, deletedAt: null, isActive: true },
      include: { role: true },
    });
  }

  revokeTokens(userId: string) {
    return this.prisma.user.update({
      where: { id: userId },
      data: { tokenVersion: { increment: 1 } },
    });
  }

  getFeatureGrants(userId: string) {
    return this.prisma.userFeatureGrant.findMany({ where: { userId } });
  }
}
