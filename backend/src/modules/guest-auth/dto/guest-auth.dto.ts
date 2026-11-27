import { IsBoolean, IsOptional, IsString } from 'class-validator';

// Fields are loosely typed on purpose: GuestAuthService validates them and answers with the
// stable error codes of PLAN 2.3 (NAME_INVALID, PHONE_INVALID, CONSENT_REQUIRED, ...).

export class GuestStartDto {
  @IsOptional() @IsString() deviceKey?: string;
  @IsOptional() @IsString() name?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsBoolean() consent?: boolean;
}

export class GuestVerifyDto {
  @IsOptional() @IsString() verificationId?: string;
  @IsOptional() @IsString() code?: string;
}
