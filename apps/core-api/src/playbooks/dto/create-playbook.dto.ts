import { IsIn, IsString, MaxLength, MinLength } from 'class-validator';
import {
  playbookCategories,
  playbookDifficulties,
  playbookStatuses,
} from '../playbook.constants';

export class CreatePlaybookDto {
  @IsString()
  @MinLength(5)
  @MaxLength(120)
  title: string;

  @IsString()
  @MinLength(20)
  @MaxLength(500)
  description: string;

  @IsString()
  @IsIn(playbookCategories)
  category: (typeof playbookCategories)[number];

  @IsString()
  @IsIn(playbookDifficulties)
  difficulty: (typeof playbookDifficulties)[number];

  @IsString()
  @IsIn(playbookStatuses)
  status: (typeof playbookStatuses)[number];
}
