import {
  PrismaClient,
  Prisma,
  LoginMethod,
  PaymentMethod,
  OrderType,
  PrinterConnection,
  RoundingMode,
  TableShape,
  TicketKind,
} from '@prisma/client';
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

// ---------------------------------------------------------------------------
// Phase 2 demo: bar and kitchen menu, floor plan, printers (PLAN.md P2-A step 4).
// Idempotent: every block looks the row up first (or upserts on a unique key) and leaves existing rows alone.
// ---------------------------------------------------------------------------

const TAX_CLASS_DEFS: {
  name: string;
  code: string;
  rate: string;
  components: { name: string; rate: number }[];
  inclusive: boolean;
  isLiquor: boolean;
}[] = [
  { name: 'GST 5% (restaurant)', code: 'GST5', rate: '5.00', components: [{ name: 'CGST', rate: 2.5 }, { name: 'SGST', rate: 2.5 }], inclusive: false, isLiquor: false },
  { name: 'VAT 20% (liquor)', code: 'VAT_LIQUOR', rate: '20.00', components: [{ name: 'VAT', rate: 20 }], inclusive: false, isLiquor: true },
  { name: 'GST 18%', code: 'GST18', rate: '18.00', components: [{ name: 'CGST', rate: 9 }, { name: 'SGST', rate: 9 }], inclusive: false, isLiquor: false },
];

// station = routing key (Category.station), ticketKind BOT for drinks.
const CATEGORY_DEFS: { name: string; station: string; ticketKind: TicketKind; tax: string; sortOrder: number; color: string }[] = [
  { name: 'Spirits', station: 'BAR', ticketKind: TicketKind.BOT, tax: 'VAT_LIQUOR', sortOrder: 1, color: '#7A4E2D' },
  { name: 'Beer & draught', station: 'BAR', ticketKind: TicketKind.BOT, tax: 'VAT_LIQUOR', sortOrder: 2, color: '#C98A1B' },
  { name: 'Cocktails', station: 'BAR', ticketKind: TicketKind.BOT, tax: 'VAT_LIQUOR', sortOrder: 3, color: '#D1495B' },
  { name: 'Wine', station: 'BAR', ticketKind: TicketKind.BOT, tax: 'VAT_LIQUOR', sortOrder: 4, color: '#7B2D45' },
  { name: 'Mocktails & soft', station: 'BAR', ticketKind: TicketKind.BOT, tax: 'GST5', sortOrder: 5, color: '#2E8B57' },
  { name: 'Bar bites', station: 'KITCHEN', ticketKind: TicketKind.KOT, tax: 'GST5', sortOrder: 6, color: '#E07A1F' },
  { name: 'Mains', station: 'KITCHEN', ticketKind: TicketKind.KOT, tax: 'GST5', sortOrder: 7, color: '#3B6EA8' },
  { name: 'Desserts', station: 'KITCHEN', ticketKind: TicketKind.KOT, tax: 'GST5', sortOrder: 8, color: '#8E5BA8' },
];

type VariantDef = { name: string; price: string; isDefault: boolean };
const PRODUCT_DEFS: { name: string; category: string; price?: string; variants?: VariantDef[]; spiritServe?: boolean }[] = [
  {
    name: 'House Whisky', category: 'Spirits', spiritServe: true,
    variants: [
      { name: '30 ml', price: '180.00', isDefault: false },
      { name: '60 ml', price: '340.00', isDefault: true },
      { name: 'Bottle', price: '4800.00', isDefault: false },
    ],
  },
  {
    name: 'Single Malt 12Y', category: 'Spirits', spiritServe: true,
    // Matches the POS board: ₹540 / 60 ml, served "On the rocks" (no extra charge).
    variants: [
      { name: '30 ml', price: '280.00', isDefault: false },
      { name: '60 ml', price: '540.00', isDefault: true },
    ],
  },
  { name: 'Premium Lager 650 ml', category: 'Beer & draught', price: '300.00' },
  { name: 'Classic Mojito', category: 'Cocktails', price: '350.00' },
  { name: 'Old Fashioned', category: 'Cocktails', price: '420.00' },
  {
    name: 'House Red Wine', category: 'Wine',
    variants: [
      { name: 'Glass 150 ml', price: '350.00', isDefault: true },
      { name: 'Bottle 750 ml', price: '1500.00', isDefault: false },
    ],
  },
  { name: 'Virgin Mojito', category: 'Mocktails & soft', price: '220.00' },
  { name: 'Cola', category: 'Mocktails & soft', price: '120.00' },
  { name: 'Chicken Wings (8 pc)', category: 'Bar bites', price: '350.00' },
  { name: 'Masala Peanuts', category: 'Bar bites', price: '120.00' },
  { name: 'Chicken Biryani', category: 'Mains', price: '380.00' },
  { name: 'Paneer Butter Masala', category: 'Mains', price: '340.00' },
  { name: 'Chocolate Brownie', category: 'Desserts', price: '220.00' },
];

