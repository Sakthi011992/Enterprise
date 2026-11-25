import { Injectable, NotFoundException } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { ACCESS_LEVELS, AccessLevel, PERMISSION_CATALOG } from '../../common/permissions/catalog';
import { PermissionsService } from './permissions.service';
import { GrantRow, PersonasRepository } from './personas.repository';
import { CreatePersonaDto, PermissionItemDto, SetPermissionsDto, UpdatePersonaDto } from './dto/persona.dto';

type PersonaRow = {
  id: string;
  key: string;
  name: string;
  description: string | null;
  homeRoute: string;
  loginMethod: 'PASSWORD' | 'PIN';
  isSystem: boolean;
  _count: { userOutlets: number };
};

function toSummary(p: PersonaRow) {
  return {
    id: p.id,
    key: p.key,
    name: p.name,
    description: p.description,
    homeRoute: p.homeRoute,
    loginMethod: p.loginMethod,
    isSystem: p.isSystem,
    userCount: p._count.userOutlets,
  };
}

function slugify(name: string): string {
  const slug = name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug || 'persona';
}

function rank(level: AccessLevel): number {
  return (ACCESS_LEVELS as readonly string[]).indexOf(level);
}

@Injectable()
export class PersonasService {
  constructor(
    private repo: PersonasRepository,
    private permissions: PermissionsService,
  ) {}

  async list(auth: AuthUser) {
    const rows = await this.repo.listForTenant(auth.tenantId);
    return rows.map(toSummary);
  }

  /** Tenant-scoped lookup. Throws 404 for another tenant's persona. */
  private async getOwned(id: string, auth: AuthUser): Promise<PersonaRow> {
    const persona = await this.repo.findOwned(id, auth.tenantId);
    if (!persona) throw new NotFoundException('Persona not found');
    return persona;
  }

  async create(dto: CreatePersonaDto, auth: AuthUser) {
    const base = slugify(dto.name);
    let key = base;
    for (let n = 2; await this.repo.keyTaken(auth.tenantId, key); n++) {
      key = `${base}-${n}`;
    }

    let grants: GrantRow[] | undefined;
    if (dto.copyFromId) {
      const source = await this.getOwned(dto.copyFromId, auth);
      const rows = await this.repo.grantsFor(source.id);
      const copied: GrantRow[] = rows.map((r) => ({
        permissionKey: r.permissionKey,
        level: r.level,
        limitValue: r.limitValue === null ? null : Number(r.limitValue),
      }));
      // Copying must not hand out more than the caller holds.
      this.assertNoEscalation(copied, auth);
      grants = copied;
    }

    const created = await this.repo.create({
      tenantId: auth.tenantId,
      key,
      name: dto.name,
      homeRoute: '/dashboard',
      loginMethod: 'PASSWORD',
      isSystem: false,
      grants,
    });
    return toSummary(created);
  }

  async update(id: string, dto: UpdatePersonaDto, auth: AuthUser) {
    const persona = await this.getOwned(id, auth);
    if (persona.isSystem) {
      throw apiError(403, 'PERSONA_SYSTEM', 'System personas cannot be changed');
    }
    const updated = await this.repo.update(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.description !== undefined ? { description: dto.description } : {}),
      ...(dto.homeRoute !== undefined ? { homeRoute: dto.homeRoute } : {}),
      ...(dto.loginMethod !== undefined ? { loginMethod: dto.loginMethod } : {}),
    });
    return toSummary(updated);
  }

  async remove(id: string, auth: AuthUser) {
    const persona = await this.getOwned(id, auth);
    if (persona.isSystem) {
      throw apiError(403, 'PERSONA_SYSTEM', 'System personas cannot be deleted');
    }
    if (persona._count.userOutlets > 0) {
      throw apiError(409, 'PERSONA_IN_USE', 'Reassign the users who have this persona first', {
        userCount: persona._count.userOutlets,
      });
    }
    await this.repo.delete(id);
    this.permissions.invalidate(id);
    return { success: true };
  }

  /** Full matrix in catalog order, NONE where no row exists. */
  async getPermissions(id: string, auth: AuthUser) {
    await this.getOwned(id, auth);
    const matrix = await this.permissions.forPersona(id);
    return [...PERMISSION_CATALOG]
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map((def) => ({ key: def.key, level: matrix[def.key].level, limit: matrix[def.key].limit }));
  }

  async setPermissions(id: string, dto: SetPermissionsDto, auth: AuthUser) {
    const persona = await this.getOwned(id, auth);
    if (persona.isSystem) {
      throw apiError(403, 'PERSONA_SYSTEM', 'System personas cannot be changed');
    }

    const catalog = new Map(PERMISSION_CATALOG.map((d) => [d.key as string, d]));
    const merged = new Map<string, GrantRow>();

    for (const item of dto.items as PermissionItemDto[]) {
      const def = catalog.get(item.key);
      if (!def) {
        throw apiError(400, 'UNKNOWN_PERMISSION', 'Unknown permission key', { key: item.key });
      }
      const hasLimit = item.limit !== undefined && item.limit !== null;
      if (hasLimit && !def.limitUnit) {
        throw apiError(400, 'LIMIT_NOT_SUPPORTED', 'This permission does not take a limit', { key: item.key });
      }
      merged.set(item.key, {
        permissionKey: item.key,
        level: item.level,
        limitValue: hasLimit ? item.limit! : null,
      });
    }

    const rows = [...merged.values()];
    this.assertNoEscalation(rows, auth);

    await this.repo.replaceGrants(id, rows);
    this.permissions.invalidate(id);
    return this.getPermissions(id, auth);
  }

  /** Nobody can grant a level above their own. */
  private assertNoEscalation(rows: GrantRow[], auth: AuthUser): void {
    for (const row of rows) {
      const own: AccessLevel = (auth.permissions[row.permissionKey]?.level ?? 'NONE') as AccessLevel;
      if (rank(row.level as AccessLevel) > rank(own)) {
        throw apiError(403, 'PERMISSION_DENIED', 'You cannot grant a level above your own', {
          key: row.permissionKey,
          yourLevel: own,
        });
      }
    }
  }
}
