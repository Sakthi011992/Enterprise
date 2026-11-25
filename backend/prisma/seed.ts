import { PrismaClient, Prisma, LoginMethod, PaymentMethod } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { DEFAULT_PERSONAS, PERMISSION_CATALOG } from '../src/common/permissions/catalog';

// Plain client, no tenant extension: every write below passes tenantId explicitly.
const prisma = new PrismaClient();

const DEFAULT_TENANT_SLUG = 'default';
const MAIN_OUTLET_CODE = 'MAIN';

function requireId(map: Map<string, string>, key: string): string {
  const id = map.get(key);
  if (!id) throw new Error(`Persona "${key}" was not seeded`);
  return id;
}

async function main() {
  // Roles (legacy, kept until Phase 2)
  const adminRole = await prisma.role.upsert({
    where: { name: 'ADMIN' },
    update: {},
    create: { name: 'ADMIN', description: 'Full system access' },
  });
  const userRole = await prisma.role.upsert({
    where: { name: 'USER' },
    update: {},
    create: { name: 'USER', description: 'Cashier — billing only' },
  });
  await prisma.role.upsert({
    where: { name: 'KIOSK' },
    update: {},
    create: { name: 'KIOSK', description: 'Kiosk display device' },
  });

  // Permission catalog (PLAN.md 1.1)
  for (const p of PERMISSION_CATALOG) {
    await prisma.permission.upsert({
      where: { key: p.key },
      update: { group: p.group, label: p.label, limitUnit: p.limitUnit, sortOrder: p.sortOrder },
      create: { key: p.key, group: p.group, label: p.label, limitUnit: p.limitUnit, sortOrder: p.sortOrder },
    });
  }

  // Default tenant and MAIN outlet
  const tenant = await prisma.tenant.upsert({
    where: { slug: DEFAULT_TENANT_SLUG },
    update: {},
    create: { name: 'Default venue', slug: DEFAULT_TENANT_SLUG },
  });
  const tenantId = tenant.id;

  const outlet = await prisma.outlet.upsert({
    where: { tenantId_code: { tenantId, code: MAIN_OUTLET_CODE } },
    update: {},
    create: { tenantId, name: 'Main outlet', code: MAIN_OUTLET_CODE },
  });

  // Personas (PLAN.md 1.2). Matrix rows are only created when missing, so admin edits survive a re-seed.
  const personaIds = new Map<string, string>();
  for (const def of DEFAULT_PERSONAS) {
    const persona = await prisma.persona.upsert({
      where: { tenantId_key: { tenantId, key: def.key } },
      update: {},
      create: {
        tenantId,
        key: def.key,
        name: def.name,
        homeRoute: def.homeRoute,
        loginMethod: def.loginMethod,
        isSystem: def.isSystem,
      },
    });
    personaIds.set(def.key, persona.id);

    for (const p of PERMISSION_CATALOG) {
      const grant = def.matrix[p.key];
      if (!grant) continue; // missing row = NONE
      await prisma.personaPermission.upsert({
        where: { personaId_permissionKey: { personaId: persona.id, permissionKey: p.key } },
        update: {},
        create: {
          personaId: persona.id,
          permissionKey: p.key,
          level: grant.level,
          limitValue: grant.limit !== undefined ? new Prisma.Decimal(grant.limit) : null,
        },
      });
    }
  }

  // Default admin (password login, admin persona at MAIN)
  const username = process.env.SEED_ADMIN_USERNAME || 'admin';
  const password = process.env.SEED_ADMIN_PASSWORD || 'Admin@123';
  const email = process.env.SEED_ADMIN_EMAIL || 'admin@example.com';
  const passwordHash = await bcrypt.hash(password, 10);

  const admin = await prisma.user.upsert({
    where: { username },
    update: {},
    create: {
      tenantId,
      username,
      email,
      displayName: 'Administrator',
      passwordHash,
      roleId: adminRole.id,
      isActive: true,
    },
  });
  await prisma.userOutlet.upsert({
    where: { userId_outletId: { userId: admin.id, outletId: outlet.id } },
    update: {},
    create: {
      userId: admin.id,
      outletId: outlet.id,
      personaId: requireId(personaIds, 'admin'),
      isDefault: true,
    },
  });

  // Demo bartender for the Phase 1 exit test: password Bartender@123, PIN 2580 (bcrypt-hashed)
  const bartender = await prisma.user.upsert({
    where: { username: 'bartender1' },
    update: {},
    create: {
      tenantId,
      username: 'bartender1',
      email: 'bartender1@example.com',
      displayName: 'Bartender 1',
      passwordHash: await bcrypt.hash('Bartender@123', 10),
      roleId: userRole.id,
      isActive: true,
    },
  });
  await prisma.userOutlet.upsert({
    where: { userId_outletId: { userId: bartender.id, outletId: outlet.id } },
    update: {},
    create: {
      userId: bartender.id,
      outletId: outlet.id,
      personaId: requireId(personaIds, 'bartender'),
      isDefault: true,
    },
  });
  await prisma.staffPin.upsert({
    where: { userId: bartender.id },
    update: {},
    create: { userId: bartender.id, pinHash: await bcrypt.hash('2580', 10) },
  });

  // Global tax
  const taxPct = new Prisma.Decimal(process.env.SEED_GLOBAL_TAX || '18');
  const existingTax = await prisma.globalTaxSetting.findFirst({ where: { tenantId, isActive: true } });
  if (!existingTax) {
    await prisma.globalTaxSetting.create({ data: { tenantId, percentage: taxPct, isActive: true } });
  }

  // Sample products
  const sample: Omit<Prisma.ProductCreateManyInput, 'tenantId'>[] = [
    { name: 'Coffee', description: 'Hot Coffee', price: new Prisma.Decimal('100.00'), taxPercentage: new Prisma.Decimal('5.00') },
    { name: 'Pizza', description: 'Margherita', price: new Prisma.Decimal('250.00'), taxPercentage: new Prisma.Decimal('18.00') },
    { name: 'Water Bottle', description: '1L', price: new Prisma.Decimal('20.00'), taxPercentage: null },
  ];
  for (const p of sample) {
    const exists = await prisma.product.findFirst({ where: { tenantId, name: p.name, deletedAt: null } });
    if (!exists) await prisma.product.create({ data: { ...p, tenantId } });
  }

  // Login methods (STATIC enabled by default, GOOGLE disabled)
  for (const [method, enabled] of [[LoginMethod.STATIC, true], [LoginMethod.GOOGLE, false]] as const) {
    await prisma.loginMethodConfig.upsert({
      where: { method },
      create: { method, enabled },
      update: {},
    });
  }

  // Payment methods (all disabled by default — admin must enable per store)
  for (const method of [PaymentMethod.CASH, PaymentMethod.UPI, PaymentMethod.CARD]) {
    await prisma.paymentMethodConfig.upsert({
      where: { storeId_method: { storeId: 'default', method } },
      create: { storeId: 'default', method, enabled: method === PaymentMethod.CASH },
      update: {},
    });
  }

  // Invoice country profiles
  const profiles = [
    { countryCode: 'IN', numberPrefix: 'GST', resetPeriod: 'FINANCIAL_YEAR' as const, taxBreakdownMode: 'SPLIT_COMPONENTS' as const, roundingRule: 'ROUND_PER_LINE' as const, retentionYears: 8, requiredFields: ['gstin'] },
    { countryCode: 'US', numberPrefix: 'INV', resetPeriod: 'CALENDAR_YEAR' as const, taxBreakdownMode: 'SINGLE_LINE' as const, roundingRule: 'ROUND_TOTAL' as const, retentionYears: 7, requiredFields: [] },
    { countryCode: 'JP', numberPrefix: 'REC', resetPeriod: 'CALENDAR_YEAR' as const, taxBreakdownMode: 'SINGLE_LINE' as const, roundingRule: 'ROUND_TOTAL' as const, retentionYears: 7, requiredFields: [] },
  ];
  for (const p of profiles) {
    await prisma.invoiceCountryProfile.upsert({
      where: { countryCode: p.countryCode },
      create: p,
      update: {},
    });
  }

  // Seed localisation keys (English baseline)
  const i18nKeys = [
    { key: 'app.title', description: 'Application title' },
    { key: 'nav.dashboard', description: 'Dashboard nav label' },
    { key: 'nav.products', description: 'Products nav label' },
    { key: 'nav.orders', description: 'Orders nav label' },
    { key: 'nav.users', description: 'Users nav label' },
    { key: 'nav.tax', description: 'Tax nav label' },
    { key: 'nav.appearance', description: 'Appearance nav label' },
  ];
  const i18nValues = [
    'POS Billing', 'Dashboard', 'Products', 'Orders', 'Users', 'Tax', 'Appearance',
  ];
  for (let i = 0; i < i18nKeys.length; i++) {
    const keyRow = await prisma.translationKey.upsert({
      where: { key: i18nKeys[i].key },
      create: i18nKeys[i],
      update: {},
    });
    await prisma.translationValue.upsert({
      where: { keyId_locale: { keyId: keyRow.id, locale: 'en' } },
      create: { keyId: keyRow.id, locale: 'en', value: i18nValues[i] },
      update: {},
    });
  }

  console.log(`Seed complete. Admin login: ${username} / ${password}. Demo: bartender1 / Bartender@123, PIN 2580.`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
