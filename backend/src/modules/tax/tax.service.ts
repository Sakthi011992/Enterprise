import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { TaxRepository } from './tax.repository';

@Injectable()
export class TaxService {
  constructor(private repo: TaxRepository) {}

  async getGlobalTax() {
    const tax = await this.repo.getActiveTax();
    return tax ?? { percentage: new Prisma.Decimal(0), isActive: true };
  }

  async setGlobalTax(percentage: number) {
    await this.repo.deactivateAll();
    return this.repo.createTax(new Prisma.Decimal(percentage));
  }

  async setProductTax(productId: string, taxPercentage: number | null) {
    const product = await this.repo.findProduct(productId);
    if (!product) throw new NotFoundException('Product not found');
    return this.repo.updateProductTax(
      productId,
      taxPercentage === null ? null : new Prisma.Decimal(taxPercentage),
    );
  }

  resolveRate(productTax: Prisma.Decimal | null | undefined, globalTax: Prisma.Decimal): Prisma.Decimal {
    return productTax !== null && productTax !== undefined ? productTax : globalTax;
  }
}
