import { Injectable } from '@nestjs/common';
import { ReportsRepository } from './reports.repository';

@Injectable()
export class ReportsService {
  constructor(private repo: ReportsRepository) {}

  private startOfDay(d = new Date()) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }
  private startOfMonth(d = new Date()) {
    return new Date(d.getFullYear(), d.getMonth(), 1);
  }

  private async aggregate(from: Date) {
    const result = await this.repo.aggregate(from);
    return {
      orders: result._count._all,
      revenue: Number(result._sum.grandTotal ?? 0),
      taxCollected: Number(result._sum.taxAmount ?? 0),
    };
  }

  async dashboard() {
    const today = await this.aggregate(this.startOfDay());
    const month = await this.aggregate(this.startOfMonth());
    return {
      today: { ordersCount: today.orders, revenue: today.revenue, taxCollected: today.taxCollected },
      monthly: { revenue: month.revenue, taxCollected: month.taxCollected },
    };
  }

  async topProducts(limit = 10) {
    const grouped = await this.repo.topProducts(limit);
    return grouped.map((g) => ({
      productId: g.productId,
      productName: g.productName,
      quantitySold: g._sum.quantity ?? 0,
      revenue: Number(g._sum.lineTotal ?? 0),
    }));
  }

  recentOrders(limit = 10) {
    return this.repo.recentOrders(limit);
  }
}
