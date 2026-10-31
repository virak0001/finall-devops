import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { AppController } from './app.controller';
import { AppService } from './app.service';

describe('AppController', () => {
  let appController: AppController;
  const appServiceMock = {
    getApplicationInfo: jest.fn(() => ({
      name: 'DevOps Learning Hub API',
      endpoints: {
        health: '/api/health',
      },
    })),
    getDashboard: jest.fn(async () => ({
      metrics: {
        totalPlaybooks: 4,
      },
    })),
  };

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
      providers: [
        {
          provide: AppService,
          useValue: appServiceMock,
        },
        {
          provide: ConfigService,
          useValue: {
            get: jest.fn(),
          },
        },
      ],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('getApplicationInfo', () => {
    it('returns the API metadata', () => {
      expect(appController.getApplicationInfo()).toEqual(
        expect.objectContaining({
          name: 'DevOps Learning Hub API',
          endpoints: expect.objectContaining({
            health: '/api/health',
          }),
        }),
      );
    });
  });

  describe('getDashboard', () => {
    it('returns dashboard metrics', async () => {
      await expect(appController.getDashboard()).resolves.toEqual(
        expect.objectContaining({
          metrics: expect.objectContaining({
            totalPlaybooks: 4,
          }),
        }),
      );
    });
  });
});
