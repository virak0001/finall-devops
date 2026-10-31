import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  UseGuards,
  Request,
} from '@nestjs/common';
import { LearnService } from './learn.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CreateLessonDto } from './dto/create-lesson.dto';
import { UpdateLessonDto } from './dto/update-lesson.dto';
import { CreateModuleDto, UpdateModuleDto } from './dto/module.dto';
import { CreateCourseDto, UpdateCourseDto } from './dto/course.dto';
import type { Request as ExpressRequest } from 'express';

interface AuthRequest extends ExpressRequest {
  user: { id: string; email: string; role: string };
}

@Controller('api/learn')
@UseGuards(JwtAuthGuard)
export class LearnController {
  constructor(private readonly learnService: LearnService) {}

  @Get('tracks')
  getTracks() {
    return this.learnService.getTracks();
  }

  @Get('tracks/:slug')
  getTrack(@Param('slug') slug: string) {
    return this.learnService.getTrack(slug);
  }

  @Get('lessons/:slug')
  getLesson(@Param('slug') slug: string) {
    return this.learnService.getLesson(slug);
  }

  @Post('lessons/:lessonId/complete')
  markComplete(
    @Param('lessonId') lessonId: string,
    @Request() req: AuthRequest,
  ) {
    return this.learnService.markComplete(req.user.id, lessonId);
  }

  @Get('progress')
  getProgress(@Request() req: AuthRequest) {
    return this.learnService.getUserProgress(req.user.id);
  }

  @Get('progress/:slug')
  getTrackProgress(@Param('slug') slug: string, @Request() req: AuthRequest) {
    return this.learnService.getTrackProgress(req.user.id, slug);
  }

  // ── Admin routes ───────────────────────────────────────────────────────────

  @Get('admin/lessons/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  getLessonById(@Param('id') id: string) {
    return this.learnService.getLessonById(id);
  }

  @Post('admin/lessons')
  @Roles('admin')
  @UseGuards(RolesGuard)
  createLesson(@Body() dto: CreateLessonDto) {
    return this.learnService.createLesson(dto);
  }

  @Patch('admin/lessons/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  updateLesson(@Param('id') id: string, @Body() dto: UpdateLessonDto) {
    return this.learnService.updateLesson(id, dto);
  }

  @Delete('admin/lessons/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  deleteLesson(@Param('id') id: string) {
    return this.learnService.deleteLesson(id);
  }

  @Post('admin/modules')
  @Roles('admin')
  @UseGuards(RolesGuard)
  createModule(@Body() dto: CreateModuleDto) {
    return this.learnService.createModule(dto);
  }

  @Patch('admin/modules/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  updateModule(@Param('id') id: string, @Body() dto: UpdateModuleDto) {
    return this.learnService.updateModule(id, dto);
  }

  @Delete('admin/modules/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  deleteModule(@Param('id') id: string) {
    return this.learnService.deleteModule(id);
  }

  @Post('admin/tracks')
  @Roles('admin')
  @UseGuards(RolesGuard)
  createCourse(@Body() dto: CreateCourseDto) {
    return this.learnService.createCourse(dto);
  }

  @Patch('admin/tracks/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  updateCourse(@Param('id') id: string, @Body() dto: UpdateCourseDto) {
    return this.learnService.updateCourse(id, dto);
  }

  @Delete('admin/tracks/:id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  deleteCourse(@Param('id') id: string) {
    return this.learnService.deleteCourse(id);
  }
}
