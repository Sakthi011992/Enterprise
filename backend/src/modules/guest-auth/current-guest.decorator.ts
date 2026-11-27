import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { GuestPrincipal } from './guest-auth.guard';

/** The verified guest on a @GuestRoute() handler (set by GuestAuthGuard). */
export const CurrentGuest = createParamDecorator(
  (data: keyof GuestPrincipal | undefined, ctx: ExecutionContext): GuestPrincipal | any => {
    const guest = ctx.switchToHttp().getRequest().guest as GuestPrincipal;
    return data ? guest?.[data] : guest;
  },
);
