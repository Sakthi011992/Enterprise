import { Global, Module } from '@nestjs/common';
import { GuestAuthModule } from '../guest-auth/guest-auth.module';
import { GuestHooks } from './guest-hooks.service';
import { GuestLifecycleService } from './guest-lifecycle.service';
import { GuestRepository } from './guest.repository';

/**
 * Global: the hooks the order, KDS, payment and
 * floor services call, and the session lifecycle. Has no dependency on those modules, so no cycles.
 */
@Global()
@Module({
  imports: [GuestAuthModule],
  providers: [
    GuestRepository,
    GuestLifecycleService,
    GuestHooks,
  ],
  exports: [GuestRepository, GuestLifecycleService, GuestHooks, GuestAuthModule],
})
export class GuestCoreModule {}
