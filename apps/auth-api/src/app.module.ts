import { Module } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { TypeOrmModule } from "@nestjs/typeorm";
import { HealthController } from "./health/health.controller.js";
import { UsersModule } from "./users/users.module.js";
import { AuthModule } from "./auth/auth.module.js";

const isTrue = (value?: string): boolean =>
  value === "true" || value === "1" || value === "yes";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      // /run/secrets/auth_env is the swarm secret (see docker-swarm/secrets/);
      // absent outside the swarm, where the local .env files apply instead.
      envFilePath: ["/run/secrets/auth_env", ".env.local", ".env"],
    }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const isTest = configService.get<string>("NODE_ENV") === "test";

        if (isTest) {
          return {
            type: "sqlite" as const,
            database: ":memory:",
            autoLoadEntities: true,
            synchronize: true,
            dropSchema: true,
          };
        }

        const databaseUrl = configService.get<string>("DATABASE_URL");

        return {
          type: "postgres" as const,
          // Prefer a full connection string (DATABASE_URL) when provided;
          // otherwise assemble the connection from the individual DB_* vars.
          ...(databaseUrl
            ? { url: databaseUrl }
            : {
                host: configService.get<string>("DB_HOST") ?? "localhost",
                port: Number.parseInt(
                  configService.get<string>("DB_PORT") ?? "5432",
                  10,
                ),
                username: configService.get<string>("DB_USERNAME") ?? "devops",
                password: configService.get<string>("DB_PASSWORD") ?? "devops123",
                database:
                  configService.get<string>("DB_DATABASE") ?? "devops_auth",
              }),
          ssl: isTrue(configService.get<string>("DB_SSL"))
            ? {
                rejectUnauthorized: isTrue(
                  configService.get<string>("DB_SSL_REJECT_UNAUTHORIZED"),
                ),
              }
            : false,
          autoLoadEntities: true,
          synchronize:
            (configService.get<string>("DB_SYNCHRONIZE") ?? "true") === "true",
          retryAttempts: 2,
          retryDelay: 1000,
        };
      },
    }),
    UsersModule,
    AuthModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
