import { Controller, Get, UseGuards } from '@nestjs/common';
import { AppService } from './app.service';
import { JwtAuthGuard } from './auth/guards/jwt-auth.guard';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getApplicationInfo() {
    return this.appService.getApplicationInfo();
  }

  @Get('api/dashboard')
  @UseGuards(JwtAuthGuard)
  getDashboard() {
    return this.appService.getDashboard();
  }
}
