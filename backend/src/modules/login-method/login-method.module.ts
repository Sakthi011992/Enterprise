import { Module, forwardRef } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { LoginMethodService } from './login-method.service';
import { LoginMethodRepository } from './login-method.repository';
import { OAuthLoginService } from './oauth-login.service';
import { OAuthRepository } from './oauth.repository';
import { LoginMethodController } from './login-method.controller';
import { AuthModule } from '../auth/auth.module';

// AuthModule imports this module for LoginMethodService, hence forwardRef on both sides.
@Module({
  imports: [ConfigModule, forwardRef(() => AuthModule)],
  controllers: [LoginMethodController],
  providers: [LoginMethodService, LoginMethodRepository, OAuthLoginService, OAuthRepository],
  exports: [LoginMethodService],
})
export class LoginMethodModule {}
