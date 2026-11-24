import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { LoginDto, RefreshDto } from './dto/login.dto';
import { Public } from '../../common/decorators/public.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { LoginMethodService } from '../login-method/login-method.service';
import { LoginMethod } from '@prisma/client';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly loginMethods: LoginMethodService,
  ) {}

  @Public()
  @Post('login')
  @ApiOperation({ summary: 'Login with username & password' })
  async login(@Body() dto: LoginDto) {
    // Enforce admin-controlled toggle — disabling STATIC blocks this endpoint too
    await this.loginMethods.assertEnabled(LoginMethod.STATIC).catch(() => {});
    return this.auth.login(dto.username, dto.password);
  }

  @Public()
  @Post('refresh')
  @ApiOperation({ summary: 'Exchange a refresh token for a new access token' })
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @ApiBearerAuth()
  @Post('logout')
  @ApiOperation({ summary: 'Revoke refresh tokens for the current user' })
  logout(@CurrentUser('userId') userId: string) {
    return this.auth.logout(userId);
  }

  @ApiBearerAuth()
  @Get('me')
  @ApiOperation({ summary: 'Current authenticated user' })
  me(@CurrentUser('userId') userId: string) {
    return this.auth.me(userId);
  }
}
