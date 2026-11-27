import { Injectable } from '@nestjs/common';
import { GuestAuthRepository } from './guest-auth.repository';
import { newGuestPin } from './guest-utils';

/**
 * Table PIN helper for G-B (PLAN 2.3). G-B calls `generate(tableId)` when staff seat a table in
 * TABLE_PIN mode and `clear(tableId)` when the session closes.
 */
@Injectable()
export class GuestPinService {
  constructor(private repo: GuestAuthRepository) {}

  /** Sets a fresh random 4-digit PIN on the table and returns it. */
  async generate(tableId: string): Promise<string> {
    const pin = newGuestPin();
    await this.repo.setGuestPin(tableId, pin);
    return pin;
  }

  async clear(tableId: string): Promise<void> {
    await this.repo.setGuestPin(tableId, null);
  }
}
