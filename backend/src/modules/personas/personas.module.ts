import { Module } from '@nestjs/common';
import { PersonasController } from './personas.controller';
import { PermissionsCatalogController } from './permissions-catalog.controller';
import { PersonasService } from './personas.service';

// PermissionsService comes from the global PermissionsModule.
@Module({
  controllers: [PersonasController, PermissionsCatalogController],
  providers: [PersonasService],
})
export class PersonasModule {}
