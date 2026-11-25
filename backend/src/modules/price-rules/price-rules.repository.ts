import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PriceRulesRepository {
  constructor(private prisma: PrismaService) {}

  list(outletId: string) {
    return this.prisma.priceRule.findMany({
      where: { OR: [{ outletId: null }, { outletId }] },
      orderBy: { name: 'asc' },
    });
  }

  findOne(id: string) {
    return this.prisma.priceRule.findFirst({ where: { id } });
  }

  create(data: Omit<Prisma.PriceRuleUncheckedCreateInput, 'tenantId'>) {
    return this.prisma.priceRule.create({ data });
  }

  update(id: string, data: Prisma.PriceRuleUncheckedUpdateInput) {
    return this.prisma.priceRule.update({ where: { id }, data });
  }
}
