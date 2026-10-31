/**
 * Postgres connection settings shared by the Nest runtime (app.module.ts)
 * and the TypeORM CLI (data-source.ts), so both connect to the same database.
 *
 * Two ways to configure it:
 *   1. DATABASE_URL — a single connection string, e.g.
 *      postgresql://user:pass@host/db?sslmode=require
 *   2. The discrete DB_HOST / DB_PORT / DB_USERNAME / DB_PASSWORD / DB_DATABASE
 *      variables (used when DATABASE_URL is absent).
 */

/** Reads a single env var — `process.env` directly, or Nest's ConfigService. */
export type EnvReader = (key: string) => string | undefined;

export type PostgresCredentials = {
  url?: string;
  host?: string;
  port?: number;
  username?: string;
  password?: string;
  database?: string;
  ssl?: boolean | { rejectUnauthorized: boolean };
};

const isTrue = (value?: string): boolean =>
  value === 'true' || value === '1' || value === 'yes';

export function buildPostgresCredentials(env: EnvReader): PostgresCredentials {
  const url = env('DATABASE_URL');
  const sslOverride = env('DB_SSL');

  const ssl = isTrue(sslOverride)
    ? { rejectUnauthorized: isTrue(env('DB_SSL_REJECT_UNAUTHORIZED')) }
    : false;

  if (url) {
    return {
      url,
      // Without an explicit DB_SSL the pg driver derives TLS from the
      // connection string itself (sslmode / channel_binding / uselibpqcompat),
      // which is what hosted providers such as Neon and RDS hand out.
      ...(sslOverride === undefined ? {} : { ssl }),
    };
  }

  return {
    host: env('DB_HOST') ?? 'localhost',
    port: Number.parseInt(env('DB_PORT') ?? '5432', 10),
    username: env('DB_USERNAME') ?? 'devops',
    password: env('DB_PASSWORD') ?? 'devops123',
    database: env('DB_DATABASE') ?? 'devops_learning',
    ssl,
  };
}
