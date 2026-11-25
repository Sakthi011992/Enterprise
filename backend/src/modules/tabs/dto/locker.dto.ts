import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Matches, MaxLength, Min, MinLength } from 'class-validator';

export class LockerQueryDto {
  @ApiPropertyOptional({ enum: ['ACTIVE', 'FINISHED', 'EXPIRED', 'REMOVED'] })
  @IsOptional()
  @IsIn(['ACTIVE', 'FINISHED', 'EXPIRED', 'REMOVED'])
  status?: 'ACTIVE' | 'FINISHED' | 'EXPIRED' | 'REMOVED';

  @ApiPropertyOptional({ description: 'Guest name, bottle name or card last four' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class CreateLockerDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  guestName: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(20)
  mobile?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Matches(/^\d{4}$/)
  cardLast4?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  stockItemId?: string;

  @ApiProperty({ example: 'Single Malt 12Y 750 ml' })
  @IsString()
  @MinLength(1)
  @MaxLength(160)
  bottleName: string;

  @ApiProperty({ example: 750 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  bottleMl: number;

  @ApiProperty({ example: 610 })
  @Type(() => Number)
  @IsInt()
  @Min(0)
  remainingMl: number;

  @ApiProperty({ example: '2026-12-31', description: 'Business date' })
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  expiresAt: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  orderItemId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}

export class ServeLockerDto {
  @ApiProperty({ example: 60 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  ml: number;
}

export class UpdateLockerDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  guestName?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(20)
  mobile?: string;

  @ApiPropertyOptional({ description: 'Changing it writes an ADJUST event' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  remainingMl?: number;

  @ApiPropertyOptional({ example: '2026-12-31' })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  expiresAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}

export class RemoveLockerDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  reason: string;
}
