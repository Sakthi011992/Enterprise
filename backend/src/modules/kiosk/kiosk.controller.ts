import {
  Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { KioskService } from './kiosk.service';
import { CreateFeaturedItemDto, SetOrderingEnabledDto, UpdateFeaturedItemDto } from './dto/kiosk.dto';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { Roles } from '../../common/decorators/roles.decorator';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Public } from '../../common/decorators/public.decorator';

@ApiTags('kiosk')
@Controller('kiosk')
@UseGuards(JwtAuthGuard, RolesGuard)
export class KioskController {
  constructor(private svc: KioskService) {}

  @Roles('KIOSK')
  @Get('config')
  getConfig(@CurrentUser('userId') userId: string) {
    return this.svc.getConfig(userId);
  }

  @Public()
  @Get('featured')
  getFeatured(@Query('storeId') storeId = 'default') {
    return this.svc.getActiveFeaturedItems(storeId);
  }
}

@ApiTags('kiosk')
@Controller('admin/kiosk')
@UseGuards(JwtAuthGuard, RolesGuard)
export class KioskAdminController {
  constructor(private svc: KioskService) {}

  @Roles('ADMIN')
  @Get('configs')
  listConfigs(@Query('storeId') storeId = 'default') {
    return this.svc.listConfigsForStore(storeId);
  }

  @Roles('ADMIN')
  @Post('devices/:userId')
  createDevice(
    @Param('userId') userId: string,
    @Query('storeId') storeId = 'default',
  ) {
    return this.svc.createDefault(userId, storeId);
  }

  @Roles('ADMIN')
  @Patch('devices/:userId/ordering')
  setOrdering(
    @Param('userId') userId: string,
    @Body() dto: SetOrderingEnabledDto,
  ) {
    return this.svc.setOrderingEnabled(userId, dto.enabled);
  }

  @Roles('ADMIN')
  @Get('featured')
  listFeatured(@Query('storeId') storeId = 'default') {
    return this.svc.listAllFeaturedItems(storeId);
  }

  @Roles('ADMIN')
  @Post('featured')
  createFeatured(@Body() dto: CreateFeaturedItemDto) {
    return this.svc.createFeaturedItem(dto);
  }

  @Roles('ADMIN')
  @Patch('featured/:id')
  updateFeatured(@Param('id') id: string, @Body() dto: UpdateFeaturedItemDto) {
    return this.svc.updateFeaturedItem(id, dto);
  }

  @Roles('ADMIN')
  @Delete('featured/:id')
  deleteFeatured(@Param('id') id: string) {
    return this.svc.deleteFeaturedItem(id);
  }
}
