import { Global, Module } from '@nestjs/common';
import { PermissionsService } from './permissions.service';
import { PersonasRepository } from './personas.repository';

/** Global so the PermissionGuard, JwtStrategy and feature services can use it anywhere. */
@Global()
@Module({
  providers: [PersonasRepository, PermissionsService],
  exports: [PersonasRepository, PermissionsService],
})
export class PermissionsModule {}
