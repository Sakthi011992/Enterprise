import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { buildMeta } from '../../common/dto/pagination.dto';
import { STORAGE_SERVICE, StorageService } from '../uploads/storage.interface';
import { CreateProductDto, ProductQueryDto, UpdateProductDto } from './dto/product.dto';
import { ImportSummary, ProductImportService } from './product-import.service';
import { ProductsRepository } from './products.repository';

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

  create(dto: CreateProductDto) {
    return this.repo.create({
      name: dto.name,
      description: dto.description,
      price: new Prisma.Decimal(dto.price),
      taxPercentage: dto.taxPercentage === undefined ? null : new Prisma.Decimal(dto.taxPercentage),
    });
  }

  async update(id: string, dto: UpdateProductDto) {
    await this.findOne(id);
    const data: Prisma.ProductUpdateInput = {};
    if (dto.name !== undefined) data.name = dto.name;
    if (dto.description !== undefined) data.description = dto.description;
    if (dto.price !== undefined) data.price = new Prisma.Decimal(dto.price);
    if (dto.taxPercentage !== undefined)
      data.taxPercentage = dto.taxPercentage === null ? null : new Prisma.Decimal(dto.taxPercentage);
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

  importExcel(file: Express.Multer.File, userId: string): Promise<ImportSummary> {
    return this.importer.importFromBuffer(file, userId);
  }

  importTemplate() {
    return this.importer.buildTemplate();
  }
}
