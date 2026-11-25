import { Body, Controller, Get, Param, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Can } from '../../common/decorators/can.decorator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { PutRecipesDto } from './dto/recipes.dto';
import { RecipesService } from './recipes.service';

/** Product recipes (PLAN.md 1.7). GET also needs menu.edit VIEW (checked in the service). */
@ApiTags('inventory')
@ApiBearerAuth()
@Controller('products/:id/recipes')
export class RecipesController {
  constructor(private readonly recipes: RecipesService) {}

  @Get()
  @Can('stock.count', 'VIEW')
  get(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.recipes.get(id, auth);
  }

  @Put()
  @Can('menu.edit', 'EDIT')
  replace(@Param('id') id: string, @Body() dto: PutRecipesDto, @CurrentUser() auth: AuthUser) {
    return this.recipes.replace(id, dto, auth);
  }
}
