import { Body, Controller, Get, HttpCode, Ip, Param, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { GuestStartDto, GuestVerifyDto } from './dto/guest-auth.dto';
import { GuestAuthService } from './guest-auth.service';

@ApiTags('guest')
@Public()
@Controller('guest/t/:qrToken')
export class GuestAuthController {
  constructor(private readonly auth: GuestAuthService) {}

  @Get()
  lookup(@Param('qrToken') qrToken: string) {
    return this.auth.lookup(qrToken);
  }

  @Post('start')
  @HttpCode(200)
  start(@Param('qrToken') qrToken: string, @Body() dto: GuestStartDto, @Ip() ip: string) {
    return this.auth.start(qrToken, dto, ip);
  }

  @Post('verify')
  @HttpCode(200)
  verify(@Param('qrToken') qrToken: string, @Body() dto: GuestVerifyDto) {
    return this.auth.verify(qrToken, dto);
  }
}
