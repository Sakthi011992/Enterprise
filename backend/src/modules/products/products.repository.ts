import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ProductsRepository {
  constructor(private prisma: PrismaService) {}

  findAll(where: Prisma.ProductWhereInput, skip: number, take: number) {
    return this.prisma.$transaction([
      this.prisma.product.findMany({ where, skip, take, orderBy: { name: 'asc' } }),
      this.prisma.product.count({ where }),
    ]);
  }

  findOne(id: string) {
    return this.prisma.product.findFirst({
      where: { id, deletedAt: null },
      include: {
        variants: { orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] },
        modifierGroups: { select: { groupId: true, sortOrder: true }, orderBy: { sortOrder: 'asc' } },
      },
    });
  }

  findManyByIds(ids: string[]) {
    return this.prisma.product.findMany({
      where: { id: { in: ids }, deletedAt: null, isActive: true },
    });
  }

  /** tenantId is filled in by the tenant-scope extension. */
  create(data: Omit<Prisma.ProductUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.product.create({ data });
  }

  update(id: string, data: Prisma.ProductUncheckedUpdateInput) {
    return this.prisma.product.update({ where: { id }, data });
  }

  softDelete(id: string) {
    return this.prisma.product.update({
      where: { id },
      data: { deletedAt: new Date(), isActive: false },
    });
  }

  // ---- category and tax class checks (tenant scoped by the Prisma extension) ----

  findActiveCategory(id: string) {
    return this.prisma.category.findFirst({ where: { id, isActive: true }, select: { id: true } });
  }

  findActiveTaxClass(id: string) {
    return this.prisma.taxClass.findFirst({ where: { id, isActive: true }, select: { id: true } });
  }

  countActiveModifierGroups(ids: string[]) {
    return this.prisma.modifierGroup.count({ where: { id: { in: ids }, isActive: true } });
  }

  // ---- variants ----------------------------------------------------------

  findVariants(productId: string) {
    return this.prisma.productVariant.findMany({
      where: { productId },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  /**
   * Applies a variant list: rows with an id are updated, rows without one are created, and existing
   * variants not in the list are deactivated (order lines keep their snapshot name and price).
   */
  replaceVariants(
    productId: string,
    rows: { id?: string; name: string; price: Prisma.Decimal; isDefault: boolean; sortOrder: number }[],
  ) {
    return this.prisma.$transaction(async (tx) => {
      const keep = rows.map((r) => r.id).filter((id): id is string => !!id);
      await tx.productVariant.updateMany({
        where: { productId, id: { notIn: keep }, isActive: true },
        data: { isActive: false, isDefault: false },
      });
      for (const row of rows) {
        const data = { name: row.name, price: row.price, isDefault: row.isDefault, sortOrder: row.sortOrder, isActive: true };
        if (row.id) {
          await tx.productVariant.update({ where: { id: row.id }, data });
        } else {
          await tx.productVariant.create({ data: { productId, ...data } });
        }
      }
      return tx.productVariant.findMany({
        where: { productId },
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      });
    });
  }

  // ---- modifier groups ---------------------------------------------------

  replaceModifierGroups(productId: string, groupIds: string[]) {
    return this.prisma.$transaction(async (tx) => {
      await tx.productModifierGroup.deleteMany({ where: { productId } });
      if (groupIds.length > 0) {
        await tx.productModifierGroup.createMany({
          data: groupIds.map((groupId, sortOrder) => ({ productId, groupId, sortOrder })),
        });
      }
      return tx.productModifierGroup.findMany({ where: { productId }, orderBy: { sortOrder: 'asc' } });
    });
  }

  // ---- notifications (outlet-level alerts) --------------------------------

  createOutletNotification(data: { tenantId: string; outletId: string; title: string; body: string; productId: string }) {
    return this.prisma.notification.create({
      data: {
        tenantId: data.tenantId,
        outletId: data.outletId,
        type: 'stock',
        title: data.title,
        body: data.body,
        data: { productId: data.productId },
      },
    });
  }
}
