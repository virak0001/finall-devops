import { NestFactory } from "@nestjs/core";
import { Logger, ValidationPipe } from "@nestjs/common";
import { AppModule } from "./app.module.js";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Allow the browser frontend to call this API cross-origin.
  // Set CORS_ORIGIN (comma-separated) in production; defaults to reflecting any origin for dev.
  const corsOrigin = process.env.CORS_ORIGIN;
  app.enableCors({
    origin: corsOrigin ? corsOrigin.split(",").map((o) => o.trim()) : true,
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = process.env.PORT ?? 3000;
  await app.listen(port, "0.0.0.0");

  Logger.log(
    `Application is running on: http://localhost:${port}`,
    "Bootstrap",
  );
}

bootstrap();
