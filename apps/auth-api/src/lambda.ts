import { NestFactory } from "@nestjs/core";
import { ValidationPipe } from "@nestjs/common";
import serverlessExpress from "@codegenie/serverless-express";
import type { Callback, Context, Handler } from "aws-lambda";
import { AppModule } from "./app.module.js";

let cachedServer: Handler | undefined;

async function bootstrap(): Promise<Handler> {
  const app = await NestFactory.create(AppModule);

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.init();

  const expressApp = app.getHttpAdapter().getInstance();
  return serverlessExpress({ app: expressApp });
}

export const handler: Handler = async (
  event: unknown,
  context: Context,
  callback: Callback,
) => {
  context.callbackWaitsForEmptyEventLoop = false;

  cachedServer ??= await bootstrap();

  return cachedServer(event, context, callback);
};
