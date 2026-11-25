import { Injectable, NotFoundException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { hashToken } from '../auth/token.util';
import { CreateDeviceDto } from './dto/device.dto';
import { DevicesRepository } from './devices.repository';

@Injectable()
export class DevicesService {
  constructor(private repo: DevicesRepository) {}

  list(auth: AuthUser, outletId?: string) {
    return this.repo.listForTenant(auth.tenantId, outletId);
  }

  /** The raw device key is returned once and only its sha256 is stored. */
  async create(dto: CreateDeviceDto, auth: AuthUser) {
    const outlet = await this.repo.findActiveOutlet(dto.outletId, auth.tenantId);
    if (!outlet) throw new NotFoundException('Outlet not found');

    const deviceKey = randomBytes(32).toString('base64url');
    const device = await this.repo.create({
      tenantId: auth.tenantId,
      outletId: outlet.id,
      name: dto.name,
      type: dto.type,
      keyHash: hashToken(deviceKey),
    });
    return { device, deviceKey };
  }

  async deactivate(id: string, auth: AuthUser) {
    const device = await this.repo.findOwned(id, auth.tenantId);
    if (!device) throw new NotFoundException('Device not found');
    await this.repo.deactivate(id);
    return { success: true };
  }
}
