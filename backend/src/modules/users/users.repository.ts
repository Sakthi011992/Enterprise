import { Injectable } from '@nestjs/common';
import { Prisma, AppFeature } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const SAFE_SELECT = {
  id: true,
  username: true,
  isActive: true,
  createdAt: true,
  updatedAt: true,
  role: { select: { id: true, name: true } },
  featureGrants: { select: { feature: true } },
} satisfies Prisma.UserSelect;

@Injectable()
export class UsersRepository {
  constructor(private prisma: PrismaService) {}

  findAll() {
    return this.prisma.user.findMany({
      where: { deletedAt: null },
      select: SAFE_SELECT,
      orderBy: { createdAt: 'desc' },
    });
  }

  findById(id: string) {
    return this.prisma.user.findFirst({
      where: { id, deletedAt: null },
      select: SAFE_SELECT,
    });
  }

  findByUsername(username: string) {
    return this.prisma.user.findFirst({
      where: { username, deletedAt: null },
    });
  }

  create(data: { username: string; passwordHash: string; roleId: string }) {
    return this.prisma.user.create({
      data,
      select: SAFE_SELECT,
    });
  }

  updatePassword(id: string, passwordHash: string) {
    return this.prisma.user.update({
      where: { id },
      data: { passwordHash, tokenVersion: { increment: 1 } },
      select: SAFE_SELECT,
    });
  }

  setActive(id: string, isActive: boolean) {
    return this.prisma.user.update({
      where: { id },
      data: { isActive },
      select: SAFE_SELECT,
    });
  }

  softDelete(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
  }

  getFeatures(userId: string) {
    return this.prisma.userFeatureGrant.findMany({ where: { userId } });
  }

  async setFeatures(userId: string, features: AppFeature[]) {
    await this.prisma.userFeatureGrant.deleteMany({ where: { userId } });
    if (features.length > 0) {
      await this.prisma.userFeatureGrant.createMany({
        data: features.map((feature) => ({ userId, feature })),
      });
    }
    return this.prisma.userFeatureGrant.findMany({ where: { userId } });
  }

  findDefaultRole() {
    return this.prisma.role.findFirst({ where: { name: 'USER' } });
  }
}
