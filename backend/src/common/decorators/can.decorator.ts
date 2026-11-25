import { SetMetadata } from '@nestjs/common';
import type { AccessLevel, PermissionKey } from '../permissions/catalog';

export const CAN_KEY = 'can';

export interface CanRequirement {
  key: PermissionKey;
  min: AccessLevel;
}

/**
 * Requires the caller's persona to grant `key` at `min` level or above.
 * Method-level @Can overrides class-level @Can. Routes without @Can only need
 * an authenticated user.
 */
export const Can = (key: PermissionKey, min: AccessLevel = 'VIEW') =>
  SetMetadata(CAN_KEY, { key, min } satisfies CanRequirement);
