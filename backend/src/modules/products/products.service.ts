import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { buildMeta } from '../../common/dto/pagination.dto';
import { STORAGE_SERVICE, StorageService } from '../uploads/storage.interface';
import {
  CreateProductDto,
  ProductQueryDto,
  ReplaceVariantsDto,
  Set86Dto,
  SetModifierGroupsDto,
  UpdateProductDto,
} from './dto/product.dto';
import { ImportSummary, ProductImportService } from './product-import.service';
import { ProductsRepository } from './products.repository';
import { normalizeVariantDefaults } from './variant-defaults';

@Injectable()
export class ProductsService {
  constructor(
    private repo: ProductsRepository,
    @Inject(STORAGE_SERVICE) private storage: StorageService,
    private importer: ProductImportService,
  ) {}

  async findAll(q: ProductQueryDto) {
    const where: Prisma.ProductWhereInput = {
      deletedAt: null,
      ...(q.isActive !== undefined ? { isActive: q.isActive } : {}),
      ...(q.search
        ? { OR: [{ name: { contains: q.search, mode: 'insensitive' } }, { description: { contains: q.search, mode: 'insensitive' } }] }
        : {}),
    };
    const [data, total] = await this.repo.findAll(where, q.skip, q.limit);
    return { data, meta: buildMeta(total, q.page, q.limit) };
  }

  async findOne(id: string) {
    const product = await this.repo.findOne(id);
    if (!product) throw new NotFoundException('Product not found');
    return product;
  }

  async create(dto: CreateProductDto) {
    await this.assertCategoryAndTaxClass(dto.categoryId, dto.taxClassId);
    return this.repo.create({
      name: dto.name,
      description: dto.description,
      price: new Prisma.Decimal(dto.price),
      taxPercentage: dto.taxPercentage === undefined ? null : new Prisma.Decimal(dto.taxPercentage),
      categoryId: dto.categoryId ?? null,
      taxClassId: dto.taxClassId ?? null,
      sortOrder: dto.sortOrder ?? 0,
    });
  }

  async update(id: string, dto: UpdateProductDto) {
    await this.findOne(id);
    await this.assertCategoryAndTaxClass(dto.categoryId ?? undefined, dto.taxClassId ?? undefined);
    const data: Prisma.ProductUncheckedUpdateInput = {};
    if (dto.name !== undefined) data.name = dto.name;
    if (dto.description !== undefined) data.description = dto.description;
    if (dto.price !== undefined) data.price = new Prisma.Decimal(dto.price);
    if (dto.taxPercentage !== undefined)
      data.taxPercentage = dto.taxPercentage === null ? null : new Prisma.Decimal(dto.taxPercentage);
    if (dto.categoryId !== undefined) data.categoryId = dto.categoryId;
    if (dto.taxClassId !== undefined) data.taxClassId = dto.taxClassId;
    if (dto.sortOrder !== undefined) data.sortOrder = dto.sortOrder;
    return this.repo.update(id, data);
  }

  async setStatus(id: string, isActive: boolean) {
    await this.findOne(id);
    return this.repo.update(id, { isActive });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.repo.softDelete(id);
    return { success: true };
  }

  async setImage(id: string, file: Express.Multer.File) {
    const product = await this.findOne(id);
    if (product.imageUrl) await this.storage.remove(product.imageUrl);
    const url = await this.storage.save(file.buffer, file.originalname, 'products');
    return this.repo.update(id, { imageUrl: url });
  }

  /** Replaces the variant list. Returns the saved variants. */
  async setVariants(id: string, dto: ReplaceVariantsDto) {
    const product = await this.findOne(id);
    const existing = await this.repo.findVariants(id);
    const known = new Set(existing.map((v) => v.id));
    if (dto.items.some((item) => item.id && !known.has(item.id))) {
      throw apiError(400, 'VARIANT_NOT_FOUND', 'A variant does not belong to this product');
    }
    const rows = normalizeVariantDefaults(dto.items).map((item, index) => ({
      id: item.id,
      name: item.name.trim(),
      price: new Prisma.Decimal(item.price),
      isDefault: item.isDefault,
      sortOrder: item.sortOrder ?? index,
    }));
    if (rows.length === 0 && product.variants.length === 0) return [];
    return this.repo.replaceVariants(id, rows);
  }

  /** Replaces the modifier groups attached to the product, in the order given. */
  async setModifierGroups(id: string, dto: SetModifierGroupsDto) {
    await this.findOne(id);
    const groupIds = [...new Set(dto.groupIds)];
    if (groupIds.length > 0) {
      const found = await this.repo.countActiveModifierGroups(groupIds);
      if (found !== groupIds.length) throw apiError(400, 'MODIFIER_GROUP_NOT_FOUND', 'A modifier group does not exist or is inactive');
    }
    return this.repo.replaceModifierGroups(id, groupIds);
  }

  /** Marks the product out of stock (86) or back in stock, and tells the outlet. */
  async set86(id: string, dto: Set86Dto, auth: AuthUser) {
    const product = await this.findOne(id);
    const updated = await this.repo.update(id, { is86: dto.is86 });
    if (product.is86 !== dto.is86) {
      await this.repo.createOutletNotification({
        tenantId: auth.tenantId,
        outletId: auth.outletId,
        productId: id,
        title: dto.is86 ? `${product.name} is out of stock` : `${product.name} is back in stock`,
        body: dto.is86 ? 'Marked out of stock (86) from the menu.' : 'Available to sell again.',
      });
    }
    return updated;
  }

  importExcel(file: Express.Multer.File, userId: string): Promise<ImportSummary> {
    return this.importer.importFromBuffer(file, userId);
  }

  importTemplate() {
    return this.importer.buildTemplate();
  }

  private async assertCategoryAndTaxClass(categoryId?: string | null, taxClassId?: string | null) {
    if (categoryId && !(await this.repo.findActiveCategory(categoryId))) {
      throw apiError(400, 'CATEGORY_NOT_FOUND', 'Category not found or inactive');
    }
    if (taxClassId && !(await this.repo.findActiveTaxClass(taxClassId))) {
      throw apiError(400, 'TAX_CLASS_NOT_FOUND', 'Tax class not found or inactive');
    }
  }
}
