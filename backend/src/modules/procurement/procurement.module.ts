import { Module } from '@nestjs/common';
import { DebitNotesController, GrnsController } from './grns.controller';
import { DebitNotesService } from './debit-notes.service';
import { GrnsService } from './grns.service';
import { ProcurementRepository } from './procurement.repository';
import { PurchaseOrdersController } from './purchase-orders.controller';
import { PurchaseOrdersService } from './purchase-orders.service';
import { VendorsController } from './vendors.controller';
import { VendorsService } from './vendors.service';

/**
 * Vendors, purchase orders, reorders, goods receipts and debit notes. Depends on the global
 * StockCoreModule (StockLedgerService, DocumentNumberRepository) and RealtimeModule.
 */
@Module({
  controllers: [VendorsController, PurchaseOrdersController, GrnsController, DebitNotesController],
  providers: [ProcurementRepository, VendorsService, PurchaseOrdersService, GrnsService, DebitNotesService],
  exports: [ProcurementRepository, PurchaseOrdersService, GrnsService],
})
export class ProcurementModule {}
