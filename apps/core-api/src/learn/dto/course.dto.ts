import { IsString, IsOptional, IsInt, IsIn, Min } from 'class-validator';

const levels = ['beginner', 'intermediate', 'advanced'] as const;

export class CreateCourseDto {
  @IsString()
  trackSlug: string;

  @IsString()
  title: string;

  @IsString()
  description: string;

  @IsString()
  @IsIn(levels)
  level: string;

  @IsOptional()
  @IsString()
  color?: string;

  @IsOptional()
  @IsString()
  icon?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  order?: number;
}

export class UpdateCourseDto {
  @IsOptional()
  @IsString()
  trackSlug?: string;

  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  @IsIn(levels)
  level?: string;

  @IsOptional()
  @IsString()
  color?: string;

  @IsOptional()
  @IsString()
  icon?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  order?: number;
}
