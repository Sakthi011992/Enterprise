import { PrismaClient, Prisma, LoginMethod, PaymentMethod } from '@prisma/client';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  // Roles
  const adminRole = await prisma.role.upsert({
    where: { name: 'ADMIN' },
    update: {},
    create: { name: 'ADMIN', description: 'Full system access' },
  });
  await prisma.role.upsert({
    where: { name: 'USER' },
    update: {},
    create: { name: 'USER', description: 'Cashier — billing only' },
  });
  await prisma.role.upsert({
    where: { name: 'KIOSK' },
    update: {},
    create: { name: 'KIOSK', description: 'Kiosk display device' },
  });

  // Default admin
  const username = process.env.SEED_ADMIN_USERNAME || 'admin';
  const password = process.env.SEED_ADMIN_PASSWORD || 'Admin@123';
  const email = process.env.SEED_ADMIN_EMAIL || 'admin@example.com';
  const passwordHash = await bcrypt.hash(password, 10);

  await prisma.user.upsert({
    where: { username },
    update: {},
    create: { username, email, passwordHash, roleId: adminRole.id, isActive: true },
  });

  // Global tax
  const taxPct = new Prisma.Decimal(process.env.SEED_GLOBAL_TAX || '18');
  const existingTax = await prisma.globalTaxSetting.findFirst({ where: { isActive: true } });
  if (!existingTax) {
    await prisma.globalTaxSetting.create({ data: { percentage: taxPct, isActive: true } });
  }

  // Sample products
  const sample: Prisma.ProductCreateManyInput[] = [
    { name: 'Coffee', description: 'Hot Coffee', price: new Prisma.Decimal('100.00'), taxPercentage: new Prisma.Decimal('5.00') },
    { name: 'Pizza', description: 'Margherita', price: new Prisma.Decimal('250.00'), taxPercentage: new Prisma.Decimal('18.00') },
    { name: 'Water Bottle', description: '1L', price: new Prisma.Decimal('20.00'), taxPercentage: null },
  ];
  for (const p of sample) {
    const exists = await prisma.product.findFirst({ where: { name: p.name, deletedAt: null } });
    if (!exists) await prisma.product.create({ data: p });
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

  console.log(`Seed complete. Admin login: ${username} / ${password}`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
