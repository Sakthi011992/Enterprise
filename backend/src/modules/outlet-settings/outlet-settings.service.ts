import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { DEFAULT_POS_SETTINGS } from '../menu/menu.service';
import { UpdateOutletSettingsDto } from './dto/outlet-settings.dto';
import { OutletSettingsRepository } from './outlet-settings.repository';

/** Settings for the outlet, with defaults when no row exists yet. */
@Injectable()
export class OutletSettingsService {
  constructor(private repo: OutletSettingsRepository) {}

  async get(auth: AuthUser) {
    const row = await this.repo.find(auth.outletId);
    return {
      outletId: auth.outletId,
      serviceChargePercent: row?.serviceChargePercent ?? new Prisma.Decimal(0),
      serviceChargeTypes: row?.serviceChargeTypes ?? [...DEFAULT_POS_SETTINGS.serviceChargeTypes],
      roundingMode: row?.roundingMode ?? DEFAULT_POS_SETTINGS.roundingMode,
      orderPrefix: row?.orderPrefix ?? 'A',
      invoicePrefix: row?.invoicePrefix ?? 'INV',
      countryCode: row?.countryCode ?? 'IN',
    };
  }

  async update(dto: UpdateOutletSettingsDto, auth: AuthUser) {
    if (dto.countryCode !== undefined && !/^[A-Z]{2}$/.test(dto.countryCode)) {
      throw apiError(400, 'COUNTRY_CODE_INVALID', 'countryCode must be two upper case letters');
    }
    const types = [...new Set(dto.serviceChargeTypes)];
    await this.repo.upsert(auth.outletId, {
      serviceChargePercent: new Prisma.Decimal(dto.serviceChargePercent),
      serviceChargeTypes: types,
      roundingMode: dto.roundingMode,
      orderPrefix: dto.orderPrefix,
      invoicePrefix: dto.invoicePrefix,
      ...(dto.countryCode !== undefined ? { countryCode: dto.countryCode } : {}),
    });
    return this.get(auth);
  }
}
