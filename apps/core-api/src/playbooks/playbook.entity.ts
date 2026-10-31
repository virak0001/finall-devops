import {
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
  Column,
  UpdateDateColumn,
} from 'typeorm';
import type {
  PlaybookCategory,
  PlaybookDifficulty,
  PlaybookStatus,
} from './playbook.constants';

@Entity({ name: 'playbooks' })
export class Playbook {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 120 })
  title: string;

  @Column({ type: 'text' })
  description: string;

  @Column({ type: 'varchar', length: 40 })
  category: PlaybookCategory;

  @Column({ type: 'varchar', length: 40 })
  difficulty: PlaybookDifficulty;

  @Column({ type: 'varchar', length: 40, default: 'planned' })
  status: PlaybookStatus;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
