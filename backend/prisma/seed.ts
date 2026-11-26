import {
  PrismaClient,
  Prisma,
  LoginMethod,
  PaymentMethod,
  OrderType,
  Platform,
  PrinterConnection,
  RoundingMode,
  StockLocationKind,
  StockUnit,
  TableShape,
  TicketKind,
} from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { validateTokenPayload } from '../src/themes/theme-tokens.schema';
import { DEFAULT_PERSONAS, PERMISSION_CATALOG } from '../src/common/permissions/catalog';
import { businessDateFor, toDateOnly } from '../src/common/pricing/business-date';

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

// posX / posY are cells on the floor setup grid (12 columns x 8 rows), not pixels.
function demoTables(): { name: string; area: string; seats: number; shape: TableShape; posX: number; posY: number }[] {
  const out: { name: string; area: string; seats: number; shape: TableShape; posX: number; posY: number }[] = [];
  for (let i = 1; i <= 9; i++) {
    out.push({ name: `R${i}`, area: 'Rooftop', seats: 4, shape: TableShape.SQUARE, posX: ((i - 1) % 3) * 2, posY: Math.floor((i - 1) / 3) * 2 });
  }
  for (let i = 1; i <= 4; i++) {
    out.push({ name: `T${i}`, area: 'Indoor', seats: 4, shape: TableShape.ROUND, posX: (i - 1) * 2, posY: 0 });
  }
  for (let i = 1; i <= 10; i++) {
    out.push({ name: `Bar ${i}`, area: 'Bar counter', seats: 1, shape: TableShape.LONG, posX: i - 1, posY: 0 });
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

// ---------------------------------------------------------------------------
// Phase 3 demo: stock locations, items with opening stock and par, recipes, vendors and PO-0317
// (PLAN.md 1.8). Idempotent: rows are looked up or upserted, and opening stock is written once per
// item and location (an OPENING movement is the marker).
// ---------------------------------------------------------------------------

const STOCK_LOCATION_DEFS: { name: string; kind: StockLocationKind; stations: string[]; isDefaultSales: boolean; sortOrder: number }[] = [
  { name: 'Main store', kind: StockLocationKind.STORE, stations: [], isDefaultSales: false, sortOrder: 0 },
  { name: 'Bar', kind: StockLocationKind.BAR, stations: ['BAR'], isDefaultSales: false, sortOrder: 1 },
  { name: 'Kitchen', kind: StockLocationKind.KITCHEN, stations: ['KITCHEN', 'TANDOOR', 'GRILL'], isDefaultSales: true, sortOrder: 2 },
  { name: 'Cellar', kind: StockLocationKind.CELLAR, stations: [], isDefaultSales: false, sortOrder: 3 },
];

const VENDOR_NAMES = ['Metro Spirits Distributors', 'City Breweries Supply', 'Fresh Farm Produce', 'Glassware Co.'];

interface StockDef {
  name: string;
  category: string;
  unit: StockUnit;
  packSize: number;
  packName: string;
  purchaseUnitName: string;
  purchaseUnitQty: number;
  avgCost: string; // ₹ per base unit, 6 dp
  lastPurchaseRate?: string; // ₹ per purchase unit
  vendor?: string;
  isLiquor?: boolean;
  isKeg?: boolean;
  opening: { location: string; qty: number; par?: number }[]; // base units
}

// Prices are taken from PLAN.md where stated (House Whisky, Single Malt, Vodka, lager, keg, stout).
// Other items have no price in the plan: cost stays 0 and opening quantities are demo values.
const STOCK_DEFS: StockDef[] = [
  {
    name: 'House Whisky 750 ml', category: 'Spirits', unit: StockUnit.ML, packSize: 750, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 9000, avgCost: '1.466667', lastPurchaseRate: '13200.00',
    vendor: 'Metro Spirits Distributors', isLiquor: true,
    opening: [{ location: 'Bar', qty: 4500, par: 4500 }, { location: 'Main store', qty: 18000 }],
  },
  {
    name: 'Single Malt 12Y 750 ml', category: 'Spirits', unit: StockUnit.ML, packSize: 750, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 9000, avgCost: '4.160000', lastPurchaseRate: '37440.00',
    vendor: 'Metro Spirits Distributors', isLiquor: true,
    opening: [{ location: 'Bar', qty: 2250, par: 4500 }, { location: 'Main store', qty: 9000 }],
  },
  {
    name: 'Premium Vodka 750 ml', category: 'Spirits', unit: StockUnit.ML, packSize: 750, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 9000, avgCost: '1.933333', lastPurchaseRate: '17400.00',
    vendor: 'Metro Spirits Distributors', isLiquor: true,
    opening: [{ location: 'Bar', qty: 6410, par: 9000 }],
  },
  {
    name: 'Dark Rum 750 ml', category: 'Spirits', unit: StockUnit.ML, packSize: 750, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 9000, avgCost: '1.200000', lastPurchaseRate: '10800.00',
    vendor: 'Metro Spirits Distributors', isLiquor: true,
    opening: [{ location: 'Main store', qty: 9000 }],
  },
  {
    name: 'White Rum 750 ml', category: 'Spirits', unit: StockUnit.ML, packSize: 750, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 9000, avgCost: '1.200000', lastPurchaseRate: '10800.00',
    vendor: 'Metro Spirits Distributors', isLiquor: true,
    opening: [{ location: 'Bar', qty: 4500, par: 4500 }, { location: 'Main store', qty: 9000 }],
  },
  {
    name: 'Premium Lager 650 ml', category: 'Beer', unit: StockUnit.ML, packSize: 650, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 7800, avgCost: '0.487179', lastPurchaseRate: '3800.00',
    vendor: 'City Breweries Supply', isLiquor: true,
    opening: [{ location: 'Cellar', qty: 78000 }],
  },
  {
    name: 'Stout 500 ml', category: 'Beer', unit: StockUnit.ML, packSize: 500, packName: 'btl',
    purchaseUnitName: 'Case of 12 bottles', purchaseUnitQty: 6000, avgCost: '0.566667', lastPurchaseRate: '3400.00',
    vendor: 'City Breweries Supply', isLiquor: true,
    opening: [],
  },
  {
    name: 'Wheat beer keg 30 L', category: 'Beer', unit: StockUnit.ML, packSize: 30000, packName: 'keg',
    purchaseUnitName: 'Keg', purchaseUnitQty: 30000, avgCost: '0.260000', lastPurchaseRate: '7800.00',
    vendor: 'City Breweries Supply', isLiquor: true, isKeg: true,
    opening: [{ location: 'Cellar', qty: 90000 }],
  },
  {
    name: 'Soda 200 ml', category: 'Mixers', unit: StockUnit.ML, packSize: 200, packName: 'btl',
    purchaseUnitName: 'Case of 24 bottles', purchaseUnitQty: 4800, avgCost: '0.000000',
    opening: [{ location: 'Bar', qty: 2000 }],
  },
  {
    name: 'Sugar syrup', category: 'Mixers', unit: StockUnit.ML, packSize: 1000, packName: 'btl',
    purchaseUnitName: 'Bottle 1 L', purchaseUnitQty: 1000, avgCost: '0.000000',
    opening: [{ location: 'Bar', qty: 2000 }],
  },
  {
    name: 'Fresh mint', category: 'Produce', unit: StockUnit.G, packSize: 1000, packName: 'kg pack',
    purchaseUnitName: 'Kg pack', purchaseUnitQty: 1000, avgCost: '0.000000', vendor: 'Fresh Farm Produce',
    opening: [{ location: 'Bar', qty: 600, par: 1000 }],
  },
  {
    name: 'Lime', category: 'Produce', unit: StockUnit.PC, packSize: 1, packName: 'pc',
    purchaseUnitName: 'Crate of 100', purchaseUnitQty: 100, avgCost: '0.000000', vendor: 'Fresh Farm Produce',
    opening: [{ location: 'Bar', qty: 40 }],
  },
  {
    name: 'Chicken wings', category: 'Produce', unit: StockUnit.G, packSize: 1, packName: 'pack',
    purchaseUnitName: 'Kg', purchaseUnitQty: 1000, avgCost: '0.000000', vendor: 'Fresh Farm Produce',
    opening: [{ location: 'Kitchen', qty: 5000 }],
  },
  {
    name: 'Paneer', category: 'Produce', unit: StockUnit.G, packSize: 1, packName: 'pack',
    purchaseUnitName: 'Block 1 kg', purchaseUnitQty: 1000, avgCost: '0.000000', vendor: 'Fresh Farm Produce',
    opening: [{ location: 'Kitchen', qty: 2000 }],
  },
];

async function seedStockDemo(tenantId: string, outletId: string, adminId: string): Promise<void> {
  // Locations
  const locationIdByName = new Map<string, string>();
  for (const def of STOCK_LOCATION_DEFS) {
    const row = await prisma.stockLocation.upsert({
      where: { outletId_name: { outletId, name: def.name } },
      update: {},
      create: { tenantId, outletId, name: def.name, kind: def.kind, stations: def.stations, isDefaultSales: def.isDefaultSales, sortOrder: def.sortOrder },
    });
    locationIdByName.set(def.name, row.id);
  }

  // Vendors
  const vendorIdByName = new Map<string, string>();
  for (const name of VENDOR_NAMES) {
    const row = await prisma.vendor.upsert({
      where: { tenantId_name: { tenantId, name } },
      update: {},
      create: { tenantId, name, paymentTermsDays: 30 },
    });
    vendorIdByName.set(name, row.id);
  }

  // Stock items, opening stock (OPENING movements) and par
  const businessDay = toDateOnly(businessDateFor(new Date(), 'Asia/Kolkata', '05:00'));
  const itemIdByName = new Map<string, string>();
  for (const def of STOCK_DEFS) {
    const item = await prisma.stockItem.upsert({
      where: { tenantId_name: { tenantId, name: def.name } },
      update: {},
      create: {
        tenantId,
        name: def.name,
        categoryName: def.category,
        baseUnit: def.unit,
        packSize: def.packSize,
        packName: def.packName,
        purchaseUnitName: def.purchaseUnitName,
        purchaseUnitQty: def.purchaseUnitQty,
        avgCost: def.avgCost,
        lastPurchaseRate: def.lastPurchaseRate ?? null,
        preferredVendorId: def.vendor ? vendorIdByName.get(def.vendor) ?? null : null,
        isLiquor: def.isLiquor ?? false,
        isKeg: def.isKeg ?? false,
      },
    });
    itemIdByName.set(def.name, item.id);

    for (const op of def.opening) {
      const locationId = locationIdByName.get(op.location)!;
      await prisma.stockLevel.upsert({
        where: { locationId_stockItemId: { locationId, stockItemId: item.id } },
        update: {},
        create: { locationId, stockItemId: item.id, onHand: op.qty, parLevel: op.par ?? 0 },
      });
      const written = await prisma.stockMovement.count({
        where: { tenantId, stockItemId: item.id, locationId, type: 'OPENING' },
      });
      if (written === 0) {
        await prisma.stockMovement.create({
          data: {
            tenantId,
            outletId,
            locationId,
            stockItemId: item.id,
            type: 'OPENING',
            qty: op.qty,
            unitCost: def.avgCost,
            businessDate: businessDay,
            note: 'Opening stock (seed)',
          },
        });
      }
    }
  }

  // Product that the Phase 2 demo menu lacks: Paneer Tikka in Bar bites (KITCHEN station)
  const barBites = await prisma.category.findFirst({ where: { tenantId, name: 'Bar bites' } });
  let paneerTikka = await prisma.product.findFirst({ where: { tenantId, name: 'Paneer Tikka', deletedAt: null } });
  if (!paneerTikka) {
    paneerTikka = await prisma.product.create({
      data: { tenantId, name: 'Paneer Tikka', price: '320.00', categoryId: barBites?.id ?? null },
    });
  }

  // Recipes (PLAN.md 1.8). A recipe is skipped when it already exists for the product and variant.
  const productIdByName = async (name: string) => {
    const p = await prisma.product.findFirst({ where: { tenantId, name, deletedAt: null } });
    if (!p) throw new Error(`Product "${name}" missing for the stock demo`);
    return p.id;
  };
  const variantIdByName = async (productId: string, name: string) => {
    const v = await prisma.productVariant.findFirst({ where: { productId, name } });
    if (!v) throw new Error(`Variant "${name}" missing for the stock demo`);
    return v.id;
  };
  const seedRecipe = async (
    productId: string,
    variantId: string | null,
    lines: { item: string; qty: number; wastage: number }[],
  ) => {
    const existing = await prisma.recipe.findFirst({ where: { productId, variantId } });
    if (existing) return;
    await prisma.recipe.create({
      data: {
        tenantId,
        productId,
        variantId,
        lines: {
          create: lines.map((l, i) => ({
            stockItemId: itemIdByName.get(l.item)!,
            qty: l.qty,
            wastagePercent: l.wastage,
            sortOrder: i,
          })),
        },
      },
    });
  };

  const whisky = await productIdByName('House Whisky');
  await seedRecipe(whisky, await variantIdByName(whisky, '30 ml'), [{ item: 'House Whisky 750 ml', qty: 30, wastage: 2 }]);
  await seedRecipe(whisky, await variantIdByName(whisky, '60 ml'), [{ item: 'House Whisky 750 ml', qty: 60, wastage: 2 }]);
  await seedRecipe(whisky, await variantIdByName(whisky, 'Bottle'), [{ item: 'House Whisky 750 ml', qty: 750, wastage: 0 }]);

  const malt = await productIdByName('Single Malt 12Y');
  await seedRecipe(malt, await variantIdByName(malt, '30 ml'), [{ item: 'Single Malt 12Y 750 ml', qty: 30, wastage: 2 }]);
  await seedRecipe(malt, await variantIdByName(malt, '60 ml'), [{ item: 'Single Malt 12Y 750 ml', qty: 60, wastage: 2 }]);

  await seedRecipe(await productIdByName('Premium Lager 650 ml'), null, [{ item: 'Premium Lager 650 ml', qty: 650, wastage: 0 }]);
  await seedRecipe(await productIdByName('Classic Mojito'), null, [
    { item: 'White Rum 750 ml', qty: 60, wastage: 2 },
    { item: 'Fresh mint', qty: 8, wastage: 0 },
    { item: 'Sugar syrup', qty: 20, wastage: 0 },
    { item: 'Soda 200 ml', qty: 100, wastage: 0 },
    { item: 'Lime', qty: 1, wastage: 0 },
  ]);
  await seedRecipe(await productIdByName('Chicken Wings (8 pc)'), null, [{ item: 'Chicken wings', qty: 400, wastage: 0 }]);
  await seedRecipe(paneerTikka.id, null, [{ item: 'Paneer', qty: 250, wastage: 0 }]);

  // "With soda" modifier draws 200 ml of soda
  await prisma.modifierOption.updateMany({
    where: { name: 'With soda', group: { tenantId } },
    data: { stockItemId: itemIdByName.get('Soda 200 ml')!, stockQty: '200' },
  });

  // PO-0317 sent to City Breweries Supply for the Cellar, so the GRN example can be replayed
  const poExists = await prisma.purchaseOrder.findFirst({ where: { tenantId, number: 'PO-0317' } });
  if (!poExists) {
    const now = new Date();
    await prisma.purchaseOrder.create({
      data: {
        tenantId,
        outletId,
        number: 'PO-0317',
        vendorId: vendorIdByName.get('City Breweries Supply')!,
        locationId: locationIdByName.get('Cellar')!,
        status: 'SENT',
        total: '82800.00',
        createdById: adminId,
        submittedAt: now,
        approvedById: adminId,
        approvedAt: now,
        sentAt: now,
        lines: {
          create: [
            { stockItemId: itemIdByName.get('Premium Lager 650 ml')!, qty: '10', rate: '3800.00', total: '38000.00', sortOrder: 0 },
            { stockItemId: itemIdByName.get('Wheat beer keg 30 L')!, qty: '4', rate: '7800.00', total: '31200.00', sortOrder: 1 },
            { stockItemId: itemIdByName.get('Stout 500 ml')!, qty: '4', rate: '3400.00', total: '13600.00', sortOrder: 2 },
          ],
        },
      },
    });
  }
  await prisma.documentCounter.upsert({
    where: { tenantId_key: { tenantId, key: 'PO' } },
    update: {},
    create: { tenantId, key: 'PO', value: 317 },
  });
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

  // One demo login per remaining persona: password <Persona>@123, PINs below (kiosk has no PIN).
  const kioskRole = await prisma.role.findUniqueOrThrow({ where: { name: 'KIOSK' } });
  const DEMO_USERS: { username: string; displayName: string; persona: string; password: string; pin: string | null }[] = [
    { username: 'manager1', displayName: 'Manager 1', persona: 'manager', password: 'Manager@123', pin: '4826' },
    { username: 'cashier1', displayName: 'Cashier 1', persona: 'cashier', password: 'Cashier@123', pin: '3917' },
    { username: 'captain1', displayName: 'Captain 1', persona: 'captain', password: 'Captain@123', pin: '5173' },
    { username: 'waiter1', displayName: 'Waiter 1', persona: 'waiter', password: 'Waiter@123', pin: '6284' },
    { username: 'chef1', displayName: 'Chef 1', persona: 'chef', password: 'Chef@123', pin: '7395' },
    { username: 'storekeeper1', displayName: 'Storekeeper 1', persona: 'storekeeper', password: 'Storekeeper@123', pin: '8462' },
    { username: 'kiosk1', displayName: 'Kiosk display', persona: 'kiosk', password: 'Kiosk@123', pin: null },
  ];
  for (const d of DEMO_USERS) {
    const user = await prisma.user.upsert({
      where: { username: d.username },
      update: {},
      create: {
        tenantId,
        username: d.username,
        email: `${d.username}@example.com`,
        displayName: d.displayName,
        passwordHash: await bcrypt.hash(d.password, 10),
        roleId: d.persona === 'kiosk' ? kioskRole.id : userRole.id,
        isActive: true,
      },
    });
    await prisma.userOutlet.upsert({
      where: { userId_outletId: { userId: user.id, outletId: outlet.id } },
      update: {},
      create: { userId: user.id, outletId: outlet.id, personaId: requireId(personaIds, d.persona), isDefault: true },
    });
    if (d.pin) {
      await prisma.staffPin.upsert({
        where: { userId: user.id },
        update: {},
        create: { userId: user.id, pinHash: await bcrypt.hash(d.pin, 10) },
      });
    }
  }

  // Phase 2 POS demo (menu, floor plan, printers)
  await seedPosDemo(tenantId, outlet.id);

  // Phase 3 demo (stock, recipes, vendors, PO-0317)
  await seedStockDemo(tenantId, outlet.id, admin.id);

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

  // Default theme "Ink & Emerald" (docs/ui-design/ink-emerald). Same values as the app's built-in
  // fallback. It is assigned only to platforms that have no theme yet, so a chosen theme is kept.
  const inkEmerald = JSON.parse(readFileSync(join(__dirname, 'themes', 'ink-emerald.json'), 'utf8'));
  validateTokenPayload(inkEmerald);
  const defaultTheme = await prisma.theme.upsert({
    where: { name: 'Ink & Emerald' },
    create: {
      name: 'Ink & Emerald',
      description: 'Default theme: ink navigation, white cards, one emerald accent.',
      tokens: inkEmerald,
      schemaVersion: inkEmerald.schemaVersion,
      createdById: admin.id,
    },
    update: {},
  });
  for (const platform of [Platform.WEB, Platform.ANDROID, Platform.IOS]) {
    const assigned = await prisma.themeAssignment.findUnique({ where: { platform } });
    if (!assigned) {
      await prisma.themeAssignment.create({ data: { platform, themeId: defaultTheme.id, updatedById: admin.id } });
    }
  }

  console.log(`Seed complete. Admin login: ${username} / ${password}. Demo: bartender1 / Bartender@123, PIN 2580; manager1, cashier1, captain1, waiter1, chef1, storekeeper1, kiosk1 (password <Persona>@123).`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
