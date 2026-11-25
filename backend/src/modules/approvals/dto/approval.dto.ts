import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ApprovalStatus, ApprovalType } from '@prisma/client';
import { IsEnum, IsObject, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength } from 'class-validator';

export class CreateApprovalDto {
  @ApiProperty({ enum: ApprovalType })
  @IsEnum(ApprovalType)
  type: ApprovalType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  orderId?: string;

  @ApiProperty({ description: 'DISCOUNT: {type,value,itemIds,reason}; VOID: {itemIds|"order",reason}; REFUND: {paymentId?,amount,reason}; NO_SALE: {reason}' })
  @IsObject()
  payload: Record<string, unknown>;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;
}

export class DecideApprovalDto {
  @ApiProperty({ enum: ['APPROVED', 'DECLINED'] })
  @IsEnum({ APPROVED: 'APPROVED', DECLINED: 'DECLINED' })
  decision: 'APPROVED' | 'DECLINED';
}

export class ManagerPinApprovalDto extends CreateApprovalDto {
  @ApiProperty()
  @IsUUID()
  managerUserId: string;

  @ApiProperty({ example: '4321' })
  @IsString()
  @Matches(/^\d{4,8}$/, { message: 'PIN must be 4 to 8 digits' })
  pin: string;
}

export class ListApprovalsQuery {
  @ApiPropertyOptional({ enum: ApprovalStatus })
  @IsOptional()
  @IsEnum(ApprovalStatus)
  status?: ApprovalStatus;
}
