import { Global, Module } from '@nestjs/common';
import { DocumentNumberRepository } from './document-number.repository';
import { StockLedgerRepository } from './stock-ledger.repository';
import { StockLedgerService } from './stock-ledger.service';

/** Shared stock ledger and document numbers. Global so inventory, procurement and orders can inject them. */
@Global()
@Module({
  providers: [StockLedgerRepository, StockLedgerService, DocumentNumberRepository],
  exports: [StockLedgerService, DocumentNumberRepository],
})
export class StockCoreModule {}
