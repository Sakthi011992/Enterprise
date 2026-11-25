import { Global, Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PrintService } from './print.service';
import { PrintJobsService } from './print-jobs.service';
import { PrintJobsController } from './print-jobs.controller';
import { PrintersController } from './printers.controller';
import { PrintersService } from './printers.service';
import { PrintingRepository } from './printing.repository';

/** Global so the orders module can inject PrintService without importing this module. */
@Global()
@Module({
  imports: [AuthModule],
  controllers: [PrintersController, PrintJobsController],
  providers: [PrintingRepository, PrintService, PrintersService, PrintJobsService],
  exports: [PrintService],
})
export class PrintingModule {}
