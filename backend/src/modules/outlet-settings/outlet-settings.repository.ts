import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class OutletSettingsRepository {
  constructor(private prisma: PrismaService) {}

  find(outletId: string) {
    return this.prisma.outletSettings.findUnique({ where: { outletId } });
  }

  upsert(outletId: string, data: Omit<Prisma.OutletSettingsUncheckedCreateInput, 'outletId'>) {
    return this.prisma.outletSettings.upsert({
      where: { outletId },
      create: { outletId, ...data },
      update: data,
    });
  }
}
