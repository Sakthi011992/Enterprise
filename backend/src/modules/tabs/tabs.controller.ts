import { Body, Controller, Get, Param, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { MoveTabDto, OpenTabDto, TabQueryDto, UpdateTabDto, VoidTabDto } from './dto/tab.dto';
import { TabsService } from './tabs.service';

@ApiTags('tabs')
@ApiBearerAuth()
@Controller('tabs')
export class TabsController {
  constructor(private readonly tabs: TabsService) {}

  @Can('sales.tab.open', 'VIEW')
  @Get()
  @ApiOperation({ summary: 'Bar tabs with today\'s counts (open, near limit, closed today)' })
  list(@Query() q: TabQueryDto, @CurrentUser() auth: AuthUser) {
    return this.tabs.list(q, auth);
  }

  @Can('sales.tab.open', 'VIEW')
  @Get(':id')
  @ApiOperation({ summary: 'One tab with its order' })
  findOne(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.tabs.findOne(id, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Post()
  @ApiOperation({ summary: 'Open a bar tab (age check, security, limit)' })
  open(@Body() dto: OpenTabDto, @CurrentUser() auth: AuthUser) {
    return this.tabs.open(dto, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Put(':id')
  @ApiOperation({ summary: 'Change guest details, limit, warning level or link' })
  update(@Param('id') id: string, @Body() dto: UpdateTabDto, @CurrentUser() auth: AuthUser) {
    return this.tabs.update(id, dto, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Post(':id/move-to-table')
  @ApiOperation({ summary: 'Put the tab on a table (order becomes dine-in)' })
  moveToTable(@Param('id') id: string, @Body() dto: MoveTabDto, @CurrentUser() auth: AuthUser) {
    return this.tabs.moveToTable(id, dto, auth);
  }

  @Can('sales.payments.take', 'EDIT')
  @Post(':id/close')
  @ApiOperation({ summary: 'Bill the tab and apply a cash deposit; the tab closes when paid' })
  close(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.tabs.close(id, auth);
  }

  @Can('sales.tab.open', 'LIMITED')
  @Post(':id/void')
  @ApiOperation({ summary: 'Void an empty tab' })
  voidTab(@Param('id') id: string, @Body() dto: VoidTabDto, @CurrentUser() auth: AuthUser) {
    return this.tabs.voidTab(id, dto, auth);
  }
}
