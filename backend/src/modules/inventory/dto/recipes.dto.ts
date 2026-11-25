import { Type } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsDefined, IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { DecimalInput } from '../decimal-input';

export class RecipeLineDto {
  @IsString()
  stockItemId: string;

  @IsDefined()
  qty: DecimalInput;

  @IsOptional()
  wastagePercent?: DecimalInput;
}

export class RecipeDto {
  /** null = all variants without their own recipe. */
  @IsOptional()
  @IsString()
  variantId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  note?: string | null;

  @IsArray()
  @ArrayMaxSize(60)
  @ValidateNested({ each: true })
  @Type(() => RecipeLineDto)
  lines: RecipeLineDto[];
}

export class PutRecipesDto {
  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => RecipeDto)
  recipes: RecipeDto[];
}
