import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import type { AccessLevel } from '../../common/permissions/catalog';

export const PERSONA_INCLUDE = { _count: { select: { userOutlets: true } } } as const;

export interface GrantRow {
  permissionKey: string;
  level: AccessLevel;
  limitValue: number | null;
}

export interface PersonaCreateData {
  tenantId: string;
  key: string;
  name: string;
  homeRoute: string;
  loginMethod: 'PASSWORD' | 'PIN';
  isSystem: boolean;
  grants?: GrantRow[];
}

export interface PersonaUpdateData {
  name?: string;
  description?: string | null;
  homeRoute?: string;
  loginMethod?: 'PASSWORD' | 'PIN';
}

/** Data access for personas, the permission catalog and persona grants. */
@Injectable()
export class PersonasRepository {
  constructor(private prisma: PrismaService) {}

  catalog() {
    return this.prisma.permission.findMany({ orderBy: { sortOrder: 'asc' } });
  }

  grantsFor(personaId: string) {
    return this.prisma.personaPermission.findMany({ where: { personaId } });
  }

  listForTenant(tenantId: string) {
    return this.prisma.persona.findMany({
      where: { tenantId },
      include: PERSONA_INCLUDE,
      orderBy: [{ isSystem: 'desc' }, { createdAt: 'asc' }],
    });
  }

  findOwned(id: string, tenantId: string) {
    return this.prisma.persona.findFirst({ where: { id, tenantId }, include: PERSONA_INCLUDE });
  }

  async keyTaken(tenantId: string, key: string): Promise<boolean> {
    const row = await this.prisma.persona.findFirst({ where: { tenantId, key }, select: { id: true } });
    return row !== null;
  }

  create(data: PersonaCreateData) {
    const { grants, ...rest } = data;
    return this.prisma.persona.create({
      data: {
        ...rest,
        ...(grants && grants.length > 0
          ? {
              permissions: {
                create: grants.map((g) => ({
                  permissionKey: g.permissionKey,
                  level: g.level,
                  limitValue: g.limitValue,
                })),
              },
            }
          : {}),
      },
      include: PERSONA_INCLUDE,
    });
  }

  update(id: string, data: PersonaUpdateData) {
    return this.prisma.persona.update({ where: { id }, data, include: PERSONA_INCLUDE });
  }

  delete(id: string) {
    return this.prisma.persona.delete({ where: { id } });
  }

  /** Replaces every grant for a persona in one transaction. */
  replaceGrants(personaId: string, rows: GrantRow[]) {
    const ops: Prisma.PrismaPromise<unknown>[] = [
      this.prisma.personaPermission.deleteMany({ where: { personaId } }),
    ];
    if (rows.length > 0) {
      ops.push(
        this.prisma.personaPermission.createMany({
          data: rows.map((r) => ({
            personaId,
            permissionKey: r.permissionKey,
            level: r.level,
            limitValue: r.limitValue,
          })),
        }),
      );
    }
    return this.prisma.$transaction(ops);
  }
}
