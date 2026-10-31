import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';

interface ValidateResponse {
  valid: boolean;
  user: { id: string; email: string; role: string };
}

interface AuthenticatedRequest extends Request {
  user?: ValidateResponse['user'];
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly configService: ConfigService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authHeader = request.headers['authorization'];

    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException();
    }

    const token = authHeader.slice(7);
    const authUrl = (
      this.configService.get<string>('AUTH_SERVICE_URL') ??
      'http://localhost:3002'
    ).replace(/\/$/, '');

    let res: Response;
    try {
      res = await fetch(`${authUrl}/api/auth/validate`, {
        headers: { Authorization: `Bearer ${token}` },
      });
    } catch {
      throw new UnauthorizedException('Auth service unreachable');
    }

    if (!res.ok) {
      throw new UnauthorizedException();
    }

    const data = (await res.json()) as ValidateResponse;
    if (!data.valid) {
      throw new UnauthorizedException();
    }

    request.user = data.user;
    return true;
  }
}
