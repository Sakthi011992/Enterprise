import { Injectable } from '@nestjs/common';
import { Prisma, Vendor } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { ProcurementRepository } from './procurement.repository';
import { VendorDto, VendorsQueryDto } from './dto/procurement.dto';

/** Vendors are tenant-wide. openPoCount counts this outlet's purchase orders that are not received or cancelled. */
@Injectable()
export class VendorsService {
  constructor(private repo: ProcurementRepository) {}

  async list(q: VendorsQueryDto, auth: AuthUser) {
    const vendors = await this.repo.listVendors(q.active === 'true' ? { isActive: true } : {});
    return this.views(auth.outletId, vendors);
  }

  async create(dto: VendorDto, auth: AuthUser) {
    await this.assertUniqueName(dto.name);
    const vendor = await this.repo.createVendor({ tenantId: auth.tenantId, ...this.data(dto) });
    const [view] = await this.views(auth.outletId, [vendor]);
    return view;
  }

  async update(id: string, dto: VendorDto, auth: AuthUser) {
    const current = await this.repo.findVendor(id);
    if (!current) throw apiError(404, 'VENDOR_NOT_FOUND', 'Vendor not found');
    await this.assertUniqueName(dto.name, id);
    const vendor = await this.repo.updateVendor(id, this.data(dto));
    const [view] = await this.views(auth.outletId, [vendor]);
    return view;
  }

  private async assertUniqueName(name: string, exceptId?: string): Promise<void> {
    if (await this.repo.findVendorByName(name, exceptId)) {
      throw apiError(409, 'VENDOR_EXISTS', 'A vendor with this name already exists', { name });
    }
  }

  private data(dto: VendorDto): Omit<Prisma.VendorUncheckedCreateInput, 'tenantId'> {
    return {
      name: dto.name,
      contactName: dto.contactName ?? null,
      phone: dto.phone ?? null,
      email: dto.email ?? null,
      gstin: dto.gstin ?? null,
      address: dto.address ?? null,
      paymentTermsDays: dto.paymentTermsDays ?? 30,
      isActive: dto.isActive ?? true,
    };
  }

  async views(outletId: string, vendors: Vendor[]) {
    const open = await this.repo.openPurchaseOrdersByVendor(outletId);
    const counts = new Map<string, number>();
    for (const po of open) counts.set(po.vendorId, (counts.get(po.vendorId) ?? 0) + 1);
    return vendors.map((v) => ({
      id: v.id,
      name: v.name,
      contactName: v.contactName,
      phone: v.phone,
      email: v.email,
      gstin: v.gstin,
      address: v.address,
      paymentTermsDays: v.paymentTermsDays,
      isActive: v.isActive,
      openPoCount: counts.get(v.id) ?? 0,
    }));
  }
}
