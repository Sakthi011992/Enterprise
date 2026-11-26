import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { GuestConfigModule } from '../guest-config/guest-config.module';
import { GuestAuthController } from './guest-auth.controller';
import { GuestAuthGuard } from './guest-auth.guard';
import { GuestAuthRepository } from './guest-auth.repository';
import { GuestAuthService } from './guest-auth.service';
import { GuestJwtService } from './guest-jwt.service';
import { GuestPinService } from './guest-pin.service';
import { GuestRateLimiter } from './guest-rate-limiter';
import { SmsOtpProvider, StaticOtpProvider, TablePinProvider } from './verification/providers';
import { VERIFICATION_PROVIDERS } from './verification/verification-provider';

@Module({
  imports: [JwtModule.register({}), GuestConfigModule],
  controllers: [GuestAuthController],
  providers: [
    GuestAuthService,
    GuestAuthRepository,
    GuestJwtService,
    GuestAuthGuard,
    GuestRateLimiter,
    GuestPinService,
    StaticOtpProvider,
    TablePinProvider,
    SmsOtpProvider,
    {
      provide: VERIFICATION_PROVIDERS,
      useFactory: (a: StaticOtpProvider, b: TablePinProvider, c: SmsOtpProvider) => [a, b, c],
      inject: [StaticOtpProvider, TablePinProvider, SmsOtpProvider],
    },
  ],
  exports: [GuestAuthGuard, GuestJwtService, GuestAuthRepository, GuestRateLimiter, GuestPinService, GuestConfigModule],
})
export class GuestAuthModule {}
