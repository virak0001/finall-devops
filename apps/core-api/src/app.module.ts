import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AuthModule } from './auth/auth.module';
import { HealthController } from './health/health.controller';
import { PlaybooksModule } from './playbooks/playbooks.module';
import { LearnModule } from './learn/learn.module';
import { ResourcesModule } from './resources/resources.module';
import { BlogModule } from './blog/blog.module';
import { buildPostgresCredentials } from './database.config';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: ['.env.local', '.env', '../.env'],
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const isTest = configService.get<string>('NODE_ENV') === 'test';

        if (isTest) {
          return {
            type: 'sqlite' as const,
            database: ':memory:',
            autoLoadEntities: true,
            synchronize: true,
            dropSchema: true,
          };
        }

        return {
          type: 'postgres' as const,
          ...buildPostgresCredentials((key) => configService.get<string>(key)),
          autoLoadEntities: true,
          synchronize:
            (configService.get<string>('DB_SYNCHRONIZE') ?? 'true') === 'true',
          retryAttempts: 5,
          retryDelay: 2000,
        };
      },
    }),
    AuthModule,
    PlaybooksModule,
    LearnModule,
    ResourcesModule,
    BlogModule,
  ],
  controllers: [AppController, HealthController],
  providers: [AppService],
})
export class AppModule {}
