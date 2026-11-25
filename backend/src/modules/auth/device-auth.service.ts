import { Injectable } from '@nestjs/common';
import { TenantContext } from '../../common/tenancy/tenant-context';
import { apiError } from '../../common/filters/api-error';
import { AuthRepository } from './auth.repository';
import { hashToken } from './token.util';

/**
 * Resolves the X-Device-Key header to an active device. The lookup runs as system
 * (in the repository) because the device is not known yet. After it succeeds the
 * tenant store is set from the device.
 */
@Injectable()
export class DeviceAuthService {
  constructor(private repo: AuthRepository) {}

  async authenticate(rawKey: string | undefined) {
    if (!rawKey) throw apiError(401, 'DEVICE_INVALID', 'Device key is missing');

    const device = await this.repo.findDeviceByKeyHash(hashToken(rawKey));
    if (!device || !device.outlet.isActive) {
      throw apiError(401, 'DEVICE_INVALID', 'This device is not registered or has been disabled');
    }

    TenantContext.set({ tenantId: device.tenantId, outletId: device.outletId });
    await this.repo.touchDevice(device.id);
    return device;
  }
}
