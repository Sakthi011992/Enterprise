import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class TaxRepository {
  constructor(private prisma: PrismaService) {}

  getActiveTax() {
    return this.prisma.globalTaxSetting.findFirst({
      where: { isActive: true },
      orderBy: { updatedAt: 'desc' },
    });
  }

  deactivateAll() {
    return this.prisma.globalTaxSetting.updateMany({
      where: { isActive: true },
      data: { isActive: false },
    });
  }

  createTax(percentage: Prisma.Decimal) {
    return this.prisma.globalTaxSetting.create({
      data: { percentage, isActive: true },
    });
  }

  findProduct(productId: string) {
    return this.prisma.product.findFirst({ where: { id: productId, deletedAt: null } });
  }

  updateProductTax(productId: string, taxPercentage: Prisma.Decimal | null) {
    return this.prisma.product.update({
      where: { id: productId },
      data: { taxPercentage },
    });
  }
}
