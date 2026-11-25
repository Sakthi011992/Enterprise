import { Module } from '@nestjs/common';
import { CountsService } from './counts.service';
import { InventoryRepository } from './inventory.repository';
import { RecipesController } from './recipes.controller';
import { RecipesService } from './recipes.service';
import { StockItemsController } from './stock-items.controller';
import { StockItemsService } from './stock-items.service';
import { StockOpsController } from './stock-ops.controller';
import { StockUploadsService } from './stock-uploads.service';
import { TransfersService } from './transfers.service';
import { InventorySummaryController, VarianceController } from './variance.controller';
import { VarianceService } from './variance.service';
import { WastageService } from './wastage.service';

/**
 * Stock locations, items, transfers, counts, wastage, variance, kegs, recipes and the inventory summary.
 * Depends on the global StockCoreModule (StockLedgerService, DocumentNumberRepository), RealtimeModule,
 * PermissionsModule and UploadsModule.
 */
@Module({
  controllers: [
    StockItemsController,
    StockOpsController,
    VarianceController,
    InventorySummaryController,
    RecipesController,
  ],
  providers: [
    InventoryRepository,
    StockItemsService,
    TransfersService,
    CountsService,
    WastageService,
    StockUploadsService,
    VarianceService,
    RecipesService,
  ],
  exports: [InventoryRepository, StockItemsService, VarianceService],
})
export class InventoryModule {}
