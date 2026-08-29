import { Injectable } from '@nestjs/common';
import { Prisma, PaymentStatus, OrderStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class PaymentsRepository {
  constructor(private prisma: PrismaService) {}

  findOrderWithPayments(orderId: string) {
    return this.prisma.order.findUnique({ where: { id: orderId }, include: { payments: true } });
  }

  createPaymentAndUpdateOrder(
    tx: Prisma.TransactionClient,
    orderId: string,
    amount: Prisma.Decimal,
    paymentMethod: string,
    paymentStatus: PaymentStatus,
    orderStatus: OrderStatus,
  ) {
    return Promise.all([
      tx.payment.create({
        data: { orderId, amount, paymentMethod, status: paymentStatus },
      }),
      tx.order.update({ where: { id: orderId }, data: { status: orderStatus } }),
    ]);
  }

  findByOrder(orderId: string) {
    return this.prisma.payment.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } });
  }

  findPayment(paymentId: string) {
    return this.prisma.payment.findUnique({ where: { id: paymentId } });
  }

  refundPaymentAndOrder(tx: Prisma.TransactionClient, paymentId: string, orderId: string) {
    return Promise.all([
      tx.payment.update({ where: { id: paymentId }, data: { status: PaymentStatus.REFUNDED } }),
      tx.order.update({ where: { id: orderId }, data: { status: OrderStatus.REFUNDED } }),
    ]);
  }

  withTransaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>) {
    return this.prisma.$transaction(fn);
  }
}
