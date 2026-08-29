import { Injectable } from '@nestjs/common';
import { LogoRole, LogoVariant } from '@prisma/client';
import * as sharp from 'sharp';
import { PrismaService } from '../../prisma/prisma.service';
import { BlobStorageService } from '../../common/storage/blob-storage.service';

@Injectable()
export class BrandingService {
  constructor(
    private prisma: PrismaService,
    private blobs: BlobStorageService,
  ) {}

  async uploadLogo(
    themeId: string,
    role: LogoRole,
    variant: LogoVariant,
    file: Express.Multer.File,
  ) {
    let buffer: Buffer;
    let mimeType: string;

    if (file.mimetype === 'image/svg+xml') {
      buffer = file.buffer;
      mimeType = 'image/svg+xml';
    } else {
      buffer = await sharp(file.buffer)
        .rotate()                  // auto-orient (strips EXIF)
        .resize({ width: 2048, withoutEnlargement: true })
        .png()
        .toBuffer();
      mimeType = 'image/png';
    }

    const meta = await sharp(buffer).metadata().catch(() => ({ width: undefined, height: undefined }));
    const stored = await this.blobs.store(buffer, { mimeType, folder: 'logos' });

    return this.prisma.brandLogo.upsert({
      where: { themeId_role_variant: { themeId, role, variant } },
      create: {
        themeId, role, variant, mimeType,
        sizeBytes: stored.sizeBytes,
        contentHash: stored.contentHash,
        blobPath: stored.blobPath,
        width: meta.width,
        height: meta.height,
      },
      update: {
        mimeType,
        sizeBytes: stored.sizeBytes,
        contentHash: stored.contentHash,
        blobPath: stored.blobPath,
        width: meta.width,
        height: meta.height,
      },
    });
  }

  async getLogo(themeId: string, role: LogoRole, variant: LogoVariant) {
    const logo = await this.prisma.brandLogo.findUnique({
      where: { themeId_role_variant: { themeId, role, variant } },
    });
    if (logo) return logo;
    // fallback to opposite variant
    const opposite = variant === LogoVariant.LIGHT ? LogoVariant.DARK : LogoVariant.LIGHT;
    return this.prisma.brandLogo.findUnique({
      where: { themeId_role_variant: { themeId, role, variant: opposite } },
    });
  }

  listLogos(themeId: string) {
    return this.prisma.brandLogo.findMany({ where: { themeId } });
  }

  async serveLogo(blobPath: string): Promise<{ buffer: Buffer; mimeType: string }> {
    const logo = await this.prisma.brandLogo.findFirst({ where: { blobPath } });
    const buffer = await this.blobs.read(blobPath);
    return { buffer, mimeType: logo?.mimeType ?? 'image/png' };
  }
}
