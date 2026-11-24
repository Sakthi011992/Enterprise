import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, PaymentStatus, OrderStatus } from '@prisma/client';
import { round2 } from '../../common/utils/money.util';
import { CreatePaymentDto } from './dto/payment.dto';
import { PaymentsRepository } from './payments.repository';

@Injectable()
export class PaymentsService {
  constructor(private repo: PaymentsRepository) {}

  async create(dto: CreatePaymentDto) {
    return this.repo.withTransaction(async (tx) => {
      const order = await this.repo.findOrderWithPayments(dto.orderId);
      if (!order) throw new NotFoundException('Order not found');
      if (order.status === 'REFUNDED') throw new BadRequestException('Order is refunded');

      const alreadyPaid = order.payments
        .filter((p) => p.status !== PaymentStatus.REFUNDED)
        .reduce((sum, p) => sum.add(p.amount), new Prisma.Decimal(0));
      const newPaid = round2(alreadyPaid.add(dto.amount));
      const grand = order.grandTotal as Prisma.Decimal;

      if (newPaid.greaterThan(grand)) {
        throw new BadRequestException(`Payment exceeds balance due (${grand.sub(alreadyPaid).toFixed(2)})`);
      }

      let orderStatus: OrderStatus;
      let paymentStatus: PaymentStatus;
      if (newPaid.greaterThanOrEqualTo(grand)) {
        orderStatus = OrderStatus.PAID;
        paymentStatus = PaymentStatus.PAID;
      } else {
        orderStatus = OrderStatus.PARTIALLY_PAID;
        paymentStatus = PaymentStatus.PARTIALLY_PAID;
      }

      const [payment] = await this.repo.createPaymentAndUpdateOrder(
        tx,
        dto.orderId,
        new Prisma.Decimal(dto.amount),
        dto.paymentMethod,
        paymentStatus,
        orderStatus,
      );
      return { payment, order: { id: order.id, status: orderStatus, paid: newPaid.toFixed(2), grandTotal: grand.toFixed(2) } };
    });
  }

  findByOrder(orderId: string) {
    return this.repo.findByOrder(orderId);
  }

  async refund(paymentId: string) {
    const payment = await this.repo.findPayment(paymentId);
    if (!payment) throw new NotFoundException('Payment not found');
    return this.repo.withTransaction(async (tx) => {
      const [updated] = await this.repo.refundPaymentAndOrder(tx, paymentId, payment.orderId);
      return updated;
    });
  }
}
