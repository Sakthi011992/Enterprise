/** App-level guest ordering configuration (docs/phase-4/PLAN.md 2.1). One row per tenant. */

export type GuestRouting = 'DIRECT' | 'WAITER';
export type GuestVerificationMethod = 'STATIC_OTP' | 'TABLE_PIN' | 'SMS_OTP';
export type GuestCheckoutMode = 'WAITER' | 'ONLINE' | 'BOTH';

export const GUEST_ROUTINGS: readonly GuestRouting[] = ['DIRECT', 'WAITER'];
export const GUEST_VERIFICATION_METHODS: readonly GuestVerificationMethod[] = ['STATIC_OTP', 'TABLE_PIN', 'SMS_OTP'];
export const GUEST_CHECKOUT_MODES: readonly GuestCheckoutMode[] = ['WAITER', 'ONLINE', 'BOTH'];

/** Table PIN length is fixed; the static OTP length is configurable. */
export const TABLE_PIN_LENGTH = 4;

/** Seeded static OTP (printed in the seed log). Stored only as a bcrypt hash. */
export const DEFAULT_STATIC_OTP = '246810';

/** Full stored shape, including the OTP hash. Internal use only, never returned by the API. */
export interface GuestConfigData {
  enabled: boolean;
  routing: GuestRouting;
  verification: {
    method: GuestVerificationMethod;
    /** bcrypt hash of the static OTP, or null when none has been set. */
    staticOtpHash: string | null;
    /** Length of the static OTP (4 to 8 digits). */
    codeLength: number;
  };
  ageGate: boolean;
  minAge: number;
  requireSeated: boolean;
  requestTtlMinutes: number;
  maxQtyPerLine: number;
  maxLinesPerRound: number;
  allowGuestCancel: boolean;
  checkout: GuestCheckoutMode;
}

/** What GET/PUT /settings/guest return: the OTP hash is replaced by `hasStaticOtp`. */
export interface GuestConfigView extends Omit<GuestConfigData, 'verification'> {
  verification: { method: GuestVerificationMethod; codeLength: number; hasStaticOtp: boolean };
  updatedAt: Date | null;
  updatedById: string | null;
}

export const DEFAULT_GUEST_CONFIG: GuestConfigData = {
  enabled: true,
  routing: 'WAITER',
  verification: { method: 'STATIC_OTP', staticOtpHash: null, codeLength: 6 },
  ageGate: true,
  minAge: 25,
  requireSeated: true,
  requestTtlMinutes: 10,
  maxQtyPerLine: 10,
  maxLinesPerRound: 20,
  allowGuestCancel: true,
  checkout: 'WAITER',
};

/** Length of the code a guest types for the given method. */
export function effectiveCodeLength(cfg: GuestConfigData): number {
  return cfg.verification.method === 'TABLE_PIN' ? TABLE_PIN_LENGTH : cfg.verification.codeLength;
}

/** Merges a stored JSON blob over the defaults, so missing keys (older rows) get default values. */
export function withDefaults(raw: unknown): GuestConfigData {
  const r = (raw && typeof raw === 'object' ? raw : {}) as Partial<GuestConfigData> & Record<string, any>;
  const v = (r.verification && typeof r.verification === 'object' ? r.verification : {}) as Partial<
    GuestConfigData['verification']
  >;
  return {
    ...DEFAULT_GUEST_CONFIG,
    ...r,
    verification: {
      ...DEFAULT_GUEST_CONFIG.verification,
      ...v,
      staticOtpHash: v.staticOtpHash ?? null,
    },
  } as GuestConfigData;
}
