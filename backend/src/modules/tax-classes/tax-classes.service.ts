import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { CreateTaxClassDto, TaxComponentDto, UpdateTaxClassDto } from './dto/tax-class.dto';
import { TaxClassesRepository } from './tax-classes.repository';

/** Component rates must add up to the class rate (to 2 decimals). */
export function assertComponentsSumToRate(rate: number, components: TaxComponentDto[]): void {
  const sum = components.reduce((total, c) => total.add(new Prisma.Decimal(c.rate)), new Prisma.Decimal(0));
  if (!sum.equals(new Prisma.Decimal(rate))) {
    throw apiError(400, 'TAX_COMPONENTS_MISMATCH', `Components add up to ${sum.toFixed(2)}, the rate is ${new Prisma.Decimal(rate).toFixed(2)}`);
  }
}

@Injectable()
export class TaxClassesService {
  constructor(private repo: TaxClassesRepository) {}

  list() {
    return this.repo.list();
  }

  async create(dto: CreateTaxClassDto) {
    assertComponentsSumToRate(dto.rate, dto.components);
    if (await this.repo.findByCode(dto.code)) throw apiError(409, 'TAX_CODE_TAKEN', `Tax code ${dto.code} already exists`);
    return this.repo.create({
      name: dto.name,
      code: dto.code,
      rate: new Prisma.Decimal(dto.rate),
      components: dto.components.map((c) => ({ name: c.name, rate: c.rate })),
      inclusive: dto.inclusive ?? false,
      isLiquor: dto.isLiquor ?? false,
      isActive: dto.isActive ?? true,
    });
  }

  async update(id: string, dto: UpdateTaxClassDto) {
    const current = await this.repo.findOne(id);
    if (!current) throw new NotFoundException('Tax class not found');
    const rate = dto.rate ?? Number(current.rate);
    const components = dto.components ?? (current.components as unknown as TaxComponentDto[]);
    assertComponentsSumToRate(rate, components);
    if (dto.code && dto.code !== current.code && (await this.repo.findByCode(dto.code))) {
      throw apiError(409, 'TAX_CODE_TAKEN', `Tax code ${dto.code} already exists`);
    }
    return this.repo.update(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.code !== undefined ? { code: dto.code } : {}),
      rate: new Prisma.Decimal(rate),
      components: components.map((c) => ({ name: c.name, rate: c.rate })),
      ...(dto.inclusive !== undefined ? { inclusive: dto.inclusive } : {}),
      ...(dto.isLiquor !== undefined ? { isLiquor: dto.isLiquor } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
    });
  }

  /** Soft delete. Refused while active products or categories use the class. Past orders keep their tax snapshots. */
  async remove(id: string) {
    const current = await this.repo.findOne(id);
    if (!current) throw new NotFoundException('Tax class not found');
    const [products, categories] = await Promise.all([
      this.repo.countActiveProducts(id),
      this.repo.countActiveCategories(id),
    ]);
    if (products + categories > 0) {
      throw apiError(409, 'TAX_CLASS_IN_USE', 'Change the products and categories that use this tax class first', {
        products,
        categories,
      });
    }
    await this.repo.update(id, { isActive: false });
    return { success: true };
  }
}
