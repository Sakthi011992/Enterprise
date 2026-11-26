import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsIn, IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength, ValidateNested } from 'class-validator';

export class RoundModifierDto {
  @ApiProperty() @IsUUID() groupId: string;
  @ApiProperty() @IsUUID() optionId: string;
}

export class RoundItemDto {
  @ApiProperty() @IsUUID() productId: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() variantId?: string;
  @ApiProperty({ minimum: 1 }) @Type(() => Number) @IsInt() @Min(1) @Max(99) quantity: number;
  @ApiPropertyOptional({ type: [RoundModifierDto] })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => RoundModifierDto)
  modifiers?: RoundModifierDto[];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) note?: string;
}

export class PlaceRoundDto {
  @ApiProperty({ description: 'Client idempotency key' }) @IsString() @MinLength(1) @MaxLength(80) roundKey: string;
  @ApiProperty({ type: [RoundItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => RoundItemDto)
  items: RoundItemDto[];
}

export class ServiceRequestDto {
  @ApiProperty({ enum: ['CALL_WAITER', 'BILL'] }) @IsIn(['CALL_WAITER', 'BILL']) type: 'CALL_WAITER' | 'BILL';
}

export class CheckoutDto {
  @ApiProperty({ enum: ['WAITER', 'ONLINE'] }) @IsIn(['WAITER', 'ONLINE']) mode: 'WAITER' | 'ONLINE';
}
