import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { MenuService } from './menu.service';

@ApiTags('menu')
@ApiBearerAuth()
@Controller('menu')
export class MenuController {
  constructor(private readonly menu: MenuService) {}

  @Get('pos')
  @Can('sales.orders.take', 'VIEW')
  @ApiOperation({ summary: 'Menu, modifiers, combos, happy hour, tax classes and settings for the POS in one call' })
  pos(@CurrentUser() auth: AuthUser) {
    return this.menu.pos(auth);
  }
}
