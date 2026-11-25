import { Injectable, NotFoundException } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { levelAtLeast } from '../../common/permissions/catalog';
import { CreateOutletDto, UpdateOutletDto } from './dto/outlet.dto';
import { OutletsRepository } from './outlets.repository';

@Injectable()
export class OutletsService {
  constructor(private repo: OutletsRepository) {}

  /** admin.settings or admin.users VIEW sees every outlet in the tenant. Others see only their own. */
  async list(auth: AuthUser) {
    const settings = auth.permissions['admin.settings']?.level ?? 'NONE';
    const users = auth.permissions['admin.users']?.level ?? 'NONE';
    // admin.users also needs every outlet, to assign staff to outlets.
    if (levelAtLeast(settings, 'VIEW') || levelAtLeast(users, 'VIEW')) {
      return this.repo.listForTenant(auth.tenantId);
    }
    return this.repo.listAssignedTo(auth.userId, auth.tenantId);
  }

  private async assertCodeFree(code: string, auth: AuthUser, exceptId?: string) {
    if (await this.repo.codeTaken(auth.tenantId, code, exceptId)) {
      throw apiError(409, 'OUTLET_CODE_TAKEN', 'Another outlet already uses this code', { code });
    }
  }

  async create(dto: CreateOutletDto, auth: AuthUser) {
    await this.assertCodeFree(dto.code, auth);
    return this.repo.create({
      tenantId: auth.tenantId,
      name: dto.name,
      code: dto.code,
      address: dto.address,
      ...(dto.timezone ? { timezone: dto.timezone } : {}),
    });
  }

  async update(id: string, dto: UpdateOutletDto, auth: AuthUser) {
    const existing = await this.repo.findOwned(id, auth.tenantId);
    if (!existing) throw new NotFoundException('Outlet not found');
    if (dto.code) await this.assertCodeFree(dto.code, auth, id);

    return this.repo.update(id, {
      ...(dto.name !== undefined ? { name: dto.name } : {}),
      ...(dto.code !== undefined ? { code: dto.code } : {}),
      ...(dto.address !== undefined ? { address: dto.address } : {}),
      ...(dto.timezone !== undefined ? { timezone: dto.timezone } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
    });
  }
}
