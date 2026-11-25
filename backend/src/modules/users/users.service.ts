import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AppFeature } from '@prisma/client';
import { PaginationDto, buildMeta } from '../../common/dto/pagination.dto';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { CreateUserDto, SetUserOutletsDto, UpdateUserDto } from './dto/user.dto';
import { OutletAssignment, UserRow, UsersRepository } from './users.repository';

const SIMPLE_PINS = new Set(['0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999', '1234', '4321']);

/** Starting persona for a legacy role name. */
const ROLE_PERSONA_KEY: Record<'ADMIN' | 'USER' | 'KIOSK', string> = {
  ADMIN: 'admin',
  USER: 'cashier',
  KIOSK: 'kiosk',
};

function toUserDto(row: UserRow) {
  const { userOutlets, staffPin, ...rest } = row;
  return {
    ...rest,
    hasPin: staffPin !== null,
    outlets: userOutlets.map((uo) => ({
      outletId: uo.outletId,
      outletName: uo.outlet.name,
      personaId: uo.personaId,
      personaName: uo.persona.name,
      isDefault: uo.isDefault,
    })),
  };
}

@Injectable()
export class UsersService {
  constructor(private repo: UsersRepository) {}

  async findAll(q: PaginationDto, auth: AuthUser) {
    const { rows, total } = await this.repo.listForTenant(auth.tenantId, q.search, q.skip, q.limit);
    return { data: rows.map(toUserDto), meta: buildMeta(total, q.page, q.limit) };
  }

  async findOne(id: string, auth: AuthUser) {
    const row = await this.repo.findOwned(id, auth.tenantId);
    if (!row) throw new NotFoundException('User not found');
    return toUserDto(row);
  }

  /** Throws 404 for users in another tenant or deleted users. */
  private async assertOwned(id: string, auth: AuthUser): Promise<void> {
    if (!(await this.repo.existsOwned(id, auth.tenantId))) throw new NotFoundException('User not found');
  }

  private async roleIdOrThrow(name: string): Promise<string> {
    const roleId = await this.repo.roleIdByName(name);
    if (!roleId) throw new BadRequestException(`Unknown role: ${name}`);
    return roleId;
  }

  /**
   * Creates the user. When the tenant has an active outlet and the starting persona
   * for the legacy role exists, the user is assigned to that outlet as default.
   */
  async create(dto: CreateUserDto, auth: AuthUser) {
    const roleName = dto.roleName ?? 'USER';
    const roleId = await this.roleIdOrThrow(roleName);
    const passwordHash = await bcrypt.hash(dto.password, 10);

    const outletId = await this.repo.firstActiveOutletId(auth.tenantId);
    const personaId = await this.repo.personaIdByKey(auth.tenantId, ROLE_PERSONA_KEY[roleName]);

    const row = await this.repo.create({
      tenantId: auth.tenantId,
      username: dto.username,
      email: dto.email,
      passwordHash,
      roleId,
      displayName: dto.displayName,
      phone: dto.phone,
      outlet: outletId && personaId ? { outletId, personaId } : undefined,
    });
    return toUserDto(row);
  }

  async update(id: string, dto: UpdateUserDto, auth: AuthUser) {
    await this.assertOwned(id, auth);
    const roleId = dto.roleName ? await this.roleIdOrThrow(dto.roleName) : undefined;
    const passwordHash = dto.password ? await bcrypt.hash(dto.password, 10) : undefined;

    await this.repo.update(id, {
      email: dto.email,
      displayName: dto.displayName,
      phone: dto.phone,
      isActive: dto.isActive,
      roleId,
      passwordHash,
    });
    return this.findOne(id, auth);
  }

  async resetPassword(id: string, newPassword: string, auth: AuthUser) {
    await this.assertOwned(id, auth);
    const passwordHash = await bcrypt.hash(newPassword, 10);
    await this.repo.update(id, { passwordHash });
    return { success: true };
  }

  async remove(id: string, auth: AuthUser) {
    await this.assertOwned(id, auth);
    await this.repo.softDelete(id);
    return { success: true };
  }

  /** Sets or replaces the 4-digit PIN and clears any lock. */
  async setPin(id: string, pin: string, auth: AuthUser) {
    await this.assertOwned(id, auth);
    if (SIMPLE_PINS.has(pin)) {
      throw apiError(400, 'PIN_TOO_SIMPLE', 'Choose a less predictable PIN');
    }
    await this.repo.upsertPin(id, await bcrypt.hash(pin, 10));
    return { success: true, hasPin: true };
  }

  /** Replaces all outlet assignments. Exactly one default when any are given. */
  async setOutlets(id: string, dto: SetUserOutletsDto, auth: AuthUser) {
    await this.assertOwned(id, auth);

    const outletIds = dto.items.map((i) => i.outletId);
    if (new Set(outletIds).size !== outletIds.length) {
      throw apiError(400, 'DUPLICATE_OUTLET', 'An outlet can only be assigned once');
    }
    const defaultCount = dto.items.filter((i) => i.isDefault).length;
    if (defaultCount > 1) {
      throw apiError(400, 'DEFAULT_OUTLET_INVALID', 'Only one outlet can be the default');
    }
    const items: OutletAssignment[] = dto.items.map((item, index) => ({
      outletId: item.outletId,
      personaId: item.personaId,
      isDefault: defaultCount === 0 ? index === 0 : !!item.isDefault,
    }));

    const personaIds = [...new Set(items.map((i) => i.personaId))];
    if ((await this.repo.countOutletsIn(outletIds, auth.tenantId)) !== outletIds.length) {
      throw apiError(400, 'INVALID_REFERENCE', 'One or more outlets were not found', { field: 'outletId' });
    }
    if ((await this.repo.countPersonasIn(personaIds, auth.tenantId)) !== personaIds.length) {
      throw apiError(400, 'INVALID_REFERENCE', 'One or more personas were not found', { field: 'personaId' });
    }

    await this.repo.replaceOutlets(id, items);
    return this.findOne(id, auth);
  }

  // Legacy feature grants (main). Deprecated: removed in Phase 2 with the feature tables.

  async getFeatures(id: string, auth: AuthUser): Promise<AppFeature[]> {
    await this.assertOwned(id, auth);
    return this.repo.getFeatures(id);
  }

  async setFeatures(id: string, features: AppFeature[], auth: AuthUser): Promise<AppFeature[]> {
    await this.assertOwned(id, auth);
    await this.repo.setFeatures(id, features);
    return features;
  }
}
