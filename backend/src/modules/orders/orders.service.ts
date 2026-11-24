import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { TaxService } from '../tax/tax.service';
import { buildMeta } from '../../common/dto/pagination.dto';
import { computeLine, computeOrderTotals } from '../../common/utils/money.util';
import { CreateOrderDto, OrderQueryDto } from './dto/order.dto';
import { OrdersRepository } from './orders.repository';

@Injectable()
export class OrdersService {
  constructor(private repo: OrdersRepository, private tax: TaxService) {}

  private async nextInvoiceNumber(prefix = 'INV'): Promise<string> {
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    const count = await this.repo.countToday(start, end);
    const datePart = `${start.getFullYear()}${String(start.getMonth() + 1).padStart(2, '0')}${String(start.getDate()).padStart(2, '0')}`;
    return `${prefix}-${datePart}-${String(count + 1).padStart(4, '0')}`;
  }

  async create(dto: CreateOrderDto, cashierId: string) {
    const productIds = dto.items.map((i) => i.productId);
    // ProductsRepository is not injected here to keep coupling minimal — orders
    // need a quick fetch of active products, which is a read-only concern.
    // A dedicated OrdersRepository method would be cleaner but overkill for now.
    const products = await this.repo.findProductsByIds(productIds);
    const map = new Map(products.map((p: any) => [p.id, p]));

    const missing = productIds.filter((id) => !map.has(id));
    if (missing.length) throw new BadRequestException(`Unavailable products: ${missing.join(', ')}`);

    const globalTax = (await this.tax.getGlobalTax()).percentage as Prisma.Decimal;

    const itemRows = dto.items.map((item) => {
      const product = map.get(item.productId)!;
      const rate = this.tax.resolveRate(product.taxPercentage, globalTax);
      const { lineSubtotal, taxAmount, lineTotal } = computeLine({
        price: product.price,
        quantity: item.quantity,
        taxPercentage: rate,
      });
      return {
        productId: product.id,
        productName: product.name,
        price: product.price,
        quantity: item.quantity,
        taxPercentage: rate,
        taxAmount,
        lineTotal,
        _lineSubtotal: lineSubtotal,
      };
    });

    const totals = computeOrderTotals(
      itemRows.map((r) => ({ lineSubtotal: r._lineSubtotal, taxAmount: r.taxAmount })),
    );
    const invoiceNumber = await this.nextInvoiceNumber(process.env.INVOICE_PREFIX || 'INV');

    return this.repo.create({
      invoiceNumber,
      cashier: { connect: { id: cashierId } },
      subtotal: totals.subtotal,
      taxAmount: totals.taxAmount,
      grandTotal: totals.grandTotal,
      status: 'PENDING',
      items: {
        create: itemRows.map(({ _lineSubtotal, ...row }) => row),
      },
    });
  }

  async findAll(q: OrderQueryDto) {
    const where: Prisma.OrderWhereInput = {
      ...(q.search ? { invoiceNumber: { contains: q.search, mode: 'insensitive' } } : {}),
      ...(q.from || q.to
        ? { createdAt: { ...(q.from ? { gte: new Date(q.from) } : {}), ...(q.to ? { lte: new Date(q.to) } : {}) } }
        : {}),
    };
    const [data, total] = await this.repo.findAll(where, q.skip, q.limit);
    return { data, meta: buildMeta(total, q.page, q.limit) };
  }

  async findOne(id: string) {
    const order = await this.repo.findOne(id);
    if (!order) throw new NotFoundException('Order not found');
    return order;
  }
}
