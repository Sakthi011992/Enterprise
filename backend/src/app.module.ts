import { Module } from '@nestjs/common';
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
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    BlobStorageModule,
    AuthModule,
    UsersModule,
    ProductsModule,
    TaxModule,
    OrdersModule,
    PaymentsModule,
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
  ],
  providers: [
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
})
export class AppModule {}
