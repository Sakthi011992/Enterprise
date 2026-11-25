import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { CAN_KEY, CanRequirement } from '../decorators/can.decorator';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { apiError } from '../filters/api-error';
import { PermissionsService } from '../../modules/personas/permissions.service';

/**
 * Global guard, registered after JwtAuthGuard. Checks the @Can requirement of
 * the handler (or its class) against the permission matrix on request.user.
 */
@Injectable()
export class PermissionGuard implements CanActivate {
  constructor(
    private reflector: Reflector,
    private permissions: PermissionsService,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const rule = this.reflector.getAllAndOverride<CanRequirement | undefined>(CAN_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!rule) return true;

    const { user } = context.switchToHttp().getRequest();
    if (!user) throw new UnauthorizedException('Authentication required');

    if (!this.permissions.check(user, rule.key, rule.min)) {
      throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', {
        permission: rule.key,
        required: rule.min,
      });
    }
    return true;
  }
}
