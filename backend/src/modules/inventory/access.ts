import { apiError } from '../../common/filters/api-error';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { AccessLevel, PermissionKey } from '../../common/permissions/catalog';
import { PermissionsService } from '../personas/permissions.service';

export type PermissionRequirement = [PermissionKey, AccessLevel];

/**
 * "X or Y" rules from PLAN.md 1.6. Passes when any requirement is met; otherwise throws 403
 * PERMISSION_DENIED naming the first requirement.
 */
export function requireAnyPermission(
  permissions: PermissionsService,
  auth: AuthUser,
  options: PermissionRequirement[],
): void {
  if (options.some(([key, min]) => permissions.check(auth, key, min))) return;
  const [permission, required] = options[0];
  throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', { permission, required });
}
