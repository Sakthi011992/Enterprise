import { Injectable } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';
import { AuthUser, PermissionGrant } from '../../common/decorators/current-user.decorator';
import { AccessLevel, PermissionKey, levelAtLeast } from '../../common/permissions/catalog';
import { PersonasRepository } from './personas.repository';

export type PermissionMatrix = Record<string, PermissionGrant>;

const CACHE_TTL_MS = 30_000;

@Injectable()
export class PermissionsService {
  private readonly cache = new Map<string, { expiresAt: number; matrix: PermissionMatrix }>();

  constructor(private repo: PersonasRepository) {}

  /** Permission catalog rows for the admin UI, in sort order. */
  async catalog() {
    const rows = await this.repo.catalog();
    return rows.map((r) => ({
      key: r.key,
      group: r.group,
      label: r.label,
      description: r.description,
      limitUnit: r.limitUnit,
      sortOrder: r.sortOrder,
    }));
  }

  /**
   * Full matrix for a persona: every catalog key, with NONE / null limit for
   * keys the persona has no row for. Cached for 30 seconds per persona.
   */
  async forPersona(personaId: string): Promise<PermissionMatrix> {
    const hit = this.cache.get(personaId);
    if (hit && hit.expiresAt > Date.now()) return hit.matrix;

    const [catalog, rows] = await Promise.all([this.repo.catalog(), this.repo.grantsFor(personaId)]);
    const byKey = new Map(rows.map((r): [string, (typeof rows)[number]] => [r.permissionKey, r]));

    const matrix: PermissionMatrix = {};
    for (const def of catalog) {
      const row = byKey.get(def.key);
      matrix[def.key] = {
        level: (row?.level ?? 'NONE') as AccessLevel,
        limit: row?.limitValue != null ? Number(row.limitValue) : null,
      };
    }

    this.cache.set(personaId, { expiresAt: Date.now() + CACHE_TTL_MS, matrix });
    return matrix;
  }

  /** Drops the cached matrix for one persona, or all personas when omitted. */
  invalidate(personaId?: string): void {
    if (personaId) this.cache.delete(personaId);
    else this.cache.clear();
  }

  /** True when the user's grant for `key` is at least `min`. */
  check(user: Pick<AuthUser, 'permissions'>, key: PermissionKey, min: AccessLevel): boolean {
    const grant = user.permissions?.[key];
    return levelAtLeast(grant?.level ?? 'NONE', min);
  }

  /**
   * Used by Phase 2 money actions. APPROVE and above pass. LIMITED passes up to
   * its limit. Anything else is denied.
   */
  assertWithinLimit(user: Pick<AuthUser, 'permissions'>, key: PermissionKey, value: number): void {
    const grant: PermissionGrant = user.permissions?.[key] ?? { level: 'NONE', limit: null };

    if (levelAtLeast(grant.level, 'APPROVE')) return;

    if (grant.level === 'LIMITED') {
      if (grant.limit !== null && value <= grant.limit) return;
      throw apiError(403, 'LIMIT_EXCEEDED', 'This amount is above your limit', { limit: grant.limit });
    }

    throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', {
      permission: key,
      required: 'LIMITED',
    });
  }
}
