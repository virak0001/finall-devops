import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { Course } from './course.entity';
import { LessonModule as LessonModuleEntity } from './module.entity';
import { Lesson } from './lesson.entity';
import { UserProgress } from './user-progress.entity';
import { LearnController } from './learn.controller';
import { LearnService } from './learn.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Course,
      LessonModuleEntity,
      Lesson,
      UserProgress,
    ]),
    AuthModule,
  ],
  controllers: [LearnController],
  providers: [LearnService],
  exports: [LearnService],
})
export class LearnModule {}
