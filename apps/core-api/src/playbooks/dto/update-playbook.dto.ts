import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import {
  playbookCategories,
  playbookDifficulties,
  playbookStatuses,
} from '../playbook.constants';

export class UpdatePlaybookDto {
  @IsOptional()
  @IsString()
  @MinLength(5)
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @IsString()
  @MinLength(20)
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @IsIn(playbookCategories)
  category?: (typeof playbookCategories)[number];

  @IsOptional()
  @IsString()
  @IsIn(playbookDifficulties)
  difficulty?: (typeof playbookDifficulties)[number];

  @IsOptional()
  @IsString()
  @IsIn(playbookStatuses)
  status?: (typeof playbookStatuses)[number];
}
