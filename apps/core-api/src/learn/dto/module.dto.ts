import { IsString, IsInt, IsOptional, Min } from 'class-validator';

export class CreateModuleDto {
  @IsString()
  courseId: string;

  @IsString()
  title: string;

  @IsInt()
  @Min(0)
  order: number;

  @IsOptional()
  @IsString()
  description?: string;
}

export class UpdateModuleDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  order?: number;

  @IsOptional()
  @IsString()
  description?: string;
}
