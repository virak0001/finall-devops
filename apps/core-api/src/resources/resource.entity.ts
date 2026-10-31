import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

@Entity({ name: 'resources' })
export class Resource {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 160 })
  title: string;

  @Column({ type: 'text' })
  description: string;

  @Column({ type: 'text' })
  url: string;

  @Column({ type: 'varchar', length: 40 })
  type: 'tool' | 'article' | 'cheatsheet' | 'video' | 'reference';

  @Column({ type: 'varchar', length: 60, default: '' })
  track: string;

  @Column({ type: 'simple-array', default: '' })
  tags: string[];

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
