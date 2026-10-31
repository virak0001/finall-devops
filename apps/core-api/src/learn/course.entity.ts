import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToMany,
} from 'typeorm';
import type { TrackSlug, DifficultyLevel } from './learn.constants';
import { LessonModule } from './module.entity';

@Entity({ name: 'courses' })
export class Course {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 60, unique: true })
  trackSlug: TrackSlug;

  @Column({ length: 120 })
  title: string;

  @Column({ type: 'text' })
  description: string;

  @Column({ type: 'varchar', length: 40 })
  level: DifficultyLevel;

  @Column({ type: 'varchar', length: 20, default: '#2ec4b6' })
  color: string;

  @Column({ type: 'varchar', length: 60, default: '' })
  icon: string;

  @Column({ type: 'int', default: 0 })
  order: number;

  @OneToMany(() => LessonModule, (m) => m.course, { cascade: true })
  modules: LessonModule[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
