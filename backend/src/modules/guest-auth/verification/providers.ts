import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { timingSafeEqual } from 'crypto';
import { apiError } from '../../../common/filters/api-error';
import { VerificationContext, VerificationProvider, VerificationStartResult } from './verification-provider';

/** Guest types the admin-set code; compared with the bcrypt hash in GuestConfig. */
@Injectable()
export class StaticOtpProvider implements VerificationProvider {
  readonly method = 'STATIC_OTP' as const;

  async start(ctx: VerificationContext): Promise<VerificationStartResult> {
    if (!ctx.config.verification.staticOtpHash) {
      throw apiError(503, 'NOT_CONFIGURED', 'Guest verification is not set up. Please ask staff.');
    }
    return { codeHash: null };
  }

  async check(ctx: VerificationContext, code: string): Promise<boolean> {
    const hash = ctx.config.verification.staticOtpHash;
    if (!hash || !/^\d+$/.test(code)) return false;
    return bcrypt.compare(code, hash);
  }
}

/** Guest types the 4-digit PIN staff see for the seated table. */
@Injectable()
export class TablePinProvider implements VerificationProvider {
  readonly method = 'TABLE_PIN' as const;

  async start(): Promise<VerificationStartResult> {
    return { codeHash: null };
  }

  async check(ctx: VerificationContext, code: string): Promise<boolean> {
    const pin = ctx.table.guestPin;
    if (!pin || code.length !== pin.length) return false;
    return timingSafeEqual(Buffer.from(code), Buffer.from(pin));
  }
}

/** Placeholder until an SMS provider is integrated. */
@Injectable()
export class SmsOtpProvider implements VerificationProvider {
  readonly method = 'SMS_OTP' as const;

  async start(): Promise<VerificationStartResult> {
    throw apiError(501, 'NOT_AVAILABLE', 'SMS verification is not available yet');
  }

  async check(): Promise<boolean> {
    throw apiError(501, 'NOT_AVAILABLE', 'SMS verification is not available yet');
  }
}
