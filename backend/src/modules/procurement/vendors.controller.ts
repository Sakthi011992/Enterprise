import { Body, Controller, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { VendorDto, VendorsQueryDto } from './dto/procurement.dto';
import { VendorsService } from './vendors.service';

@ApiTags('procurement')
@ApiBearerAuth()
@Controller('vendors')
export class VendorsController {
  constructor(private readonly vendors: VendorsService) {}

  @Get()
  @Can('stock.purchaseOrders', 'VIEW')
  list(@Query() q: VendorsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.vendors.list(q, auth);
  }

  @Post()
  @Can('stock.purchaseOrders', 'EDIT')
  create(@Body() dto: VendorDto, @CurrentUser() auth: AuthUser) {
    return this.vendors.create(dto, auth);
  }

  @Put(':id')
  @Can('stock.purchaseOrders', 'EDIT')
  update(@Param('id') id: string, @Body() dto: VendorDto, @CurrentUser() auth: AuthUser) {
    return this.vendors.update(id, dto, auth);
  }
}
