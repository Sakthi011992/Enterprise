import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const ORDER_INCLUDE = {
  items: true,
  payments: true,
  cashier: { select: { username: true } },
} satisfies Prisma.OrderInclude;

@Injectable()
export class OrdersRepository {
  constructor(private prisma: PrismaService) {}

  countToday(start: Date, end: Date) {
    return this.prisma.order.count({ where: { createdAt: { gte: start, lt: end } } });
  }

  create(data: Prisma.OrderCreateInput) {
    return this.prisma.order.create({ data, include: ORDER_INCLUDE });
  }

  findAll(where: Prisma.OrderWhereInput, skip: number, take: number) {
    return this.prisma.$transaction([
      this.prisma.order.findMany({
        where,
        skip,
        take,
        orderBy: { createdAt: 'desc' },
        include: { cashier: { select: { username: true } } },
      }),
      this.prisma.order.count({ where }),
    ]);
  }

  findOne(id: string) {
    return this.prisma.order.findUnique({ where: { id }, include: ORDER_INCLUDE });
  }

  findProductsByIds(ids: string[]) {
    return this.prisma.product.findMany({
      where: { id: { in: ids }, deletedAt: null, isActive: true },
    });
  }

  updateStatus(id: string, status: string) {
    return this.prisma.order.update({ where: { id }, data: { status: status as any } });
  }
}
