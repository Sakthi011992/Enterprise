import { Body, Controller, Delete, Get, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators/public.decorator';
import { CurrentGuest } from '../guest-auth/current-guest.decorator';
import { GuestPrincipal, GuestRoute } from '../guest-auth/guest-auth.guard';
import { CheckoutDto, PlaceRoundDto, ServiceRequestDto } from './dto/guest.dto';
import { GuestOrderingService } from './guest-ordering.service';

@ApiTags('guest')
@Controller('guest')
export class GuestPublicMenuController {
  constructor(private guest: GuestOrderingService) {}

  @Get('t/:qrToken/menu')
  @Public()
  @ApiOperation({ summary: 'Read-only menu for a table (no guest token)' })
  menu(@Param('qrToken') qrToken: string) {
    return this.guest.publicMenu(qrToken);
  }
}

@ApiTags('guest')
@Controller('guest')
@GuestRoute()
export class GuestController {
  constructor(private guest: GuestOrderingService) {}

  @Get('menu')
  menu(@CurrentGuest() g: GuestPrincipal) {
    return this.guest.menu(g);
  }

  @Post('rounds')
  place(@CurrentGuest() g: GuestPrincipal, @Body() dto: PlaceRoundDto) {
    return this.guest.placeRound(g, dto);
  }

  @Delete('rounds/:id')
  cancel(@CurrentGuest() g: GuestPrincipal, @Param('id') id: string) {
    return this.guest.cancelRound(g, id);
  }

  @Get('order')
  order(@CurrentGuest() g: GuestPrincipal) {
    return this.guest.order(g);
  }

  @Post('service-requests')
  serviceRequest(@CurrentGuest() g: GuestPrincipal, @Body() dto: ServiceRequestDto) {
    return this.guest.serviceRequest(g, dto);
  }

  @Post('checkout')
  checkout(@CurrentGuest() g: GuestPrincipal, @Body() dto: CheckoutDto) {
    return this.guest.checkout(g, dto);
  }

  @Post('age-confirm')
  ageConfirm(@CurrentGuest() g: GuestPrincipal) {
    return this.guest.ageConfirm(g);
  }
}
