import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class OpenDrawerDto {
  @ApiProperty({ example: 'Change for a large note' })
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  reason: string;

  @ApiPropertyOptional({ description: 'Approved NO_SALE approval, needed unless the caller can take payments (EDIT)' })
  @IsOptional()
  @IsUUID()
  approvalId?: string;
}
