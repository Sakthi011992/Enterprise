import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ApprovalsController } from './approvals.controller';
import { ApprovalsRepository } from './approvals.repository';
import { ApprovalsService } from './approvals.service';
import { AuditTrailRepository } from './audit-trail.repository';
import { AuditTrailService } from './audit-trail.service';

@Module({
  imports: [AuthModule],
  controllers: [ApprovalsController],
  providers: [ApprovalsService, ApprovalsRepository, AuditTrailService, AuditTrailRepository],
  exports: [ApprovalsService, AuditTrailService],
})
export class ApprovalsModule {}
