import { Injectable } from '@nestjs/common';
import { apiError } from '../../../common/filters/api-error';

/** Injection token for the online payment gateway (PLAN Q-2: placeholder only in Phase 4). */
export const PAYMENT_GATEWAY = 'PAYMENT_GATEWAY';

/**
 * Online payment gateway port. A real provider (later phase) implements both methods; until then
 * NotConfiguredGateway is bound and every call fails with 501 NOT_AVAILABLE. There is no webhook route.
 */
export interface PaymentGateway {
  createIntent(orderId: string): Promise<never>;
  verifyWebhook(req: unknown): Promise<never>;
}

@Injectable()
export class NotConfiguredGateway implements PaymentGateway {
  async createIntent(_orderId: string): Promise<never> {
    throw apiError(501, 'NOT_AVAILABLE', 'Online payment is not available yet. Please ask your waiter for the bill.');
  }

  async verifyWebhook(_req: unknown): Promise<never> {
    throw apiError(501, 'NOT_AVAILABLE', 'Online payment is not configured');
  }
}

export const paymentGatewayProvider = { provide: PAYMENT_GATEWAY, useClass: NotConfiguredGateway };
