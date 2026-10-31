import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateBlogPostDto {
  @IsString()
  @MinLength(5)
  @MaxLength(140)
  title!: string;

  @IsString()
  @MinLength(20)
  content!: string;
}

export class UpdateBlogPostDto {
  @IsOptional()
  @IsString()
  @MinLength(5)
  @MaxLength(140)
  title?: string;

  @IsOptional()
  @IsString()
  @MinLength(20)
  content?: string;
}

export class CreateBlogCommentDto {
  @IsString()
  @MinLength(2)
  @MaxLength(1000)
  content!: string;
}
