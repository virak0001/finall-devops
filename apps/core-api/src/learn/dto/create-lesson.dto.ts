import { IsString, IsInt, IsIn, IsOptional, Min } from 'class-validator';
import type { LessonType } from '../learn.constants';

export class CreateLessonDto {
  @IsString()
  title: string;

  @IsString()
  slug: string;

  @IsString()
  moduleId: string;

  @IsIn(['reading', 'lab', 'quiz'])
  type: LessonType;

  @IsString()
  content: string;

  @IsInt()
  @Min(1)
  durationMinutes: number;

  @IsInt()
  @Min(0)
  order: number;

  @IsOptional()
  @IsString()
  labConfig?: string;
}
