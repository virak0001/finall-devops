import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Controller('api/health')
export class HealthController {
  constructor(private readonly dataSource: DataSource) {}

  @Get()
  async checkHealth() {
    try {
      await this.dataSource.query('SELECT 1');

      return {
        status: 'ok',
        service: 'core-api',
        database: 'up',
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      throw new ServiceUnavailableException({
        status: 'degraded',
        database: 'down',
        timestamp: new Date().toISOString(),
        message:
          error instanceof Error
            ? error.message
            : 'Database health check failed.',
      });
    }
  }
}
