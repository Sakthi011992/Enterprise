import { Injectable, NotFoundException } from '@nestjs/common';
import { ImageSource } from '@prisma/client';
import sharp from 'sharp';
import { PrismaService } from '../../prisma/prisma.service';
import { BlobStorageService } from '../../common/storage/blob-storage.service';
import { UnsplashAdapter } from './adapters/unsplash.adapter';

@Injectable()
export class ProductImagesService {
  constructor(
    private prisma: PrismaService,
    private blobs: BlobStorageService,
    private unsplash: UnsplashAdapter,
  ) {}

  private async normalizeImage(buffer: Buffer) {
    const processed = await sharp(buffer)
      .rotate()
      .resize({ width: 1600, withoutEnlargement: true })
      .webp({ quality: 85 })
      .toBuffer();
    return processed;
  }

  async uploadImage(productId: string, file: Express.Multer.File) {
    const buffer = await this.normalizeImage(file.buffer);
    const stored = await this.blobs.store(buffer, { mimeType: 'image/webp', folder: 'products' });
    const isFirst = (await this.prisma.productImage.count({ where: { productId } })) === 0;
    return this.prisma.productImage.create({
      data: {
        productId,
        isPrimary: isFirst,
        source: ImageSource.UPLOAD,
        mimeType: 'image/webp',
        sizeBytes: stored.sizeBytes,
        contentHash: stored.contentHash,
        blobPath: stored.blobPath,
      },
    });
  }

  searchStock(query: string, page = 1) {
    return this.unsplash.search(query, page);
  }

  async attachStock(
    productId: string,
    opts: {
      imageUrl: string;
      downloadLocation: string;
      photographerName: string;
      photographerUrl: string;
      sourceUrl: string;
    },
  ) {
    await this.unsplash.pingDownload(opts.downloadLocation);
    const raw = await this.unsplash.downloadBytes(opts.imageUrl);
    const buffer = await this.normalizeImage(raw);
    const stored = await this.blobs.store(buffer, { mimeType: 'image/webp', folder: 'products' });
    const isFirst = (await this.prisma.productImage.count({ where: { productId } })) === 0;
    return this.prisma.productImage.create({
      data: {
        productId,
        isPrimary: isFirst,
        source: ImageSource.STOCK,
        mimeType: 'image/webp',
        sizeBytes: stored.sizeBytes,
        contentHash: stored.contentHash,
        blobPath: stored.blobPath,
        photographerName: opts.photographerName,
        photographerUrl: opts.photographerUrl,
        sourceUrl: opts.sourceUrl,
      },
    });
  }

  listImages(productId: string) {
    return this.prisma.productImage.findMany({
      where: { productId },
      orderBy: [{ isPrimary: 'desc' }, { createdAt: 'asc' }],
    });
  }

  async setPrimary(productId: string, imageId: string) {
    return this.prisma.$transaction([
      this.prisma.productImage.updateMany({ where: { productId }, data: { isPrimary: false } }),
      this.prisma.productImage.update({ where: { id: imageId }, data: { isPrimary: true } }),
    ]);
  }

  async deleteImage(id: string) {
    const img = await this.prisma.productImage.findUnique({ where: { id } });
    if (!img) throw new NotFoundException('Image not found');
    await this.prisma.productImage.delete({ where: { id } });
    return { success: true };
  }

  async serveImage(blobPath: string): Promise<Buffer> {
    return this.blobs.read(blobPath);
  }
}
