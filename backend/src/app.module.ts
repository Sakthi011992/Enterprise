import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { ProductsModule } from './modules/products/products.module';
import { TaxModule } from './modules/tax/tax.module';
import { OrdersModule } from './modules/orders/orders.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { ReportsModule } from './modules/reports/reports.module';
import { UploadsModule } from './modules/uploads/uploads.module';
import { InvoiceModule } from './modules/invoice/invoice.module';
import { ThemesModule } from './themes/themes.module';
import { BlobStorageModule } from './common/storage/blob-storage.module';
import { LocalisationModule } from './modules/localisation/localisation.module';
import { BrandingModule } from './modules/branding/branding.module';
import { ProductImagesModule } from './modules/product-images/product-images.module';
import { KioskModule } from './modules/kiosk/kiosk.module';
import { LoginMethodModule } from './modules/login-method/login-method.module';
import { PaymentConfigModule } from './modules/payment-config/payment-config.module';
import { PermissionsModule } from './modules/personas/permissions.module';
import { PersonasModule } from './modules/personas/personas.module';
import { OutletsModule } from './modules/outlets/outlets.module';
import { DevicesModule } from './modules/devices/devices.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { MenuModule } from './modules/menu/menu.module';
import { CategoriesModule } from './modules/categories/categories.module';
import { ModifiersModule } from './modules/modifiers/modifiers.module';
import { CombosModule } from './modules/combos/combos.module';
import { PriceRulesModule } from './modules/price-rules/price-rules.module';
import { TaxClassesModule } from './modules/tax-classes/tax-classes.module';
import { OutletSettingsModule } from './modules/outlet-settings/outlet-settings.module';
import { FloorModule } from './modules/floor/floor.module';
import { PrintingModule } from './modules/printing/printing.module';
import { ApprovalsModule } from './modules/approvals/approvals.module';
import { DayCloseModule } from './modules/day-close/day-close.module';
import { CashDrawerModule } from './modules/cash-drawer/cash-drawer.module';
import { StockCoreModule } from './modules/stock-core/stock-core.module';
import { InventoryModule } from './modules/inventory/inventory.module';
import { ProcurementModule } from './modules/procurement/procurement.module';
import { TabsModule } from './modules/tabs/tabs.module';
import { KdsModule } from './modules/kds/kds.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { GuestConfigModule } from './modules/guest-config/guest-config.module';
import { GuestAuthModule } from './modules/guest-auth/guest-auth.module';
import { GuestCoreModule } from './modules/guest/guest-core.module';
import { GuestModule } from './modules/guest/guest.module';
import { GuestRequestsModule } from './modules/guest-requests/guest-requests.module';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { PermissionGuard } from './common/guards/permission.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { TenantContextMiddleware } from './common/tenancy/tenant-context.middleware';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    BlobStorageModule,
    StockCoreModule,
    RealtimeModule,
    PermissionsModule,
    AuthModule,
    UsersModule,
    PersonasModule,
    OutletsModule,
    DevicesModule,
    NotificationsModule,
    ProductsModule,
    TaxModule,
    TaxClassesModule,
    CategoriesModule,
    ModifiersModule,
    CombosModule,
    PriceRulesModule,
    OutletSettingsModule,
    FloorModule,
    MenuModule,
    PrintingModule,
    OrdersModule,
    PaymentsModule,
    ApprovalsModule,
    DayCloseModule,
    CashDrawerModule,
    ReportsModule,
    UploadsModule,
    InvoiceModule,
    ThemesModule,
    LocalisationModule,
    BrandingModule,
    ProductImagesModule,
    KioskModule,
    LoginMethodModule,
    PaymentConfigModule,
    InventoryModule,
    ProcurementModule,
    TabsModule,
    KdsModule,
    GuestConfigModule,
    GuestAuthModule,
    GuestCoreModule,
    GuestModule,
    GuestRequestsModule,
  ],
  providers: [
    // Registration order is run order: authenticate, then @Can, then legacy @Roles.
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: PermissionGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(TenantContextMiddleware).forRoutes('*');
  }
}
