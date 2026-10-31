import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  OneToMany,
  JoinColumn,
  CreateDateColumn,
} from 'typeorm';
import { Course } from './course.entity';
import { Lesson } from './lesson.entity';

@Entity({ name: 'lesson_modules' })
export class LessonModule {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  courseId: string;

  @ManyToOne(() => Course, (c) => c.modules, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'courseId' })
  course: Course;

  @Column({ length: 120 })
  title: string;

  @Column({ type: 'int', default: 0 })
  order: number;

  @OneToMany(() => Lesson, (l) => l.module, { cascade: true })
  lessons: Lesson[];

  @CreateDateColumn()
  createdAt: Date;
}
