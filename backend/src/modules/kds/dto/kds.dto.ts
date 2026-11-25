import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class BoardQueryDto {
  @ApiPropertyOptional({ description: 'BAR, KITCHEN, ... or ALL (default)' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  station?: string;

  @ApiPropertyOptional({ enum: ['active', 'done'], default: 'active' })
  @IsOptional()
  @IsIn(['active', 'done'])
  view?: 'active' | 'done';
}

export class ReadyQueryDto {
  @ApiPropertyOptional({ enum: ['true', 'false'] })
  @IsOptional()
  @IsIn(['true', 'false'])
  mine?: 'true' | 'false';
}
