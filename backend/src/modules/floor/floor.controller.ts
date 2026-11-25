import { Body, Controller, Delete, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreateAreaDto, CreateTableDto, TableStatusDto, UpdateAreaDto, UpdateTableDto } from './dto/floor.dto';
import { FloorService } from './floor.service';

@ApiTags('floor')
@ApiBearerAuth()
@Controller()
export class FloorController {
  constructor(private readonly floor: FloorService) {}

  @Get('areas')
  @Can('sales.orders.take', 'VIEW')
  listAreas(@CurrentUser() auth: AuthUser) {
    return this.floor.listAreas(auth);
  }

  @Post('areas')
  @Can('admin.settings', 'EDIT')
  createArea(@Body() dto: CreateAreaDto, @CurrentUser() auth: AuthUser) {
    return this.floor.createArea(dto, auth);
  }

  @Patch('areas/:id')
  @Can('admin.settings', 'EDIT')
  updateArea(@Param('id') id: string, @Body() dto: UpdateAreaDto, @CurrentUser() auth: AuthUser) {
    return this.floor.updateArea(id, dto, auth);
  }

  @Delete('areas/:id')
  @Can('admin.settings', 'EDIT')
  removeArea(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.floor.removeArea(id, auth);
  }

  @Get('tables')
  @Can('sales.orders.take', 'VIEW')
  @ApiOperation({ summary: 'Live floor view: tables with their open order' })
  listTables(@CurrentUser() auth: AuthUser) {
    return this.floor.listTables(auth);
  }

  @Post('tables')
  @Can('admin.settings', 'EDIT')
  createTable(@Body() dto: CreateTableDto, @CurrentUser() auth: AuthUser) {
    return this.floor.createTable(dto, auth);
  }

  @Patch('tables/:id')
  @Can('admin.settings', 'EDIT')
  updateTable(@Param('id') id: string, @Body() dto: UpdateTableDto, @CurrentUser() auth: AuthUser) {
    return this.floor.updateTable(id, dto, auth);
  }

  @Delete('tables/:id')
  @Can('admin.settings', 'EDIT')
  removeTable(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.floor.removeTable(id, auth);
  }

  @Patch('tables/:id/status')
  @Can('sales.orders.take', 'EDIT')
  setStatus(@Param('id') id: string, @Body() dto: TableStatusDto, @CurrentUser() auth: AuthUser) {
    return this.floor.setStatus(id, dto, auth);
  }
}
