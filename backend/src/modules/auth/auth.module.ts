import { Module, forwardRef } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigModule } from '@nestjs/config';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { AuthRepository } from './auth.repository';
import { JwtStrategy } from './jwt.strategy';
import { DeviceAuthService } from './device-auth.service';
import { LoggerPasswordResetNotifier, PASSWORD_RESET_NOTIFIER } from './password-reset.notifier';
import { LoginMethodModule } from '../login-method/login-method.module';

// LoginMethodModule imports this module back (OAuth login returns the shared session), hence forwardRef.
@Module({
  imports: [ConfigModule, PassportModule, JwtModule.register({}), forwardRef(() => LoginMethodModule)],
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthRepository,
    JwtStrategy,
    DeviceAuthService,
    { provide: PASSWORD_RESET_NOTIFIER, useClass: LoggerPasswordResetNotifier },
  ],
  exports: [AuthService, AuthRepository, DeviceAuthService],
})
export class AuthModule {}
