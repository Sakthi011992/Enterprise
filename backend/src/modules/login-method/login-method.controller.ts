import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { LoginMethod } from '@prisma/client';
import { LoginMethodService } from './login-method.service';
import { OAuthLoginService } from './oauth-login.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('auth')
@Controller('auth/login-methods')
@UseGuards(JwtAuthGuard, RolesGuard)
export class LoginMethodController {
  constructor(
    private methodSvc: LoginMethodService,
    private oauthSvc: OAuthLoginService,
  ) {}

  @Public()
  @Get()
  getEnabled() {
    return this.methodSvc.getEnabled();
  }

  @Roles('ADMIN')
  @Get('config')
  getAll() {
    return this.methodSvc.getAll();
  }

  @Roles('ADMIN')
  @Post('config/:method')
  setEnabled(
    @Param('method') method: LoginMethod,
    @Body() body: { enabled: boolean },
  ) {
    return this.methodSvc.setEnabled(method, body.enabled);
  }

  @Public()
  @Post('google/token')
  googleToken(@Body() body: { idToken: string }) {
    return this.oauthSvc.loginWithGoogleToken(body.idToken);
  }
}
