import { Body, Controller, Get, Headers, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiOperation, ApiTags } from '@nestjs/swagger';
import { LoginMethod } from '@prisma/client';
import { AuthService } from './auth.service';
import { DeviceAuthService } from './device-auth.service';
import { LoginDto, RefreshDto } from './dto/login.dto';
import {
  ForgotPasswordDto,
  PinLoginDto,
  ResetPasswordDto,
  SelectOutletDto,
  SwitchOutletDto,
} from './dto/auth.dto';
import { Public } from '../../common/decorators/public.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { LoginMethodService } from '../login-method/login-method.service';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly loginMethods: LoginMethodService,
    private readonly devices: DeviceAuthService,
  ) {}

  @Public()
  @Post('login')
  @ApiOperation({ summary: 'Password login. Returns a session, or needsOutlet when the user must choose an outlet' })
  async login(@Body() dto: LoginDto) {
    // Enforce admin-controlled toggle: disabling STATIC blocks this endpoint too (main's behaviour, unchanged).
    await this.loginMethods.assertEnabled(LoginMethod.STATIC).catch(() => {});
    return this.auth.login(dto.username, dto.password);
  }

  @Public()
  @Post('select-outlet')
  @ApiOperation({ summary: 'Finish login by choosing an outlet (uses the selectionToken)' })
  selectOutlet(@Body() dto: SelectOutletDto) {
    return this.auth.selectOutlet(dto.selectionToken, dto.outletId);
  }

  @ApiBearerAuth()
  @Post('switch-outlet')
  @ApiOperation({ summary: 'Switch the signed-in session to another outlet' })
  switchOutlet(@Body() dto: SwitchOutletDto, @CurrentUser() user: AuthUser) {
    return this.auth.switchOutlet(user, dto.outletId);
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
  logout(@CurrentUser() user: AuthUser) {
    return this.auth.logout(user.userId);
  }

  @ApiBearerAuth()
  @Get('me')
  @ApiOperation({ summary: 'Current session (without tokens)' })
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user);
  }

  @Public()
  @Post('forgot-password')
  @ApiOperation({ summary: 'Request a password reset link. Always returns success' })
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.auth.forgotPassword(dto.usernameOrEmail);
  }

  @Public()
  @Post('reset-password')
  @ApiOperation({ summary: 'Set a new password with a reset token' })
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.auth.resetPassword(dto.token, dto.newPassword);
  }

  @Public()
  @Get('pin/staff')
  @ApiHeader({ name: 'X-Device-Key', required: true })
  @ApiOperation({ summary: 'Staff who can sign in with a PIN on this shared tablet' })
  async pinStaff(@Headers('x-device-key') deviceKey?: string) {
    const device = await this.devices.authenticate(deviceKey);
    return this.auth.pinStaff(device);
  }

  @Public()
  @Post('pin/login')
  @ApiHeader({ name: 'X-Device-Key', required: true })
  @ApiOperation({ summary: 'Sign in with a 4-digit PIN on a registered device' })
  async pinLogin(@Headers('x-device-key') deviceKey: string | undefined, @Body() dto: PinLoginDto) {
    const device = await this.devices.authenticate(deviceKey);
    return this.auth.pinLogin(device, dto);
  }
}
