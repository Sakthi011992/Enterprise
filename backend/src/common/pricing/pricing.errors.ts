export type PricingErrorCode =
  | 'LIQUOR_DISCOUNT_NOT_ALLOWED'
  | 'INVALID_DISCOUNT'
  | 'UNKNOWN_DISCOUNT_ITEM'
  | 'DUPLICATE_LINE_ID'
  | 'INVALID_QUANTITY'
  | 'INVALID_PERCENT'
  | 'INVALID_TIME'
  | 'TAX_COMPONENTS_MISMATCH';

/** Thrown by the pricing engine and schedule helpers. Services map `code` to API errors. */
export class PricingError extends Error {
  constructor(
    public readonly code: PricingErrorCode,
    message?: string,
  ) {
    super(message ?? code);
    this.name = 'PricingError';
  }
}
