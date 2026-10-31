import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { BlogService } from './blog.service';
import {
  CreateBlogCommentDto,
  CreateBlogPostDto,
  UpdateBlogPostDto,
} from './dto/blog.dto';

interface AuthenticatedRequest extends Request {
  user?: {
    id?: string;
    email?: string;
    role?: string;
  };
}

@Controller('api/blog')
export class BlogController {
  constructor(private readonly blogService: BlogService) {}

  @Get()
  findAll() {
    return this.blogService.findAll();
  }

  @Get(':slug')
  findOne(@Param('slug') slug: string) {
    return this.blogService.findOneBySlug(slug);
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  create(@Body() dto: CreateBlogPostDto) {
    return this.blogService.create(dto);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  update(@Param('id') id: string, @Body() dto: UpdateBlogPostDto) {
    return this.blogService.update(id, dto);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  remove(@Param('id') id: string) {
    return this.blogService.remove(id);
  }

  @Post('admin/posts')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  createAdmin(@Body() dto: CreateBlogPostDto) {
    return this.blogService.create(dto);
  }

  @Patch('admin/posts/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  updateAdmin(@Param('id') id: string, @Body() dto: UpdateBlogPostDto) {
    return this.blogService.update(id, dto);
  }

  @Delete('admin/posts/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  removeAdmin(@Param('id') id: string) {
    return this.blogService.remove(id);
  }

  @Get(':slug/comments')
  findComments(@Param('slug') slug: string) {
    return this.blogService.findCommentsBySlug(slug);
  }

  @Post(':slug/comments')
  @UseGuards(JwtAuthGuard)
  createComment(
    @Param('slug') slug: string,
    @Body() dto: CreateBlogCommentDto,
    @Req() request: AuthenticatedRequest,
  ) {
    return this.blogService.createComment(slug, dto, request.user);
  }

  @Post(':slug/complete')
  @UseGuards(JwtAuthGuard)
  markComplete(@Param('slug') slug: string, @Req() request: AuthenticatedRequest) {
    if (!request.user?.id) throw new UnauthorizedException();
    const userId = request.user.id;
    return this.blogService.markComplete(userId, slug);
  }

  @Get(':slug/complete')
  @UseGuards(JwtAuthGuard)
  checkComplete(@Param('slug') slug: string, @Req() request: AuthenticatedRequest) {
    if (!request.user?.id) throw new UnauthorizedException();
    const userId = request.user.id;
    return this.blogService.isComplete(userId, slug);
  }
  @Delete('comments/:id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  removeComment(@Param('id') id: string) {
    return this.blogService.removeComment(id);
  }
}
