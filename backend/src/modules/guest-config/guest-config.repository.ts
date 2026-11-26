import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class GuestConfigRepository {
  constructor(private prisma: PrismaService) {}

  find(tenantId: string) {
    return this.prisma.guestConfig.findUnique({ where: { tenantId } });
  }

  upsert(tenantId: string, config: Prisma.InputJsonValue, updatedById: string | null) {
    return this.prisma.guestConfig.upsert({
      where: { tenantId },
      create: { tenantId, config, updatedById },
      update: { config, updatedById },
    });
  }
}
