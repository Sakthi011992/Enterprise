import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class TaxClassesRepository {
  constructor(private prisma: PrismaService) {}

  list() {
    return this.prisma.taxClass.findMany({ orderBy: { code: 'asc' } });
  }

  findOne(id: string) {
    return this.prisma.taxClass.findFirst({ where: { id } });
  }

  findByCode(code: string) {
    return this.prisma.taxClass.findFirst({ where: { code }, select: { id: true } });
  }

  create(data: Omit<Prisma.TaxClassUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.taxClass.create({ data });
  }

  update(id: string, data: Prisma.TaxClassUncheckedUpdateInput) {
    return this.prisma.taxClass.update({ where: { id }, data });
  }

  countActiveProducts(taxClassId: string) {
    return this.prisma.product.count({ where: { taxClassId, isActive: true, deletedAt: null } });
  }

  countActiveCategories(taxClassId: string) {
    return this.prisma.category.count({ where: { taxClassId, isActive: true } });
  }
}
