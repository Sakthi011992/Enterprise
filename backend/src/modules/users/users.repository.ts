import { Injectable } from '@nestjs/common';
import { AppFeature, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

export const USER_SELECT = {
  id: true,
  username: true,
  email: true,
  displayName: true,
  phone: true,
  isActive: true,
  createdAt: true,
  updatedAt: true,
  role: { select: { id: true, name: true } },
  featureGrants: { select: { feature: true } },
  userOutlets: {
    select: {
      outletId: true,
      personaId: true,
      isDefault: true,
      outlet: { select: { name: true } },
      persona: { select: { name: true } },
    },
  },
  staffPin: { select: { userId: true } },
} satisfies Prisma.UserSelect;

export type UserRow = Prisma.UserGetPayload<{ select: typeof USER_SELECT }>;

export interface UserCreateData {
  tenantId: string;
  username: string;
  email?: string;
  passwordHash: string;
  roleId: string;
  displayName?: string;
  phone?: string;
  outlet?: { outletId: string; personaId: string };
}

export interface UserUpdateData {
  email?: string;
  displayName?: string;
  phone?: string;
  isActive?: boolean;
  roleId?: string;
  passwordHash?: string;
}

export interface OutletAssignment {
  outletId: string;
  personaId: string;
  isDefault: boolean;
}

/** Data access for users, their outlet assignments, PINs and legacy feature grants. */
@Injectable()
export class UsersRepository {
  constructor(private prisma: PrismaService) {}

  async listForTenant(tenantId: string, search: string | undefined, skip: number, take: number) {
    const where: Prisma.UserWhereInput = {
      tenantId,
      deletedAt: null,
      ...(search ? { OR: [{ username: { contains: search, mode: 'insensitive' as const } }] } : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({ where, select: USER_SELECT, skip, take, orderBy: { createdAt: 'desc' } }),
      this.prisma.user.count({ where }),
    ]);
    return { rows, total };
  }

  findOwned(id: string, tenantId: string) {
    return this.prisma.user.findFirst({ where: { id, tenantId, deletedAt: null }, select: USER_SELECT });
  }

  /** Lookup by id for the owning tenant, without the joins. Used for existence checks. */
  async existsOwned(id: string, tenantId: string): Promise<boolean> {
    const row = await this.prisma.user.findFirst({ where: { id, tenantId, deletedAt: null }, select: { id: true } });
    return row !== null;
  }

  async roleIdByName(name: string): Promise<string | null> {
    const role = await this.prisma.role.findUnique({ where: { name }, select: { id: true } });
    return role?.id ?? null;
  }

  async personaIdByKey(tenantId: string, key: string): Promise<string | null> {
    const persona = await this.prisma.persona.findFirst({ where: { tenantId, key }, select: { id: true } });
    return persona?.id ?? null;
  }

  /** The tenant's first active outlet, used as the starting outlet for new users. */
  async firstActiveOutletId(tenantId: string): Promise<string | null> {
    const outlet = await this.prisma.outlet.findFirst({
      where: { tenantId, isActive: true },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return outlet?.id ?? null;
  }

  /** Creates the user, with an optional starting outlet assignment, and returns the safe row. */
  async create(data: UserCreateData) {
    const { outlet, ...rest } = data;
    return this.prisma.user.create({
      data: {
        ...rest,
        ...(outlet
          ? { userOutlets: { create: { outletId: outlet.outletId, personaId: outlet.personaId, isDefault: true } } }
          : {}),
      },
      select: USER_SELECT,
    });
  }

  /** Writes the user row. Password changes also bump tokenVersion so old refresh tokens stop working. */
  update(id: string, data: UserUpdateData) {
    const { roleId, ...rest } = data;
    return this.prisma.user.update({
      where: { id },
      data: {
        ...rest,
        ...(roleId ? { role: { connect: { id: roleId } } } : {}),
        ...(data.passwordHash !== undefined ? { tokenVersion: { increment: 1 } } : {}),
      },
      select: USER_SELECT,
    });
  }

  softDelete(id: string) {
    return this.prisma.user.update({ where: { id }, data: { deletedAt: new Date(), isActive: false } });
  }

  upsertPin(userId: string, pinHash: string) {
    return this.prisma.staffPin.upsert({
      where: { userId },
      create: { userId, pinHash, failedAttempts: 0, lockedUntil: null },
      update: { pinHash, failedAttempts: 0, lockedUntil: null },
    });
  }

  async countOutletsIn(outletIds: string[], tenantId: string): Promise<number> {
    return this.prisma.outlet.count({ where: { tenantId, id: { in: outletIds } } });
  }

  async countPersonasIn(personaIds: string[], tenantId: string): Promise<number> {
    return this.prisma.persona.count({ where: { tenantId, id: { in: personaIds } } });
  }

  /** Replaces all outlet assignments for a user in one transaction. */
  replaceOutlets(userId: string, items: OutletAssignment[]) {
    const ops: Prisma.PrismaPromise<unknown>[] = [this.prisma.userOutlet.deleteMany({ where: { userId } })];
    if (items.length > 0) {
      ops.push(this.prisma.userOutlet.createMany({ data: items.map((i) => ({ userId, ...i })) }));
    }
    return this.prisma.$transaction(ops);
  }

  // Legacy feature grants (main). Deprecated: replaced by persona permissions in Phase 2.

  async getFeatures(userId: string): Promise<AppFeature[]> {
    const grants = await this.prisma.userFeatureGrant.findMany({ where: { userId } });
    return grants.map((g) => g.feature);
  }

  async setFeatures(userId: string, features: AppFeature[]): Promise<void> {
    await this.prisma.userFeatureGrant.deleteMany({ where: { userId } });
    if (features.length > 0) {
      await this.prisma.userFeatureGrant.createMany({
        data: features.map((feature) => ({ userId, feature })),
      });
    }
  }
}
