import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class CombosRepository {
  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.combo.findMany({ orderBy: { name: 'asc' }, include: { items: true } });
  }

  findOne(id: string) {
    return this.prisma.combo.findFirst({ where: { id }, include: { items: true } });
  }

  create(data: Omit<Prisma.ComboUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.combo.create({ data, include: { items: true } });
  }

  /** Replaces the item list in the same write. */
  update(id: string, data: Prisma.ComboUncheckedUpdateInput, items?: Prisma.ComboItemUncheckedCreateWithoutComboInput[]) {
    return this.prisma.combo.update({
      where: { id },
      data: items ? { ...data, items: { deleteMany: {}, create: items } } : data,
      include: { items: true },
    });
  }

  findActiveProducts(ids: string[]) {
    return this.prisma.product.findMany({
      where: { id: { in: ids }, isActive: true, deletedAt: null },
      select: { id: true },
    });
  }

  findVariants(ids: string[]) {
    return this.prisma.productVariant.findMany({ where: { id: { in: ids } }, select: { id: true, productId: true } });
  }
}
