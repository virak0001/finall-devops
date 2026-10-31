import { Column, CreateDateColumn, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'blog_completions' })
export class BlogCompletion {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 128 })
  userId: string;

  @Column({ type: 'varchar', length: 128 })
  postId: string;

  @CreateDateColumn()
  createdAt: Date;
}
