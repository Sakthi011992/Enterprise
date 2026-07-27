import { IsArray, IsEnum } from 'class-validator';
import { AppFeature } from '@prisma/client';

export class SetUserFeaturesDto {
  @IsArray()
  @IsEnum(AppFeature, { each: true })
  features: AppFeature[];
}
