/**
 * TypeORM DataSource — used by the TypeORM CLI for migrations.
 *
 * Run via npm scripts:
 *   npm run migration:generate -- src/migrations/MyMigrationName
 *   npm run migration:run
 *   npm run migration:revert
 *   npm run migration:show
 */
import 'reflect-metadata';
import { DataSource } from 'typeorm';
import * as path from 'path';
import { buildPostgresCredentials } from './database.config';

// Load .env files relative to the project root
// eslint-disable-next-line @typescript-eslint/no-var-requires
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env.local') });
// eslint-disable-next-line @typescript-eslint/no-var-requires
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

export const AppDataSource = new DataSource({
  type: 'postgres',
  ...buildPostgresCredentials((key) => process.env[key]),

  // All entity files (ts source and compiled js)
  entities: [path.join(__dirname, '**', '*.entity.{ts,js}')],

  // Migration files live in the shared top-level migration/ folder
  migrations: [path.join(__dirname, '..', '..', 'migration', '*.{ts,js}')],
  migrationsTableName: 'typeorm_migrations',

  // Never auto-sync when using migrations
  synchronize: false,
  logging: ['migration', 'error'],
});
