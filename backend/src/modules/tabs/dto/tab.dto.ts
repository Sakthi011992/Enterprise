import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, Matches, MaxLength, Min, MinLength } from 'class-validator';

export const TAB_SECURITY = ['CARD_PREAUTH', 'CASH_DEPOSIT', 'HOUSE_ACCOUNT', 'NONE'] as const;
export const TAB_LINK = ['BAR_SEAT', 'TABLE', 'QUEUE_TOKEN', 'NONE'] as const;

export class TabQueryDto {
  @ApiPropertyOptional({ enum: ['OPEN', 'CLOSED'] })
  @IsOptional()
  @IsIn(['OPEN', 'CLOSED', 'VOID'])
  status?: 'OPEN' | 'CLOSED' | 'VOID';

  @ApiPropertyOptional({ enum: ['today', 'all'], default: 'today' })
  @IsOptional()
  @IsIn(['today', 'all'])
  scope?: 'today' | 'all';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  openedById?: string;
}

export class OpenTabDto {
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

  @ApiProperty()
  @IsBoolean()
  ageChecked: boolean;

  @ApiProperty({ enum: TAB_SECURITY })
  @IsIn(TAB_SECURITY)
  security: (typeof TAB_SECURITY)[number];

  @ApiPropertyOptional({ description: 'CARD_PREAUTH: last four digits of the card' })
  @IsOptional()
  @Matches(/^\d{4}$/)
  cardLast4?: string;

  @ApiPropertyOptional({ description: 'Pre-auth hold (card) or cash deposit' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  amountHeld?: number;

  @ApiPropertyOptional({ description: 'HOUSE_ACCOUNT: "Corporate: Acme"' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  houseAccount?: string;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  tabLimit: number;

  @ApiPropertyOptional({ enum: [80, 90], default: 80 })
  @IsOptional()
  @Type(() => Number)
  @IsIn([80, 90])
  warnAtPercent?: number;

  @ApiProperty({ enum: TAB_LINK })
  @IsIn(TAB_LINK)
  linkType: (typeof TAB_LINK)[number];

  @ApiPropertyOptional({ example: 'Bar seat 3' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  linkLabel?: string;

  @ApiPropertyOptional({ description: 'Required when linkType is TABLE' })
  @IsOptional()
  @IsString()
  tableId?: string;

  @ApiPropertyOptional({ description: 'TAB_NO_SECURITY approval, when security is NONE and the caller has no APPROVE' })
  @IsOptional()
  @IsString()
  approvalId?: string;
}

export class UpdateTabDto {
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

  @ApiPropertyOptional({ description: 'New limit. Checked against sales.tab.open like opening a tab' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(1)
  tabLimit?: number;

  @ApiPropertyOptional({ enum: [80, 90] })
  @IsOptional()
  @Type(() => Number)
  @IsIn([80, 90])
  warnAtPercent?: number;

  @ApiPropertyOptional({ enum: ['BAR_SEAT', 'QUEUE_TOKEN', 'NONE'] })
  @IsOptional()
  @IsIn(['BAR_SEAT', 'QUEUE_TOKEN', 'NONE'])
  linkType?: 'BAR_SEAT' | 'QUEUE_TOKEN' | 'NONE';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(60)
  linkLabel?: string;
}

export class MoveTabDto {
  @ApiProperty()
  @IsString()
  tableId: string;
}

export class VoidTabDto {
  @ApiProperty()
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  reason: string;
}
