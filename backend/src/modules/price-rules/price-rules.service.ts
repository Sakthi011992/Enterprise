import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { CreatePriceRuleDto, UpdatePriceRuleDto } from './dto/price-rule.dto';
import { PriceRulesRepository } from './price-rules.repository';

@Injectable()
export class PriceRulesService {
  constructor(private repo: PriceRulesRepository) {}

  list(auth: AuthUser) {
    return this.repo.list(auth.outletId);
  }

  async create(dto: CreatePriceRuleDto, auth: AuthUser) {
    this.assertOutlet(dto.outletId, auth);
    this.assertWindow(dto.startTime, dto.endTime);
    return this.repo.create({
      outletId: dto.outletId ?? null,
      name: dto.name,
      percentOff: new Prisma.Decimal(dto.percentOff),
      categoryIds: dto.categoryIds,
      productIds: dto.productIds,
      days: dto.days,
      startTime: dto.startTime,
      endTime: dto.endTime,
      isActive: dto.isActive ?? true,
    });
  }

  async update(id: string, dto: UpdatePriceRuleDto, auth: AuthUser) {
    const current = await this.repo.findOne(id);
    if (!current) throw new NotFoundException('Happy hour not found');
    if (dto.outletId !== undefined) this.assertOutlet(dto.outletId, auth);
    this.assertWindow(dto.startTime ?? current.startTime, dto.endTime ?? current.endTime);
    const { outletId, percentOff, ...rest } = dto;
    return this.repo.update(id, {
      ...rest,
      ...(outletId !== undefined ? { outletId } : {}),
      ...(percentOff !== undefined ? { percentOff: new Prisma.Decimal(percentOff) } : {}),
    });
  }

  /** Soft delete: the rule stops applying and stays on record. */
  async remove(id: string) {
    const current = await this.repo.findOne(id);
    if (!current) throw new NotFoundException('Happy hour not found');
    await this.repo.update(id, { isActive: false });
    return { success: true };
  }

  private assertOutlet(outletId: string | null | undefined, auth: AuthUser) {
    if (outletId !== undefined && outletId !== null && outletId !== auth.outletId) {
      throw apiError(400, 'OUTLET_MISMATCH', 'A happy hour applies to all outlets or to the current outlet');
    }
  }

  private assertWindow(startTime: string, endTime: string) {
    if (startTime === endTime) throw apiError(400, 'TIME_WINDOW_EMPTY', 'Start and end time cannot be the same');
  }
}
