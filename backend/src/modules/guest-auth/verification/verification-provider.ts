import type { GuestConfigData, GuestVerificationMethod } from '../../guest-config/guest-config.types';

/** What a provider sees when a challenge starts or a code is checked. */
export interface VerificationContext {
  config: GuestConfigData;
  table: { id: string; guestPin: string | null };
  phone: string;
  /** Stored challenge hash (SMS OTP only). */
  codeHash?: string | null;
}

export interface VerificationStartResult {
  /** Saved on the GuestVerification row (SMS OTP: hash of the code sent). */
  codeHash: string | null;
}

/**
 * One way of proving the guest is at the table (PLAN 2.3). Adding SMS OTP later means
 * implementing this interface in SmsOtpProvider and enabling the option in settings.
 */
export interface VerificationProvider {
  readonly method: GuestVerificationMethod;
  start(ctx: VerificationContext): Promise<VerificationStartResult>;
  check(ctx: VerificationContext, code: string): Promise<boolean>;
}

export const VERIFICATION_PROVIDERS = Symbol('VERIFICATION_PROVIDERS');
