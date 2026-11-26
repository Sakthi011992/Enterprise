import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Max, Min, ValidateNested } from 'class-validator';
import {
  GUEST_CHECKOUT_MODES,
  GUEST_ROUTINGS,
  GUEST_VERIFICATION_METHODS,
  GuestCheckoutMode,
  GuestRouting,
  GuestVerificationMethod,
} from '../guest-config.types';

export class GuestVerificationSettingsDto {
  @ApiPropertyOptional({ enum: GUEST_VERIFICATION_METHODS })
  @IsOptional()
  @IsIn(GUEST_VERIFICATION_METHODS as string[])
  method?: GuestVerificationMethod;

  @ApiPropertyOptional({ description: 'Static OTP length, 4 to 8 digits' })
  @IsOptional()
  @IsInt()
  @Min(4)
  @Max(8)
  codeLength?: number;

  @ApiPropertyOptional({ description: 'New static OTP (digits). Stored hashed; never returned.' })
  @IsOptional()
  @IsString()
  newStaticOtp?: string;
}

/** PUT /settings/guest. Every field is optional; omitted fields keep their current value. */
export class UpdateGuestConfigDto {
  @IsOptional() @IsBoolean() enabled?: boolean;

  @ApiPropertyOptional({ enum: GUEST_ROUTINGS })
  @IsOptional()
  @IsIn(GUEST_ROUTINGS as string[])
  routing?: GuestRouting;

  @IsOptional()
  @ValidateNested()
  @Type(() => GuestVerificationSettingsDto)
  verification?: GuestVerificationSettingsDto;

  @IsOptional() @IsBoolean() ageGate?: boolean;
  @IsOptional() @IsInt() @Min(18) @Max(30) minAge?: number;
  @IsOptional() @IsBoolean() requireSeated?: boolean;
  @IsOptional() @IsInt() @Min(1) @Max(120) requestTtlMinutes?: number;
  @IsOptional() @IsInt() @Min(1) @Max(99) maxQtyPerLine?: number;
  @IsOptional() @IsInt() @Min(1) @Max(100) maxLinesPerRound?: number;
  @IsOptional() @IsBoolean() allowGuestCancel?: boolean;

  @ApiPropertyOptional({ enum: GUEST_CHECKOUT_MODES })
  @IsOptional()
  @IsIn(GUEST_CHECKOUT_MODES as string[])
  checkout?: GuestCheckoutMode;
}
