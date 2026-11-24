import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateFeaturedItemDto, UpdateFeaturedItemDto } from './dto/kiosk.dto';

@Injectable()
export class KioskService {
  constructor(private prisma: PrismaService) {}

  async getConfig(userId: string) {
    return this.prisma.kioskConfig.findUnique({ where: { userId } });
  }

  async createDefault(userId: string, storeId = 'default') {
    return this.prisma.kioskConfig.upsert({
      where: { userId },
      create: { userId, storeId, orderingEnabled: false },
      update: {},
    });
  }

  async setOrderingEnabled(userId: string, enabled: boolean) {
    return this.prisma.kioskConfig.update({
      where: { userId },
      data: { orderingEnabled: enabled },
    });
  }

  listConfigsForStore(storeId: string) {
    return this.prisma.kioskConfig.findMany({ where: { storeId } });
  }

  async getActiveFeaturedItems(storeId: string) {
    const now = new Date();
    return this.prisma.featuredItem.findMany({
      where: {
        storeId,
        isActive: true,
        OR: [{ startsAt: null }, { startsAt: { lte: now } }],
        AND: [{ OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
      },
      orderBy: { sortOrder: 'asc' },
      include: { product: true },
    });
  }

  listAllFeaturedItems(storeId: string) {
    return this.prisma.featuredItem.findMany({
      where: { storeId },
      orderBy: { sortOrder: 'asc' },
      include: { product: { select: { name: true, price: true } } },
    });
  }

  createFeaturedItem(dto: CreateFeaturedItemDto) {
    return this.prisma.featuredItem.create({
      data: {
        productId: dto.productId,
        storeId: dto.storeId ?? 'default',
        label: dto.label,
        sortOrder: dto.sortOrder ?? 0,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
      },
    });
  }

  async updateFeaturedItem(id: string, dto: UpdateFeaturedItemDto) {
    const item = await this.prisma.featuredItem.findUnique({ where: { id } });
    if (!item) throw new NotFoundException('Featured item not found');
    return this.prisma.featuredItem.update({
      where: { id },
      data: {
        label: dto.label,
        sortOrder: dto.sortOrder,
        isActive: dto.isActive,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : undefined,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : undefined,
      },
    });
  }

  deleteFeaturedItem(id: string) {
    return this.prisma.featuredItem.delete({ where: { id } });
  }
}
