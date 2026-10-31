import { IsString, IsInt, IsIn, IsOptional, Min } from 'class-validator';
import type { LessonType } from '../learn.constants';

export class UpdateLessonDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  slug?: string;

  @IsOptional()
  @IsIn(['reading', 'lab', 'quiz'])
  type?: LessonType;

  @IsOptional()
  @IsString()
  content?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  durationMinutes?: number;

  @IsOptional()
  @IsInt()
  @Min(0)
  order?: number;

  @IsOptional()
  @IsString()
  labConfig?: string;
}
