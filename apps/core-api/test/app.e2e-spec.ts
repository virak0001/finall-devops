import { Test, TestingModule } from '@nestjs/testing';
import { ExecutionContext, INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';
import { JwtAuthGuard } from './../src/auth/guards/jwt-auth.guard';
import { RolesGuard } from './../src/auth/guards/roles.guard';

describe('AppController (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate: (context: ExecutionContext) => {
          const request = context.switchToHttp().getRequest();
          request.user = {
            id: 'test-admin',
            email: 'admin@example.com',
            role: 'admin',
          };
          return true;
        },
      })
      .overrideGuard(RolesGuard)
      .useValue({
        canActivate: () => true,
      })
      .compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  it('/ (GET)', () => {
    return request(app.getHttpServer())
      .get('/')
      .expect(200)
      .expect(({ body }) => {
        expect(body.name).toBe('DevOps Learning Hub API');
        expect(body.endpoints.playbooks).toBe('/api/playbooks');
      });
  });

  it('/api/health (GET)', () => {
    return request(app.getHttpServer())
      .get('/api/health')
      .expect(200)
      .expect(({ body }) => {
        expect(body.status).toBe('ok');
        expect(body.database).toBe('up');
      });
  });

  it('/api/playbooks (POST)', async () => {
    const response = await request(app.getHttpServer())
      .post('/api/playbooks')
      .send({
        title: 'Automate rollback drills',
        description:
          'Practice release rollback and verification on every sprint.',
        category: 'resilience',
        difficulty: 'advanced',
        status: 'practicing',
      })
      .expect(201);

    expect(response.body.title).toBe('Automate rollback drills');

    await request(app.getHttpServer())
      .get('/api/playbooks')
      .expect(200)
      .expect(({ body }) => {
        expect(Array.isArray(body)).toBe(true);
        expect(
          body.some(
            (item: { title: string }) =>
              item.title === 'Automate rollback drills',
          ),
        ).toBe(true);
      });
  });

  afterEach(async () => {
    await app.close();
  });
});
