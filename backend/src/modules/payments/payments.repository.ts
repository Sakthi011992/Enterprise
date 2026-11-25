import { Injectable } from '@nestjs/common';
import { PaymentStatus, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/** Data access for payment rows. Order status and totals are written by the service through OrdersRepository. */
@Injectable()
export class PaymentsRepository {
  constructor(private prisma: PrismaService) {}

  transaction<T>(fn: (tx: Prisma.TransactionClient) => Promise<T>): Promise<T> {
    return this.prisma.$transaction(fn);
  }

  createPayment(tx: Prisma.TransactionClient, data: Prisma.PaymentUncheckedCreateInput) {
    return tx.payment.create({ data });
  }

  findByOrder(orderId: string) {
    return this.prisma.payment.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' } });
  }

  findPayment(paymentId: string) {
    return this.prisma.payment.findUnique({ where: { id: paymentId } });
  }

  /** Legacy full refund: the original payment is marked REFUNDED. */
  markRefunded(tx: Prisma.TransactionClient, paymentId: string) {
    return tx.payment.update({ where: { id: paymentId }, data: { status: PaymentStatus.REFUNDED } });
  }
}
