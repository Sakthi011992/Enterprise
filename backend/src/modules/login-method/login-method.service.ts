import { BadRequestException, Injectable } from '@nestjs/common';
import { LoginMethod } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class LoginMethodService {
  constructor(private prisma: PrismaService) {}

  async getEnabled(): Promise<LoginMethod[]> {
    const configs = await this.prisma.loginMethodConfig.findMany({
      where: { enabled: true },
    });
    return configs.map((c) => c.method);
  }

  getAll() {
    return this.prisma.loginMethodConfig.findMany();
  }

  async setEnabled(method: LoginMethod, enabled: boolean) {
    if (!enabled) {
      const enabledMethods = await this.getEnabled();
      if (enabledMethods.length <= 1 && enabledMethods.includes(method)) {
        throw new BadRequestException('Cannot disable the last login method');
      }
    }
    return this.prisma.loginMethodConfig.upsert({
      where: { method },
      create: { method, enabled },
      update: { enabled },
    });
  }

  async assertEnabled(method: LoginMethod) {
    const config = await this.prisma.loginMethodConfig.findUnique({ where: { method } });
    if (!config?.enabled) {
      throw new BadRequestException(`Login method ${method} is not enabled`);
    }
  }
}
