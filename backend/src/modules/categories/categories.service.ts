import { Injectable, NotFoundException } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';
import { CreateCategoryDto, UpdateCategoryDto } from './dto/category.dto';
import { CategoriesRepository } from './categories.repository';

@Injectable()
export class CategoriesService {
  constructor(private repo: CategoriesRepository) {}

  list() {
    return this.repo.list();
  }

  async create(dto: CreateCategoryDto) {
    await this.assertTaxClass(dto.taxClassId);
    return this.repo.create({
      name: dto.name,
      sortOrder: dto.sortOrder ?? 0,
      station: dto.station ?? 'KITCHEN',
      ticketKind: dto.ticketKind ?? 'KOT',
      taxClassId: dto.taxClassId ?? null,
      color: dto.color ?? null,
      isActive: dto.isActive ?? true,
    });
  }

  async update(id: string, dto: UpdateCategoryDto) {
    await this.findOne(id);
    await this.assertTaxClass(dto.taxClassId);
    const { taxClassId, ...rest } = dto;
    return this.repo.update(id, {
      ...rest,
      ...(taxClassId !== undefined ? { taxClassId } : {}),
    });
  }

  /** Soft delete. Refused while active products still use the category. */
  async remove(id: string) {
    await this.findOne(id);
    const count = await this.repo.countActiveProducts(id);
    if (count > 0) throw apiError(409, 'CATEGORY_IN_USE', 'Move or deactivate its products first', { count });
    await this.repo.update(id, { isActive: false });
    return { success: true };
  }

  private async findOne(id: string) {
    const category = await this.repo.findOne(id);
    if (!category) throw new NotFoundException('Category not found');
    return category;
  }

  private async assertTaxClass(taxClassId?: string | null) {
    if (taxClassId && !(await this.repo.findActiveTaxClass(taxClassId))) {
      throw apiError(400, 'TAX_CLASS_NOT_FOUND', 'Tax class not found or inactive');
    }
  }
}
