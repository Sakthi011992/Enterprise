import { Body, Controller, Delete, Get, Param, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CreatePriceRuleDto, UpdatePriceRuleDto } from './dto/price-rule.dto';
import { PriceRulesService } from './price-rules.service';

@ApiTags('menu')
@ApiBearerAuth()
@Controller('price-rules')
export class PriceRulesController {
  constructor(private readonly rules: PriceRulesService) {}

  @Get()
  @Can('menu.edit', 'VIEW')
  list(@CurrentUser() auth: AuthUser) {
    return this.rules.list(auth);
  }

  @Post()
  @Can('menu.edit', 'EDIT')
  create(@Body() dto: CreatePriceRuleDto, @CurrentUser() auth: AuthUser) {
    return this.rules.create(dto, auth);
  }

  @Patch(':id')
  @Can('menu.edit', 'EDIT')
  update(@Param('id') id: string, @Body() dto: UpdatePriceRuleDto, @CurrentUser() auth: AuthUser) {
    return this.rules.update(id, dto, auth);
  }

  @Delete(':id')
  @Can('menu.edit', 'EDIT')
  remove(@Param('id') id: string) {
    return this.rules.remove(id);
  }
}
