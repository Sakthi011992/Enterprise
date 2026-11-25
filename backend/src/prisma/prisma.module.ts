import { Global, Injectable, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaService, createTenantPrismaClient } from './prisma.service';

/** Connects the tenant-scoped client when the app starts and disconnects it on shutdown. */
@Injectable()
export class PrismaLifecycle implements OnModuleInit, OnModuleDestroy {
  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit(): Promise<void> {
    await this.prisma.$connect();
  }

  async onModuleDestroy(): Promise<void> {
    await this.prisma.$disconnect();
  }
}

@Global()
@Module({
  providers: [{ provide: PrismaService, useFactory: (): PrismaService => createTenantPrismaClient() }, PrismaLifecycle],
  exports: [PrismaService],
})
export class PrismaModule {}
