import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsArray, IsOptional, IsString, MaxLength, MinLength, ValidateNested } from 'class-validator';
import { RoundItemDto } from '../../guest/dto/guest.dto';

export class ConfirmRequestDto {
  @ApiPropertyOptional({ type: [RoundItemDto], description: 'Edited lines (remove, quantity, notes). Omit to confirm as placed.' })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => RoundItemDto)
  items?: RoundItemDto[];
}

export class RejectRequestDto {
  @ApiProperty() @IsString() @MinLength(1) @MaxLength(200) reason: string;
}
