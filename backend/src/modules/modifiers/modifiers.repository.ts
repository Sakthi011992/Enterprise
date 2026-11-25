import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const WITH_OPTIONS = {
  options: { orderBy: [{ sortOrder: 'asc' as const }, { name: 'asc' as const }] },
};

@Injectable()
export class ModifiersRepository {
  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.modifierGroup.findMany({ orderBy: { name: 'asc' }, include: WITH_OPTIONS });
  }

  /** Stock items named by option links (existence and display names only). */
  stockItemsByIds(ids: string[]) {
    return this.prisma.stockItem.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } });
  }

  findOne(id: string) {
    return this.prisma.modifierGroup.findFirst({ where: { id }, include: WITH_OPTIONS });
  }

  create(data: Omit<Prisma.ModifierGroupUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.modifierGroup.create({ data, include: WITH_OPTIONS });
  }

  /** Updates the group and reconciles its options in one write: listed ids are updated, new rows created, the rest deactivated. */
  update(
    id: string,
    data: Prisma.ModifierGroupUncheckedUpdateInput,
    options?: {
      keep: { id: string; data: Prisma.ModifierOptionUncheckedUpdateInput }[];
      create: Prisma.ModifierOptionUncheckedCreateWithoutGroupInput[];
      keepIds: string[];
    },
  ) {
    return this.prisma.modifierGroup.update({
      where: { id },
      data: {
        ...data,
        ...(options
          ? {
              options: {
                updateMany: { where: { id: { notIn: options.keepIds } }, data: { isActive: false } },
                update: options.keep.map((o) => ({ where: { id: o.id }, data: o.data })),
                create: options.create,
              },
            }
          : {}),
      },
      include: WITH_OPTIONS,
    });
  }
}
