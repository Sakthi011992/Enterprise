import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { ConfigModule } from '@nestjs/config';
import { LoginMethodService } from './login-method.service';
import { OAuthLoginService } from './oauth-login.service';
import { LoginMethodController } from './login-method.controller';

@Module({
  imports: [ConfigModule, JwtModule.register({})],
  controllers: [LoginMethodController],
  providers: [LoginMethodService, OAuthLoginService],
  exports: [LoginMethodService],
})
export class LoginMethodModule {}
