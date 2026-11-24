import { BadRequestException, Injectable } from '@nestjs/common';
import { PaymentMethod } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PaymentConfigService {
  constructor(private prisma: PrismaService) {}

  async getEnabledMethods(storeId = 'default'): Promise<PaymentMethod[]> {
    const configs = await this.prisma.paymentMethodConfig.findMany({
      where: { storeId, enabled: true },
    });
    return configs.map((c) => c.method);
  }

  getAllConfigs(storeId = 'default') {
    return this.prisma.paymentMethodConfig.findMany({ where: { storeId } });
  }

  async setEnabled(storeId: string, method: PaymentMethod, enabled: boolean) {
    return this.prisma.paymentMethodConfig.upsert({
      where: { storeId_method: { storeId, method } },
      create: { storeId, method, enabled },
      update: { enabled },
    });
  }

  async assertMethodEnabled(storeId: string, method: PaymentMethod) {
    const config = await this.prisma.paymentMethodConfig.findUnique({
      where: { storeId_method: { storeId, method } },
    });
    if (!config?.enabled) {
      throw new BadRequestException(`Payment method ${method} is not enabled for this store`);
    }
  }
}
