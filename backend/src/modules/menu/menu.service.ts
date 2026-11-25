import { Injectable } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { isWithinSchedule } from '../../common/pricing/pricing.engine';
import { MenuRepository } from './menu.repository';
import { nextClockTime } from './menu-time';

/** Settings used when the outlet has no outlet_settings row yet. */
export const DEFAULT_POS_SETTINGS = {
  serviceChargePercent: 0,
  serviceChargeTypes: ['DINE_IN'],
  roundingMode: 'NEAREST_1',
} as const;

@Injectable()
export class MenuService {
  constructor(private repo: MenuRepository) {}

  /** Everything the POS needs in one call. Inactive rows are left out; 86'd products stay with `is86: true`. */
  async pos(auth: AuthUser, now: Date = new Date()) {
    const outlet = await this.repo.findOutlet(auth.outletId);
    const timeZone = outlet?.timezone ?? 'Asia/Kolkata';
    const [categories, products, groups, combos, rules, taxClasses, settings] = await Promise.all([
      this.repo.categories(),
      this.repo.products(),
      this.repo.modifierGroups(),
      this.repo.combos(),
      this.repo.priceRules(auth.outletId),
      this.repo.taxClasses(),
      this.repo.outletSettings(auth.outletId),
    ]);

    // The repository already filters on isActive; the checks here keep the rule explicit and testable.
    const activeCategories = categories.filter((c) => c.isActive);
    const activeProducts = products.filter((p) => p.isActive && !p.deletedAt);
    const activeGroups = groups.filter((g) => g.isActive);
    const activeGroupIds = new Set(activeGroups.map((g) => g.id));
    const activeCombos = combos.filter((c) => c.isActive);
    const activeRules = rules.filter((r) => r.isActive);
    const activeTaxClasses = taxClasses.filter((t) => t.isActive);

    return {
      categories: activeCategories.map((c) => ({ id: c.id, name: c.name, color: c.color, sortOrder: c.sortOrder })),
      products: activeProducts.map((p) => ({
        id: p.id,
        name: p.name,
        categoryId: p.categoryId,
        price: p.price,
        is86: p.is86,
        imageUrl: p.imageUrl,
        taxClassId: p.taxClassId,
        variants: p.variants
          .filter((v) => v.isActive)
          .map((v) => ({ id: v.id, name: v.name, price: v.price, isDefault: v.isDefault })),
        modifierGroupIds: p.modifierGroups.map((g) => g.groupId).filter((id) => activeGroupIds.has(id)),
      })),
      modifierGroups: activeGroups.map((g) => ({
        id: g.id,
        name: g.name,
        minSelect: g.minSelect,
        maxSelect: g.maxSelect,
        options: g.options
          .filter((o) => o.isActive)
          .map((o) => ({ id: o.id, name: o.name, priceDelta: o.priceDelta })),
      })),
      combos: activeCombos.map((c) => ({
        id: c.id,
        name: c.name,
        price: c.price,
        items: c.items.map((i) => ({
          productId: i.productId,
          variantId: i.variantId,
          quantity: i.quantity,
          swapAllowed: i.swapAllowed,
        })),
        availableNow: isWithinSchedule(now, timeZone, c.days, c.startTime, c.endTime),
      })),
      priceRules: activeRules.map((r) => {
        const activeNow = isWithinSchedule(now, timeZone, r.days, r.startTime, r.endTime);
        return {
          id: r.id,
          name: r.name,
          percentOff: r.percentOff,
          categoryIds: r.categoryIds,
          productIds: r.productIds,
          activeNow,
          endsAt: activeNow ? nextClockTime(now, timeZone, r.endTime).toISOString() : null,
        };
      }),
      taxClasses: activeTaxClasses.map((t) => ({
        id: t.id,
        code: t.code,
        name: t.name,
        rate: t.rate,
        isLiquor: t.isLiquor,
        inclusive: t.inclusive,
      })),
      settings: settings
        ? {
            serviceChargePercent: settings.serviceChargePercent,
            serviceChargeTypes: settings.serviceChargeTypes,
            roundingMode: settings.roundingMode,
          }
        : { ...DEFAULT_POS_SETTINGS, serviceChargeTypes: [...DEFAULT_POS_SETTINGS.serviceChargeTypes] },
    };
  }
}
