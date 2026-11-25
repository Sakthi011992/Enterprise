import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { apiError } from '../../common/filters/api-error';
import { PricingInput } from '../../common/pricing/pricing.engine';
import {
  discountAmounts,
  frozenLineInput,
  pricingDiscounts,
  readStoredTax,
  runPricing,
  serializeComponents,
  serviceChargeFor,
} from './order-pricing';
import { OrdersRepository } from './orders.repository';
import { OrderBundle } from './order-view';

const json = (v: unknown) => v as Prisma.InputJsonValue;

/**
 * Re-prices an order from its lines, discounts and outlet settings (PLAN.md 1.3) and writes the line
 * and order totals. Every order mutation calls recalc() inside its transaction.
 */
@Injectable()
export class OrderPricingService {
  constructor(private repo: OrdersRepository) {}

  /** The engine input for the bundle as it stands, plus the discount row id behind each engine discount. */
  async inputFor(tx: Prisma.TransactionClient, b: OrderBundle) {
    const settings = await this.repo.getOutletSettings(tx, b.order.outletId);
    const live = new Set(b.items.filter((i) => i.status !== 'VOIDED').map((i) => i.id));
    const { inputs, rowIds } = pricingDiscounts(b.discounts, live);
    const input: PricingInput = {
      lines: b.items.map(frozenLineInput),
      discounts: inputs,
      serviceChargePercent: serviceChargeFor(b.order.type, settings),
      roundingMode: settings.roundingMode,
    };
    return { input, rowIds };
  }

  /** The discountable base (non-liquor net before discounts), used for the LIMITED percent check. */
  async discountableBase(tx: Prisma.TransactionClient, b: OrderBundle): Promise<Prisma.Decimal> {
    const { input } = await this.inputFor(tx, { ...b, discounts: [] });
    return runPricing({ ...input, discounts: [] }).discountableBase;
  }

  /** Re-prices the order and returns the bundle as saved. Throws 400 with the engine code on a pricing rule breach. */
  async recalc(tx: Prisma.TransactionClient, orderId: string): Promise<OrderBundle> {
    const b = await this.repo.loadBundle(tx, orderId);
    if (!b) throw apiError(404, 'ORDER_NOT_FOUND', 'Order not found');

    const { input, rowIds } = await this.inputFor(tx, b);
    const result = runPricing(input);
    const amounts = discountAmounts(input);

    const byId = new Map(b.items.map((i) => [i.id, i]));
    for (const line of result.lines) {
      const item = byId.get(line.id);
      if (!item) continue;
      await this.repo.updateItem(tx, item.id, {
        grossAmount: line.gross,
        discountAmount: line.discount,
        taxAmount: line.tax,
        lineTotal: line.total,
        taxBreakdown: json({
          snapshot: readStoredTax(item.taxBreakdown).snapshot,
          components: serializeComponents(line.taxBreakdown),
        }),
      });
    }

    for (const d of b.discounts) {
      const k = rowIds.indexOf(d.id);
      const amount = k >= 0 ? amounts[k] : new Prisma.Decimal(0);
      if (!amount.equals(d.amount)) await this.repo.updateDiscount(tx, d.id, { amount });
    }

    await this.repo.updateOrder(tx, orderId, {
      subtotal: result.subtotal,
      discountTotal: result.discountTotal,
      serviceCharge: result.serviceCharge,
      taxAmount: result.taxTotal,
      taxBreakdown: json(serializeComponents(result.taxBreakdown)),
      roundOff: result.roundOff,
      grandTotal: result.grandTotal,
    });

    const saved = await this.repo.loadBundle(tx, orderId);
    return saved!;
  }
}
