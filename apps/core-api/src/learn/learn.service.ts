import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Course } from './course.entity';
import { LessonModule } from './module.entity';
import { Lesson } from './lesson.entity';
import { UserProgress } from './user-progress.entity';
import { TrackSlug, DifficultyLevel } from './learn.constants';
import { CreateLessonDto } from './dto/create-lesson.dto';
import { UpdateLessonDto } from './dto/update-lesson.dto';
import { CreateModuleDto, UpdateModuleDto } from './dto/module.dto';
import { CreateCourseDto, UpdateCourseDto } from './dto/course.dto';

@Injectable()
export class LearnService {
  constructor(
    @InjectRepository(Course)
    private readonly courseRepo: Repository<Course>,
    @InjectRepository(LessonModule)
    private readonly moduleRepo: Repository<LessonModule>,
    @InjectRepository(Lesson)
    private readonly lessonRepo: Repository<Lesson>,
    @InjectRepository(UserProgress)
    private readonly progressRepo: Repository<UserProgress>,
  ) {}

  async getTracks() {
    const courses = await this.courseRepo.find({
      order: { order: 'ASC' },
    });
    const counts = await Promise.all(
      courses.map(async (c) => {
        const modules = await this.moduleRepo.find({
          where: { courseId: c.id },
        });
        const modIds = modules.map((m) => m.id);
        const lessonCount = modIds.length
          ? await this.lessonRepo
              .createQueryBuilder('l')
              .where('l.moduleId IN (:...ids)', { ids: modIds })
              .getCount()
          : 0;
        return { courseId: c.id, lessonCount, moduleCount: modules.length };
      }),
    );
    return courses.map((c) => {
      const stat = counts.find((x) => x.courseId === c.id);
      return {
        ...c,
        lessonCount: stat?.lessonCount ?? 0,
        moduleCount: stat?.moduleCount ?? 0,
      };
    });
  }

  async getTrack(trackSlug: string) {
    const course = await this.courseRepo.findOneOrFail({
      where: { trackSlug: trackSlug as TrackSlug },
    });
    const modules = await this.moduleRepo.find({
      where: { courseId: course.id },
      order: { order: 'ASC' },
    });
    const modulesWithLessons = await Promise.all(
      modules.map(async (m) => {
        const lessons = await this.lessonRepo.find({
          where: { moduleId: m.id },
          order: { order: 'ASC' },
          select: ['id', 'title', 'slug', 'type', 'durationMinutes', 'order'],
        });
        return { ...m, lessons };
      }),
    );
    return { ...course, modules: modulesWithLessons };
  }

  async getLesson(slug: string) {
    return this.lessonRepo.findOneOrFail({ where: { slug } });
  }

  async markComplete(userId: string, lessonId: string) {
    const existing = await this.progressRepo.findOne({
      where: { userId, lessonId },
    });
    if (existing) return existing;
    return this.progressRepo.save(
      this.progressRepo.create({ userId, lessonId }),
    );
  }

  async getUserProgress(userId: string) {
    return this.progressRepo.find({ where: { userId } });
  }

  async getTrackProgress(userId: string, trackSlug: string) {
    const course = await this.courseRepo.findOneOrFail({
      where: { trackSlug: trackSlug as TrackSlug },
    });
    const modules = await this.moduleRepo.find({
      where: { courseId: course.id },
    });
    const modIds = modules.map((m) => m.id);
    if (!modIds.length) return { total: 0, completed: 0, percent: 0 };

    const lessons = await this.lessonRepo
      .createQueryBuilder('l')
      .where('l.moduleId IN (:...ids)', { ids: modIds })
      .getMany();

    const lessonIds = lessons.map((l) => l.id);
    if (!lessonIds.length) return { total: 0, completed: 0, percent: 0 };

    const completed = await this.progressRepo
      .createQueryBuilder('p')
      .where('p.userId = :userId', { userId })
      .andWhere('p.lessonId IN (:...lessonIds)', { lessonIds })
      .getCount();

    return {
      total: lessonIds.length,
      completed,
      percent: Math.round((completed / lessonIds.length) * 100),
    };
  }

  // ── Admin methods ──────────────────────────────────────────────────────────

  async getLessonById(id: string) {
    const lesson = await this.lessonRepo.findOne({ where: { id } });
    if (!lesson) throw new NotFoundException(`Lesson ${id} not found`);
    return lesson;
  }

  async createLesson(dto: CreateLessonDto) {
    const lesson = this.lessonRepo.create(dto);
    return this.lessonRepo.save(lesson);
  }

  async updateLesson(id: string, dto: UpdateLessonDto) {
    const lesson = await this.getLessonById(id);
    Object.assign(lesson, dto);
    return this.lessonRepo.save(lesson);
  }

  async deleteLesson(id: string) {
    const lesson = await this.getLessonById(id);
    await this.lessonRepo.remove(lesson);
    return { deleted: true };
  }

  async createModule(dto: CreateModuleDto) {
    const module = this.moduleRepo.create(dto);
    return this.moduleRepo.save(module);
  }

  async updateModule(id: string, dto: UpdateModuleDto) {
    const module = await this.moduleRepo.findOne({ where: { id } });
    if (!module) throw new NotFoundException(`Module ${id} not found`);
    Object.assign(module, dto);
    return this.moduleRepo.save(module);
  }

  async deleteModule(id: string) {
    const module = await this.moduleRepo.findOne({ where: { id } });
    if (!module) throw new NotFoundException(`Module ${id} not found`);
    await this.moduleRepo.remove(module);
    return { deleted: true };
  }

  async createCourse(dto: CreateCourseDto) {
    const course = this.courseRepo.create({
      ...dto,
      trackSlug: dto.trackSlug as TrackSlug,
      level: dto.level as DifficultyLevel,
    });
    return this.courseRepo.save(course);
  }

  async updateCourse(id: string, dto: UpdateCourseDto) {
    const course = await this.courseRepo.findOne({ where: { id } });
    if (!course) throw new NotFoundException(`Track ${id} not found`);
    if (dto.title !== undefined) course.title = dto.title;
    if (dto.description !== undefined) course.description = dto.description;
    if (dto.color !== undefined) course.color = dto.color;
    if (dto.icon !== undefined) course.icon = dto.icon;
    if (dto.order !== undefined) course.order = dto.order;
    if (dto.trackSlug !== undefined) course.trackSlug = dto.trackSlug as TrackSlug;
    if (dto.level !== undefined) course.level = dto.level as DifficultyLevel;
    return this.courseRepo.save(course);
  }

  async deleteCourse(id: string) {
    const course = await this.courseRepo.findOne({ where: { id } });
    if (!course) throw new NotFoundException(`Track ${id} not found`);
    await this.courseRepo.remove(course);
    return { deleted: true };
  }
}
