import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { decimalInput } from '../inventory/decimal-input';
import { qty3 } from '../inventory/inventory-views';
import { ModifierGroupDto, ModifierOptionDto } from './dto/modifier-group.dto';
import { ModifiersRepository } from './modifiers.repository';

type GroupRow = NonNullable<Awaited<ReturnType<ModifiersRepository['findOne']>>>;

/** minSelect must not exceed maxSelect, and both must fit the active options. */
export function assertSelectRules(minSelect: number, maxSelect: number, activeOptions: number): void {
  if (minSelect > maxSelect) throw apiError(400, 'MODIFIER_RULES', 'Minimum selections cannot exceed the maximum');
  if (maxSelect > Math.max(activeOptions, 1)) {
    throw apiError(400, 'MODIFIER_RULES', 'Maximum selections cannot exceed the number of options');
  }
}

@Injectable()
export class ModifiersService {
  constructor(private repo: ModifiersRepository) {}

  async list() {
    return this.views(await this.repo.list());
  }

  async create(dto: ModifierGroupDto) {
    const minSelect = dto.minSelect ?? 0;
    const maxSelect = dto.maxSelect ?? 1;
    const activeOptions = dto.options.length;
    assertSelectRules(minSelect, maxSelect, activeOptions);
    await this.assertStockRefs(dto.options);
    const [group] = await this.views([
      await this.repo.create({
        name: dto.name,
        minSelect,
        maxSelect,
        showOn: dto.showOn ?? ['POS'],
        isActive: dto.isActive ?? true,
        options: { create: dto.options.map((o, i) => this.optionRow(o, i)) },
      }),
    ]);
    return group;
  }

  async update(id: string, dto: ModifierGroupDto) {
    const current = await this.repo.findOne(id);
    if (!current) throw new NotFoundException('Modifier group not found');

    const minSelect = dto.minSelect ?? 0;
    const maxSelect = dto.maxSelect ?? 1;
    assertSelectRules(minSelect, maxSelect, dto.options.length);
    await this.assertStockRefs(dto.options);

    const known = new Set(current.options.map((o) => o.id));
    if (dto.options.some((o) => o.id && !known.has(o.id))) {
      throw apiError(400, 'MODIFIER_OPTION_NOT_FOUND', 'An option does not belong to this group');
    }

    const keep = dto.options
      .map((o, i) => ({ option: o, index: i }))
      .filter(({ option }) => !!option.id)
      .map(({ option, index }) => ({
        id: option.id as string,
        data: this.optionRow(option, index) as Prisma.ModifierOptionUncheckedUpdateInput,
      }));
    const create = dto.options
      .map((o, i) => ({ option: o, index: i }))
      .filter(({ option }) => !option.id)
      .map(({ option, index }) => this.optionRow(option, index));

    const [group] = await this.views([
      await this.repo.update(
        id,
        {
          name: dto.name,
          minSelect,
          maxSelect,
          ...(dto.showOn !== undefined ? { showOn: dto.showOn } : {}),
          ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
        },
        { keep, create, keepIds: keep.map((k) => k.id) },
      ),
    ]);
    return group;
  }

  /** Soft delete. Products that still reference the group stop offering it (inactive groups are left out of the POS menu). */
  async remove(id: string) {
    if (!(await this.repo.findOne(id))) throw new NotFoundException('Modifier group not found');
    await this.repo.update(id, { isActive: false });
    return { success: true };
  }

  private optionRow(option: ModifierOptionDto, index: number) {
    return {
      name: option.name,
      priceDelta: new Prisma.Decimal(option.priceDelta ?? 0),
      sortOrder: option.sortOrder ?? index,
      isActive: true,
      ...this.stockFields(option),
    };
  }

  /** An option sold from stock carries the item and the base units per option; without an item the quantity is ignored. */
  private stockFields(option: ModifierOptionDto): { stockItemId: string | null; stockQty: Prisma.Decimal | null } {
    if (!option.stockItemId) return { stockItemId: null, stockQty: null };
    const stockQty = decimalInput(option.stockQty, 'stockQty', { dp: 3, min: 0.001 }) as Prisma.Decimal;
    return { stockItemId: option.stockItemId, stockQty };
  }

  private async assertStockRefs(options: ModifierOptionDto[]): Promise<void> {
    const ids = [...new Set(options.map((o) => o.stockItemId).filter((v): v is string => !!v))];
    if (ids.length === 0) return;
    const items = await this.repo.stockItemsByIds(ids);
    if (items.length !== ids.length) {
      throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found', { stockItemIds: ids });
    }
  }

  /** Adds the stock item name and formats the stock quantity (3 dp string) on each option. */
  private async views(groups: GroupRow[]) {
    const ids = [...new Set(groups.flatMap((g) => g.options.map((o) => o.stockItemId)).filter((v): v is string => !!v))];
    const items = ids.length ? await this.repo.stockItemsByIds(ids) : [];
    const names = new Map(items.map((i) => [i.id, i.name]));
    return groups.map((g) => ({
      ...g,
      options: g.options.map((o) => ({
        ...o,
        stockQty: o.stockQty === null ? null : qty3(o.stockQty),
        stockItemName: o.stockItemId ? (names.get(o.stockItemId) ?? null) : null,
      })),
    }));
  }
}
