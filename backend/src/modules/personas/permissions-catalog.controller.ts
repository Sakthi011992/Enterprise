import { Controller, Get } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { PermissionsService } from './permissions.service';
import { Can } from '../../common/decorators/can.decorator';

@ApiTags('permissions')
@ApiBearerAuth()
@Controller('permissions')
export class PermissionsCatalogController {
  constructor(private readonly permissions: PermissionsService) {}

  @Get('catalog')
  @Can('admin.users', 'VIEW')
  @ApiOperation({ summary: 'Permission catalog: keys, groups, labels and limit units' })
  catalog() {
    return this.permissions.catalog();
  }
}
