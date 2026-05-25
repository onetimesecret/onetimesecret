// src/schemas/shapes/config/auth.ts

/**
 * Authentication Configuration Shape
 *
 * Adds runtime defaults and value constraints on top of the type-only auth
 * contract — auth-mode default, simple-mode positive bounds, and the
 * full-mode database URL fallback.
 *
 * @see src/schemas/contracts/config/auth.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

export {
  authConfigSchema,
  authModeSchema,
  simpleModeSchema,
  fullModeSchema,
  isAuthConfig,
} from '@/schemas/contracts/config/auth';

export type {
  AuthConfig,
  AuthMode,
  SimpleModeConfig,
  FullModeConfig,
} from '@/schemas/contracts/config/auth';

const authModeShape = z.enum(['simple', 'full']);

const simpleModeShape = z.object({
  password_hash_cost: z.number().int().positive().optional(),
  session_timeout: z.number().int().positive().optional(),
});

const fullModeShape = z.object({
  /**
   * Application database connection URL
   *
   * SQLite paths:
   *   - 'sqlite://:memory:' - In-memory, no persistence (dev/test only)
   *   - 'sqlite://data/auth.db' - Relative path
   *   - 'sqlite:///data/auth.db' - Absolute path
   */
  database_url: z.string().default('sqlite://data/auth.db'),

  /**
   * Migrations connection (PostgreSQL, MySQL, MS SQL Server only)
   *
   * Used at deployment time to run all Rodauth migrations
   */
  database_url_migrations: nullableString,

  /**
   * Service URL for internal requests
   */
  service_url: z.string().optional(),
});

const authConfigShape = z.object({
  mode: authModeShape.default('simple'),
  simple: simpleModeShape.optional(),
  full: fullModeShape.optional(),
});

export { authConfigShape, authModeShape, simpleModeShape, fullModeShape };
