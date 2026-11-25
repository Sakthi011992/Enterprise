import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { ApprovalsService } from './approvals.service';
import { CreateApprovalDto, DecideApprovalDto, ListApprovalsQuery, ManagerPinApprovalDto } from './dto/approval.dto';
import { Can } from '../../common/decorators/can.decorator';
import { CurrentUser, AuthUser } from '../../common/decorators/current-user.decorator';

@ApiTags('approvals')
@ApiBearerAuth()
@Controller('approvals')
export class ApprovalsController {
  constructor(private readonly approvals: ApprovalsService) {}

  @Can('sales.orders.take', 'EDIT')
  @Post()
  @ApiOperation({ summary: 'Ask a manager for approval (PENDING, expires in 15 min)' })
  create(@Body() dto: CreateApprovalDto, @CurrentUser() auth: AuthUser) {
    return this.approvals.create(auth, dto);
  }

  @Can('sales.orders.take', 'EDIT')
  @Post('pin')
  @ApiOperation({ summary: 'Manager PIN at this device: create and approve in one step' })
  pin(@Body() dto: ManagerPinApprovalDto, @CurrentUser() auth: AuthUser) {
    return this.approvals.approveWithPin(auth, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Read one approval (polled while waiting)' })
  get(@Param('id') id: string, @CurrentUser() auth: AuthUser) {
    return this.approvals.get(auth, id);
  }

  @Get()
  @ApiOperation({ summary: 'List approvals of this outlet, optionally by status' })
  list(@Query() q: ListApprovalsQuery, @CurrentUser() auth: AuthUser) {
    return this.approvals.list(auth, q.status);
  }

  @Post(':id/decide')
  @ApiOperation({ summary: 'Approver accepts or declines a pending approval' })
  decide(@Param('id') id: string, @Body() dto: DecideApprovalDto, @CurrentUser() auth: AuthUser) {
    return this.approvals.decide(auth, id, dto);
  }
}
