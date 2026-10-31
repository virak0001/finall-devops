import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { playbookCategories } from './playbooks/playbook.constants';
import { PlaybooksService } from './playbooks/playbooks.service';

@Injectable()
export class AppService {
  constructor(
    private readonly configService: ConfigService,
    private readonly playbooksService: PlaybooksService,
  ) {}

  getApplicationInfo() {
    return {
      name:
        this.configService.get<string>('APP_NAME') ?? 'DevOps Learning Hub API',
      message:
        'NestJS API powering a Nuxt 4 + PostgreSQL DevOps learning platform.',
      generatedAt: new Date().toISOString(),
      endpoints: {
        health: '/api/health',
        dashboard: '/api/dashboard',
        playbooks: '/api/playbooks',
      },
      stack: ['nestjs', 'postgresql', 'docker', 'docker-swarm'],
    };
  }

  async getDashboard() {
    const summary = await this.playbooksService.getSummary();

    return {
      appName:
        this.configService.get<string>('APP_NAME') ?? 'DevOps Learning Hub API',
      environment: this.configService.get<string>('NODE_ENV') ?? 'development',
      generatedAt: new Date().toISOString(),
      tagline:
        'Practice delivery, observability, resilience, and security workflows with a stack designed for Docker and Swarm.',
      highlights: [
        'Nuxt 4 frontend proxies API calls through Nitro server routes.',
        'NestJS persists learning playbooks in PostgreSQL with startup seed data.',
        'Docker Compose handles local orchestration while Docker Swarm scales replicas.',
      ],
      commands: {
        compose: 'docker compose up --build',
        swarm: 'docker stack deploy -c docker-stack.yml devops-learning',
      },
      metrics: {
        totalPlaybooks: summary.total,
        practicing: summary.practicing,
        validated: summary.validated,
        learningTracks: playbookCategories.length,
      },
      categories: summary.categories.map((category) => ({
        key: category.key,
        label: this.toLabel(category.key),
        total: category.total,
      })),
      recentPlaybooks: summary.recent,
    };
  }

  private toLabel(value: string) {
    return value
      .split('-')
      .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
      .join(' ');
  }
}
