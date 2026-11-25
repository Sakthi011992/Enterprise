import { BadRequestException, Injectable } from '@nestjs/common';
import { LoginMethod } from '@prisma/client';
import { LoginMethodRepository } from './login-method.repository';

@Injectable()
export class LoginMethodService {
  constructor(private repo: LoginMethodRepository) {}

  async getEnabled(): Promise<LoginMethod[]> {
    const configs = await this.repo.findEnabled();
    return configs.map((c) => c.method);
  }

  getAll() {
    return this.repo.findAll();
  }

  async setEnabled(method: LoginMethod, enabled: boolean) {
    if (!enabled) {
      const enabledMethods = await this.getEnabled();
      if (enabledMethods.length <= 1 && enabledMethods.includes(method)) {
        throw new BadRequestException('Cannot disable the last login method');
      }
    }
    return this.repo.upsert(method, enabled);
  }

  async assertEnabled(method: LoginMethod) {
    const config = await this.repo.findOne(method);
    if (!config?.enabled) {
      throw new BadRequestException(`Login method ${method} is not enabled`);
    }
  }
}