const AREA_DEFS = [
  { name: 'Indoor', sortOrder: 1, priceMarkupPercent: '0.00' },
  { name: 'Rooftop', sortOrder: 2, priceMarkupPercent: '10.00' },
  { name: 'Bar counter', sortOrder: 3, priceMarkupPercent: '0.00' },
];

function demoTables(): { name: string; area: string; seats: number; shape: TableShape; posX: number; posY: number }[] {
  const out: { name: string; area: string; seats: number; shape: TableShape; posX: number; posY: number }[] = [];
  for (let i = 1; i <= 9; i++) {
    out.push({ name: `R${i}`, area: 'Rooftop', seats: 4, shape: TableShape.SQUARE, posX: ((i - 1) % 3) * 140, posY: Math.floor((i - 1) / 3) * 140 });
  }
  for (let i = 1; i <= 4; i++) {
    out.push({ name: `T${i}`, area: 'Indoor', seats: 4, shape: TableShape.ROUND, posX: (i - 1) * 140, posY: 0 });
  }
  for (let i = 1; i <= 10; i++) {
    out.push({ name: `Bar ${i}`, area: 'Bar counter', seats: 1, shape: TableShape.LONG, posX: (i - 1) * 60, posY: 0 });
  }
  return out;
}

async function seedPosDemo(tenantId: string, outletId: string): Promise<void> {
  // Tax classes (the Phase 2 migration creates them for existing tenants; upsert covers fresh databases)
  const taxIdByCode = new Map<string, string>();
  for (const t of TAX_CLASS_DEFS) {
    const row = await prisma.taxClass.upsert({
      where: { tenantId_code: { tenantId, code: t.code } },
      update: {},
      create: { tenantId, name: t.name, code: t.code, rate: t.rate, components: t.components, inclusive: t.inclusive, isLiquor: t.isLiquor },
    });
    taxIdByCode.set(t.code, row.id);
  }

  // Categories
  const categoryIdByName = new Map<string, string>();
  for (const c of CATEGORY_DEFS) {
    const existing = await prisma.category.findFirst({ where: { tenantId, name: c.name } });
    const row =
      existing ??
      (await prisma.category.create({
        data: {
          tenantId,
          name: c.name,
          station: c.station,
          ticketKind: c.ticketKind,
          taxClassId: taxIdByCode.get(c.tax),
          sortOrder: c.sortOrder,
          color: c.color,
        },
      }));
    categoryIdByName.set(c.name, row.id);
  }

  // Modifier group: how to serve spirits
  let serveGroup = await prisma.modifierGroup.findFirst({ where: { tenantId, name: 'How to serve (spirits)' } });
  if (!serveGroup) {
    serveGroup = await prisma.modifierGroup.create({
      data: {
        tenantId,
        name: 'How to serve (spirits)',
        minSelect: 0,
        maxSelect: 1,
        showOn: ['POS'],
        options: {
          create: [
            { name: 'On the rocks', priceDelta: '0.00', sortOrder: 1 },
            { name: 'Neat', priceDelta: '0.00', sortOrder: 2 },
            { name: 'With soda', priceDelta: '40.00', sortOrder: 3 },
            { name: 'With water', priceDelta: '0.00', sortOrder: 4 },
          ],
        },
      },
    });
  }

  // Products (with variants where listed). Product price = default variant price.
  const productIdByName = new Map<string, string>();
  for (const p of PRODUCT_DEFS) {
    const existing = await prisma.product.findFirst({ where: { tenantId, name: p.name, deletedAt: null } });
    if (existing) {
      productIdByName.set(p.name, existing.id);
      continue;
    }
    const defaultVariant = p.variants?.find((v) => v.isDefault);
    const product = await prisma.product.create({
      data: {
        tenantId,
        name: p.name,
        price: defaultVariant ? defaultVariant.price : (p.price as string),
        categoryId: categoryIdByName.get(p.category),
        taxClassId: null, // category default applies
        variants: p.variants
          ? { create: p.variants.map((v, i) => ({ name: v.name, price: v.price, isDefault: v.isDefault, sortOrder: i + 1 })) }
          : undefined,
      },
    });
    productIdByName.set(p.name, product.id);
  }

  // Spirits take the serve modifier
  const spiritProductIds = PRODUCT_DEFS.filter((p) => p.spiritServe).map((p) => productIdByName.get(p.name)!);
  await prisma.productModifierGroup.createMany({
    data: spiritProductIds.map((productId) => ({ productId, groupId: serveGroup!.id, sortOrder: 1 })),
    skipDuplicates: true,
  });

  // Happy hour: 17:00 to 20:00, 30% off cocktails, all outlets
  const existingHappy = await prisma.priceRule.findFirst({ where: { tenantId, name: 'Happy hour' } });
  if (!existingHappy) {
    await prisma.priceRule.create({
      data: {
        tenantId,
        outletId: null,
        name: 'Happy hour',
        percentOff: '30.00',
        categoryIds: [categoryIdByName.get('Cocktails')!],
        productIds: [],
        days: [0, 1, 2, 3, 4, 5, 6],
        startTime: '17:00',
        endTime: '20:00',
        isActive: true,
      },
    });
  }

  // Outlet settings: 5% service charge on dine-in
  await prisma.outletSettings.upsert({
    where: { outletId },
    update: {},
    create: {
      outletId,
      serviceChargePercent: '5.00',
      serviceChargeTypes: [OrderType.DINE_IN],
      roundingMode: RoundingMode.NEAREST_1,
      orderPrefix: 'A',
      invoicePrefix: 'INV',
      countryCode: 'IN',
    },
  });

  // Floor plan: areas and tables
  const areaIdByName = new Map<string, string>();
  for (const a of AREA_DEFS) {
    const existing = await prisma.area.findFirst({ where: { outletId, name: a.name } });
    const row =
      existing ??
      (await prisma.area.create({
        data: { tenantId, outletId, name: a.name, sortOrder: a.sortOrder, priceMarkupPercent: a.priceMarkupPercent },
      }));
    areaIdByName.set(a.name, row.id);
  }
  for (const t of demoTables()) {
    await prisma.diningTable.upsert({
      where: { outletId_name: { outletId, name: t.name } },
      update: {},
      create: {
        tenantId,
        outletId,
        areaId: areaIdByName.get(t.area)!,
        name: t.name,
        seats: t.seats,
        shape: t.shape,
        posX: t.posX,
        posY: t.posY,
      },
    });
  }

  // Printers and station routes (LAN printers on the demo subnet)
  const printerDefs = [
    { name: 'Counter receipt', host: '192.168.1.30', isReceipt: true },
    { name: 'Main bar BOT', host: '192.168.1.31', isReceipt: false },
    { name: 'Kitchen KOT', host: '192.168.1.32', isReceipt: false },
  ];
  const printerIdByName = new Map<string, string>();
  for (const pr of printerDefs) {
    const existing = await prisma.printer.findFirst({ where: { tenantId, outletId, name: pr.name } });
    const row =
      existing ??
      (await prisma.printer.create({
        data: { tenantId, outletId, name: pr.name, connection: PrinterConnection.LAN, host: pr.host, port: 9100, isReceipt: pr.isReceipt },
      }));
    printerIdByName.set(pr.name, row.id);
  }
  const routes = [
    { station: 'BAR', printer: 'Main bar BOT' },
    { station: 'KITCHEN', printer: 'Kitchen KOT' },
  ];
  for (const r of routes) {
    await prisma.stationRoute.upsert({
      where: { outletId_station: { outletId, station: r.station } },
      update: {},
      create: { tenantId, outletId, station: r.station, printerId: printerIdByName.get(r.printer)! },
    });
  }
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

  // Phase 2 POS demo (menu, floor plan, printers)
  await seedPosDemo(tenantId, outlet.id);

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
