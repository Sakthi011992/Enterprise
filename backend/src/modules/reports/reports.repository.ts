import { Injectable } from '@nestjs/common';
import { OrderStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

const COUNTED: OrderStatus[] = [OrderStatus.PAID, OrderStatus.PARTIALLY_PAID];

@Injectable()
export class ReportsRepository {
  constructor(private prisma: PrismaService) {}

  aggregate(from: Date) {
    return this.prisma.order.aggregate({
      where: { createdAt: { gte: from }, status: { in: COUNTED } },
      _sum: { grandTotal: true, taxAmount: true },
      _count: { _all: true },
    });
  }

  topProducts(limit: number) {
    return this.prisma.orderItem.groupBy({
      by: ['productId', 'productName'],
      _sum: { quantity: true, lineTotal: true },
      orderBy: { _sum: { quantity: 'desc' } },
      take: limit,
    });
  }

  recentOrders(limit: number) {
    return this.prisma.order.findMany({
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: { cashier: { select: { username: true } } },
    });
  }
}
