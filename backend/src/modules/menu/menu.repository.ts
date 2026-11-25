import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/** Read-only queries behind GET /menu/pos. */
@Injectable()
export class MenuRepository {
  constructor(private prisma: PrismaService) {}

  findOutlet(outletId: string) {
    return this.prisma.outlet.findFirst({ where: { id: outletId }, select: { timezone: true } });
  }

  categories() {
    return this.prisma.category.findMany({
      where: { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    });
  }

  products() {
    return this.prisma.product.findMany({
      where: { deletedAt: null, isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      include: {
        variants: { where: { isActive: true }, orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] },
        modifierGroups: { orderBy: { sortOrder: 'asc' }, select: { groupId: true } },
      },
    });
  }

  modifierGroups() {
    return this.prisma.modifierGroup.findMany({
      where: { isActive: true },
      orderBy: { name: 'asc' },
      include: { options: { where: { isActive: true }, orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }] } },
    });
  }

  combos() {
    return this.prisma.combo.findMany({ where: { isActive: true }, orderBy: { name: 'asc' }, include: { items: true } });
  }

  priceRules(outletId: string) {
    return this.prisma.priceRule.findMany({
      where: { isActive: true, OR: [{ outletId: null }, { outletId }] },
      orderBy: { name: 'asc' },
    });
  }

  taxClasses() {
    return this.prisma.taxClass.findMany({ where: { isActive: true }, orderBy: { code: 'asc' } });
  }

  outletSettings(outletId: string) {
    return this.prisma.outletSettings.findFirst({ where: { outletId } });
  }
}
