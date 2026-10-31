import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { BlogComment } from './blog-comment.entity';
import { BlogController } from './blog.controller';
import { BlogPost } from './blog.entity';
import { BlogCompletion } from './blog-completion.entity';
import { BlogService } from './blog.service';

@Module({
  imports: [TypeOrmModule.forFeature([BlogPost, BlogComment, BlogCompletion]), AuthModule],
  controllers: [BlogController],
  providers: [BlogService],
  exports: [BlogService],
})
export class BlogModule {}
