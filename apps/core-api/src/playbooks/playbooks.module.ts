import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { Playbook } from './playbook.entity';
import { PlaybooksController } from './playbooks.controller';
import { PlaybooksService } from './playbooks.service';

@Module({
  imports: [TypeOrmModule.forFeature([Playbook]), AuthModule],
  controllers: [PlaybooksController],
  providers: [PlaybooksService],
  exports: [PlaybooksService],
})
export class PlaybooksModule {}
