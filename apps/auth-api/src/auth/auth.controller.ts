import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  HttpCode,
  HttpStatus,
  Request,
} from "@nestjs/common";
import { AuthService } from "./auth.service.js";
import { RegisterDto } from "./dto/register.dto.js";
import { LoginDto } from "./dto/login.dto.js";
import { RefreshDto } from "./dto/refresh.dto.js";
import { JwtAuthGuard } from "./guards/jwt-auth.guard.js";
import { JwtRefreshGuard } from "./guards/jwt-refresh.guard.js";

@Controller("api/auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("register")
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Post("login")
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post("refresh")
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtRefreshGuard)
  async refresh(@Request() req, @Body() _dto: RefreshDto) {
    return this.authService.refresh(req.user.id);
  }

  @Post("logout")
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(JwtAuthGuard)
  async logout(@Request() req) {
    await this.authService.logout(req.user.id);
  }

  @Get("validate")
  @UseGuards(JwtAuthGuard)
  validate(@Request() req) {
    return this.authService.validateToken(req.user);
  }

  @Get("me")
  @UseGuards(JwtAuthGuard)
  me(@Request() req) {
    return req.user;
  }
}
