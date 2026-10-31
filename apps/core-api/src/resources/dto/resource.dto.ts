import {
  IsArray,
  IsIn,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
} from 'class-validator';

const resourceTypes = [
  'tool',
  'article',
  'cheatsheet',
  'video',
  'reference',
] as const;

export class CreateResourceDto {
  @IsString()
  @MaxLength(160)
  title: string;

  @IsString()
  description: string;

  @IsUrl()
  url: string;

  @IsIn(resourceTypes)
  type: (typeof resourceTypes)[number];

  @IsString()
  track: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];
}

export class UpdateResourceDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsUrl()
  url?: string;

  @IsOptional()
  @IsIn(resourceTypes)
  type?: (typeof resourceTypes)[number];

  @IsOptional()
  @IsString()
  track?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];
}
