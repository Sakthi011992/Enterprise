import { Injectable } from '@nestjs/common';
import { LoginMethod } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Data access for the admin-controlled login method toggles. */
@Injectable()
export class LoginMethodRepository {
  constructor(private prisma: PrismaService) {}

  findEnabled() {
    return this.prisma.loginMethodConfig.findMany({ where: { enabled: true } });
  }

  findAll() {
    return this.prisma.loginMethodConfig.findMany();
  }

  findOne(method: LoginMethod) {
    return this.prisma.loginMethodConfig.findUnique({ where: { method } });
  }

  upsert(method: LoginMethod, enabled: boolean) {
    return this.prisma.loginMethodConfig.upsert({
      where: { method },
      create: { method, enabled },
      update: { enabled },
    });
  }
}
