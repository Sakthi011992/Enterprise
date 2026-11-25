import { Body, Controller, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { LocationDto, ItemsQueryDto, MovementsQueryDto, ParDto, StockItemDto } from './dto/inventory.dto';
import { StockItemsService } from './stock-items.service';

/** Stock locations, stock items, par levels and item movements (PLAN.md 1.7). Edits accept menu.edit or stock.purchaseOrders EDIT. */
@ApiTags('inventory')
@ApiBearerAuth()
@Controller('stock')
export class StockItemsController {
  constructor(private readonly items: StockItemsService) {}

  @Get('locations')
  @Can('stock.count', 'VIEW')
  listLocations(@CurrentUser() auth: AuthUser) {
    return this.items.listLocations(auth);
  }

  @Post('locations')
  createLocation(@Body() dto: LocationDto, @CurrentUser() auth: AuthUser) {
    return this.items.createLocation(dto, auth);
  }

  @Put('locations/:id')
  updateLocation(@Param('id') id: string, @Body() dto: LocationDto, @CurrentUser() auth: AuthUser) {
    return this.items.updateLocation(id, dto, auth);
  }

  @Get('items')
  @Can('stock.count', 'VIEW')
  list(@Query() q: ItemsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.items.list(q, auth);
  }

  @Post('items')
  create(@Body() dto: StockItemDto, @CurrentUser() auth: AuthUser) {
    return this.items.create(dto, auth);
  }

  @Get('items/:id')
  @Can('stock.count', 'VIEW')
  detail(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.items.detail(id, auth);
  }

  @Put('items/:id')
  update(@Param('id') id: string, @Body() dto: StockItemDto, @CurrentUser() auth: AuthUser) {
    return this.items.update(id, dto, auth);
  }

  @Put('items/:id/par')
  setPar(@Param('id') id: string, @Body() dto: ParDto, @CurrentUser() auth: AuthUser) {
    return this.items.setPar(id, dto, auth);
  }

  @Get('items/:id/movements')
  @Can('stock.count', 'VIEW')
  movements(@Param('id') id: string, @Query() q: MovementsQueryDto, @CurrentUser() auth: AuthUser) {
    return this.items.movements(id, q, auth);
  }
}
