import {
  BadRequestException,
  Injectable,
  NotFoundException,
  OnApplicationBootstrap,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DeepPartial, Repository } from 'typeorm';
import { BlogComment } from './blog-comment.entity';
import { BlogPost } from './blog.entity';
import { BlogCompletion } from './blog-completion.entity';
import {
  CreateBlogCommentDto,
  CreateBlogPostDto,
  UpdateBlogPostDto,
} from './dto/blog.dto';

interface AuthUser {
  id?: string;
  email?: string;
}

@Injectable()
export class BlogService implements OnApplicationBootstrap {
  private readonly starterPosts: DeepPartial<BlogPost>[] = [
    {
      title: 'Why I Built This DevOps Learning Platform',
      slug: 'why-i-built-this-devops-learning-platform',
      content:
        'I wanted a single place to practice DevOps workflows with structure. This platform combines tracks, playbooks, and resources so learning is practical and measurable.',
    },
    {
      title: 'From Theory to Practice: My DevOps Learning Routine',
      slug: 'from-theory-to-practice-my-devops-learning-routine',
      content:
        'My weekly routine is simple: learn one concept, build one small project, and write one reflection. Consistency over intensity is the key to long-term progress.',
    },
  ];

  constructor(
    @InjectRepository(BlogPost)
    private readonly postRepository: Repository<BlogPost>,
    @InjectRepository(BlogComment)
    private readonly commentRepository: Repository<BlogComment>,
    @InjectRepository(BlogCompletion)
    private readonly completionRepository: Repository<BlogCompletion>,
  ) {}

  async onApplicationBootstrap() {
    const postCount = await this.postRepository.count();
    if (postCount === 0) {
      await this.postRepository.save(this.starterPosts);
    }
  }

  async findAll() {
    return this.postRepository.find({
      order: { createdAt: 'DESC' },
    });
  }

  async findOneBySlug(slug: string) {
    const post = await this.postRepository.findOne({ where: { slug } });
    if (!post) throw new NotFoundException(`Blog post ${slug} not found`);
    return post;
  }

  async create(dto: CreateBlogPostDto) {
    const slug = await this.generateUniqueSlug(dto.title);
    const post = this.postRepository.create({ ...dto, slug });
    return this.postRepository.save(post);
  }

  async update(id: string, dto: UpdateBlogPostDto) {
    const post = await this.postRepository.findOne({ where: { id } });
    if (!post) throw new NotFoundException(`Blog post ${id} not found`);

    if (dto.title && dto.title !== post.title) {
      post.slug = await this.generateUniqueSlug(dto.title, id);
    }

    Object.assign(post, dto);
    return this.postRepository.save(post);
  }

  async remove(id: string) {
    const post = await this.postRepository.findOne({ where: { id } });
    if (!post) throw new NotFoundException(`Blog post ${id} not found`);

    await this.commentRepository.delete({ postId: id });
    await this.postRepository.remove(post);
    return { deleted: true };
  }

  async findCommentsBySlug(slug: string) {
    const post = await this.findOneBySlug(slug);
    return this.commentRepository.find({
      where: { postId: post.id },
      order: { createdAt: 'DESC' },
    });
  }

  async createComment(slug: string, dto: CreateBlogCommentDto, user?: AuthUser) {
    const post = await this.findOneBySlug(slug);
    const authorEmail = user?.email ?? '';
    const authorName = authorEmail.includes('@')
      ? authorEmail.split('@')[0]
      : 'member';

    const comment = this.commentRepository.create({
      postId: post.id,
      authorEmail,
      authorName,
      content: dto.content,
    });

    return this.commentRepository.save(comment);
  }

  async removeComment(id: string) {
    const comment = await this.commentRepository.findOne({ where: { id } });
    if (!comment) throw new NotFoundException(`Comment ${id} not found`);
    await this.commentRepository.remove(comment);
    return { deleted: true };
  }

  async markComplete(userId: string, slug: string) {
    const post = await this.findOneBySlug(slug);

    const existing = await this.completionRepository.findOne({
      where: { userId, postId: post.id },
    });
    if (existing) return existing;

    const created = this.completionRepository.create({ userId, postId: post.id });
    return this.completionRepository.save(created);
  }

  async isComplete(userId: string, slug: string) {
    const post = await this.findOneBySlug(slug);
    const existing = await this.completionRepository.findOne({
      where: { userId, postId: post.id },
    });
    return !!existing;
  }

  private async generateUniqueSlug(title: string, excludeId?: string) {
    const base = this.slugify(title);
    if (!base) {
      throw new BadRequestException('Unable to generate slug from title');
    }

    let slug = base;
    let suffix = 1;

    while (true) {
      const existing = await this.postRepository.findOne({ where: { slug } });
      if (!existing || existing.id === excludeId) return slug;
      suffix += 1;
      slug = `${base}-${suffix}`;
    }
  }

  private slugify(title: string) {
    return title
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-+|-+$/g, '');
  }
}
