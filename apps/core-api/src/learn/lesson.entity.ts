import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';
import type { LessonType } from './learn.constants';
import { LessonModule } from './module.entity';

@Entity({ name: 'lessons' })
export class Lesson {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid' })
  moduleId: string;

  @ManyToOne(() => LessonModule, (m) => m.lessons, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'moduleId' })
  module: LessonModule;

  @Column({ length: 160 })
  title: string;

  @Column({ type: 'varchar', length: 200, unique: true })
  slug: string;

  @Column({ type: 'text' })
  content: string;

  @Column({ type: 'varchar', length: 20, default: 'reading' })
  type: LessonType;

  @Column({ type: 'int', default: 5 })
  durationMinutes: number;

  @Column({ type: 'int', default: 0 })
  order: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
