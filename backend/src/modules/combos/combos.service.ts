import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { ComboDto } from './dto/combo.dto';
import { CombosRepository } from './combos.repository';

@Injectable()
export class CombosService {
  constructor(private repo: CombosRepository) {}

  list() {
    return this.repo.list();
  }

  async create(dto: ComboDto) {
    const items = await this.checkedItems(dto);
    return this.repo.create({
      name: dto.name,
      price: new Prisma.Decimal(dto.price),
      taxClassId: dto.taxClassId ?? null,
      days: dto.days ?? [0, 1, 2, 3, 4, 5, 6],
      startTime: dto.startTime ?? null,
      endTime: dto.endTime ?? null,
      isActive: dto.isActive ?? true,
      items: { create: items },
    });
  }

  async update(id: string, dto: ComboDto) {
    if (!(await this.repo.findOne(id))) throw new NotFoundException('Combo not found');
    const items = await this.checkedItems(dto);
    return this.repo.update(
      id,
      {
        name: dto.name,
        price: new Prisma.Decimal(dto.price),
        taxClassId: dto.taxClassId ?? null,
        days: dto.days ?? [0, 1, 2, 3, 4, 5, 6],
        startTime: dto.startTime ?? null,
        endTime: dto.endTime ?? null,
        isActive: dto.isActive ?? true,
      },
      items,
    );
  }

  /** Soft delete. */
  async remove(id: string) {
    if (!(await this.repo.findOne(id))) throw new NotFoundException('Combo not found');
    await this.repo.update(id, { isActive: false });
    return { success: true };
  }

  /** Every product must be active, and a variant must belong to its product. */
  private async checkedItems(dto: ComboDto) {
    const productIds = [...new Set(dto.items.map((i) => i.productId))];
    const products = await this.repo.findActiveProducts(productIds);
    if (products.length !== productIds.length) {
      throw apiError(400, 'PRODUCT_NOT_FOUND', 'A product in the combo does not exist or is inactive');
    }
    const variantIds = dto.items.map((i) => i.variantId).filter((v): v is string => !!v);
    if (variantIds.length > 0) {
      const variants = await this.repo.findVariants(variantIds);
      const owner = new Map(variants.map((v) => [v.id, v.productId]));
      for (const item of dto.items) {
        if (item.variantId && owner.get(item.variantId) !== item.productId) {
          throw apiError(400, 'VARIANT_NOT_FOUND', 'A variant does not belong to its product');
        }
      }
    }
    return dto.items.map((item) => ({
      productId: item.productId,
      variantId: item.variantId ?? null,
      quantity: item.quantity ?? 1,
      swapAllowed: item.swapAllowed ?? false,
    }));
  }
}
