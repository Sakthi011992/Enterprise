import { Injectable } from '@nestjs/common';
import { OrderDiscount, OrderItem, Payment, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { DayFacts } from './day-totals';

/** Data access for the day-close reports: orders of a business window, their lines, and saved Z closes. */
@Injectable()
export class DayCloseRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  async outletTimezone(outletId: string): Promise<string> {
    const outlet = await this.prisma.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
    return outlet?.timezone ?? 'Asia/Kolkata';
  }

  async outletCountry(outletId: string): Promise<string> {
    const s = await this.prisma.outletSettings.findUnique({ where: { outletId }, select: { countryCode: true } });
    return s?.countryCode ?? 'IN';
  }

  ordersInWindow(tx: Prisma.TransactionClient, outletId: string, start: Date, end: Date) {
    return tx.order.findMany({
      where: { outletId, createdAt: { gte: start, lt: end } },
      orderBy: { createdAt: 'asc' },
    });
  }

  /** Everything the totals need for a set of orders, loaded with scalar queries. */
  async factsFor(tx: Prisma.TransactionClient, orders: { id: string; type: string; status: string; subtotal: Prisma.Decimal; discountTotal: Prisma.Decimal; serviceCharge: Prisma.Decimal; roundOff: Prisma.Decimal; grandTotal: Prisma.Decimal; taxBreakdown: Prisma.JsonValue | null }[], businessDate: string): Promise<DayFacts> {
    const orderIds = orders.map((o) => o.id);
    const payments: Payment[] = orderIds.length ? await tx.payment.findMany({ where: { orderId: { in: orderIds } } }) : [];
    const items: OrderItem[] = orderIds.length ? await tx.orderItem.findMany({ where: { orderId: { in: orderIds } } }) : [];
    const discounts: OrderDiscount[] = orderIds.length
      ? await tx.orderDiscount.findMany({ where: { orderId: { in: orderIds } } })
      : [];

    const productIds = [...new Set(items.map((i) => i.productId))];
    const products = productIds.length
      ? await tx.product.findMany({ where: { id: { in: productIds } }, select: { id: true, categoryId: true } })
      : [];
    const categoryIds = [...new Set(products.map((p) => p.categoryId).filter((x): x is string => !!x))];
    const categories = categoryIds.length
      ? await tx.category.findMany({ where: { id: { in: categoryIds } }, select: { id: true, name: true } })
      : [];

    const userIds = [...new Set(discounts.map((d) => d.createdById))];
    const users = userIds.length
      ? await tx.user.findMany({ where: { id: { in: userIds } }, select: { id: true, displayName: true, username: true } })
      : [];

    return {
      businessDate,
      orders: orders.map((o) => ({
        id: o.id,
        status: o.status,
        type: o.type,
        subtotal: o.subtotal,
        discountTotal: o.discountTotal,
        serviceCharge: o.serviceCharge,
        roundOff: o.roundOff,
        grandTotal: o.grandTotal,
        taxBreakdown: o.taxBreakdown,
      })),
      payments: payments.map((p) => ({
        orderId: p.orderId,
        paymentMethod: p.paymentMethod,
        amount: p.amount,
        tipAmount: p.tipAmount,
        status: p.status,
      })),
      items: items.map((i) => ({
        orderId: i.orderId,
        productId: i.productId,
        quantity: i.quantity,
        net: i.grossAmount.sub(i.discountAmount),
        status: i.status,
      })),
      discounts: discounts.map((d) => ({ orderId: d.orderId, amount: d.amount, createdById: d.createdById })),
      categoryOfProduct: new Map(products.map((p) => [p.id, p.categoryId])),
      categoryNames: new Map(categories.map((c) => [c.id, c.name])),
      userNames: new Map(users.map((u) => [u.id, u.displayName ?? u.username])),
    };
  }

  findZClose(tx: Prisma.TransactionClient, outletId: string, businessDate: Date) {
    return tx.dayClose.findFirst({ where: { outletId, kind: 'Z', businessDate } });
  }

  createDayClose(tx: Prisma.TransactionClient, data: Prisma.DayCloseUncheckedCreateInput) {
    return tx.dayClose.create({ data });
  }

  /** Links the given orders to a day close (the Z report). */
  linkOrders(tx: Prisma.TransactionClient, orderIds: string[], dayCloseId: string) {
    return tx.order.updateMany({ where: { id: { in: orderIds } }, data: { dayCloseId } });
  }

  listDayCloses(outletId: string, take: number) {
    return this.prisma.dayClose.findMany({ where: { outletId }, orderBy: { createdAt: 'desc' }, take });
  }
}
