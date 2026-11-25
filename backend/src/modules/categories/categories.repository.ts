import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class CategoriesRepository {
  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.category.findMany({ orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] });
  }

  findOne(id: string) {
    return this.prisma.category.findFirst({ where: { id } });
  }

  create(data: Omit<Prisma.CategoryUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.category.create({ data });
  }

  update(id: string, data: Prisma.CategoryUncheckedUpdateInput) {
    return this.prisma.category.update({ where: { id }, data });
  }

  countActiveProducts(categoryId: string) {
    return this.prisma.product.count({ where: { categoryId, isActive: true, deletedAt: null } });
  }

  findActiveTaxClass(id: string) {
    return this.prisma.taxClass.findFirst({ where: { id, isActive: true }, select: { id: true } });
  }
}
