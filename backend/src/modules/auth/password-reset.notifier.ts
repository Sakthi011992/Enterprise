import { Injectable, Logger } from '@nestjs/common';

export const PASSWORD_RESET_NOTIFIER = 'PASSWORD_RESET_NOTIFIER';

export interface PasswordResetTarget {
  userId: string;
  username: string;
  email: string | null;
}

/** Delivers a password reset link. Phase 1 uses the logger; later phases can send email. */
export interface PasswordResetNotifier {
  notify(target: PasswordResetTarget, resetUrl: string): Promise<void>;
}

@Injectable()
export class LoggerPasswordResetNotifier implements PasswordResetNotifier {
  private readonly logger = new Logger('PasswordReset');

  async notify(target: PasswordResetTarget, resetUrl: string): Promise<void> {
    this.logger.log(`Password reset link for user ${target.username}: ${resetUrl}`);
  }
}
