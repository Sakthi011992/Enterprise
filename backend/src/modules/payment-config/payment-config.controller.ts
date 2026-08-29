import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { PaymentMethod } from '@prisma/client';
import { PaymentConfigService } from './payment-config.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('payment-config')
@Controller('payments/methods')
@UseGuards(JwtAuthGuard, RolesGuard)
export class PaymentConfigController {
  constructor(private svc: PaymentConfigService) {}

  @Public()
  @Get(':storeId')
  getEnabled(@Param('storeId') storeId: string) {
    return this.svc.getEnabledMethods(storeId);
  }

  @Roles('ADMIN')
  @Get(':storeId/config')
  getAll(@Param('storeId') storeId: string) {
    return this.svc.getAllConfigs(storeId);
  }

  @Roles('ADMIN')
  @Post(':storeId/config')
  setEnabled(
    @Param('storeId') storeId: string,
    @Body() body: { method: PaymentMethod; enabled: boolean },
  ) {
    return this.svc.setEnabled(storeId, body.method, body.enabled);
  }
}
