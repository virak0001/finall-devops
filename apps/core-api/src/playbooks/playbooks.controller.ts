import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { CreatePlaybookDto } from './dto/create-playbook.dto';
import { UpdatePlaybookDto } from './dto/update-playbook.dto';
import { PlaybooksService } from './playbooks.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';

@Controller('api/playbooks')
@UseGuards(JwtAuthGuard)
export class PlaybooksController {
  constructor(private readonly playbooksService: PlaybooksService) {}

  @Get()
  findAll() {
    return this.playbooksService.findAll();
  }

  @Post()
  @Roles('admin')
  @UseGuards(RolesGuard)
  create(@Body() createPlaybookDto: CreatePlaybookDto) {
    return this.playbooksService.create(createPlaybookDto);
  }

  @Patch(':id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  update(@Param('id') id: string, @Body() dto: UpdatePlaybookDto) {
    return this.playbooksService.update(id, dto);
  }

  @Delete(':id')
  @Roles('admin')
  @UseGuards(RolesGuard)
  remove(@Param('id') id: string) {
    return this.playbooksService.remove(id);
  }
}
