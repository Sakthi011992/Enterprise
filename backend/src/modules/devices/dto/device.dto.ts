import { ApiProperty } from '@nestjs/swagger';
import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';

export const DEVICE_TYPES = ['POS_TABLET', 'KDS', 'TV', 'KIOSK', 'PRINTER', 'PHONE'] as const;

export class CreateDeviceDto {
  @ApiProperty()
  @IsString()
  outletId: string;

  @ApiProperty({ example: 'Bar tablet 1' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  name: string;

  @ApiProperty({ enum: DEVICE_TYPES })
  @IsIn([...DEVICE_TYPES])
  type: (typeof DEVICE_TYPES)[number];
}
