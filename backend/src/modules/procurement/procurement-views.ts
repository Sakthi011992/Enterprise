// Summary views shared by the purchase order and GRN services (PLAN.md 1.7 GrnSummary).
import { GoodsReceipt } from '@prisma/client';
import { money2, ymd } from '../inventory/inventory-views';
import { ProcurementRepository } from './procurement.repository';

/** GrnSummary rows with vendor, location and PO number names. */
export async function grnSummaryViews(repo: ProcurementRepository, outletId: string, grns: GoodsReceipt[]) {
  if (grns.length === 0) return [];
  const vendors = await repo.findVendorsByIds([...new Set(grns.map((g) => g.vendorId))]);
  const locations = await repo.findLocationsByIds(outletId, [...new Set(grns.map((g) => g.locationId))]);
  const poIds = [...new Set(grns.map((g) => g.poId).filter((v): v is string => !!v))];
  const pos = poIds.length ? await repo.posByIds(poIds) : [];
  const vendorName = new Map(vendors.map((v) => [v.id, v.name]));
  const locationName = new Map(locations.map((l) => [l.id, l.name]));
  const poNumber = new Map(pos.map((p) => [p.id, p.number]));
  return grns.map((g) => ({
    id: g.id,
    number: g.number,
    poNumber: g.poId ? (poNumber.get(g.poId) ?? null) : null,
    vendor: { id: g.vendorId, name: vendorName.get(g.vendorId) ?? null },
    location: { id: g.locationId, name: locationName.get(g.locationId) ?? null },
    status: g.status,
    receivedOn: ymd(g.receivedOn),
    invoiceValue: money2(g.invoiceValue),
    payable: money2(g.payable),
    mismatch: g.mismatch,
  }));
}
