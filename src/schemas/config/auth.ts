// src/schemas/config/auth.ts

/**
 * Authentication Configuration Schema
 *
 * Zod v4 schema for etc/defaults/auth.defaults.yaml
 *
 * Purpose:
 * - Type-safe validation of authentication configuration
 * - Runtime validation for YAML parsing
 * - TypeScript type inference for auth config usage
 */

import { z } from 'zod';
import { nullableString } from './shared/primitives';

/**
 * Authentication mode
 */
const authModeSchema = z.enum(['simple', 'full']);

// NOTE: Session configuration has been moved to src/schemas/config/section/site.ts
// Session handling is auth-mode agnostic (works with simple or full mode).
// See: sessionConfigSchema in site.ts

/**
 * Simple mode settings (Redis-only authentication)
 */
const simpleModeSchema = z.object({
  password_hash_cost: z.number().int().positive().optional(),
  session_timeout: z.number().int().positive().optional(),
});

/**
 * Full mode settings (Rodauth-based application)
 */
const fullModeSchema = z.object({
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

/**
 * Complete authentication configuration schema
 *
 * Matches the structure from etc/defaults/auth.defaults.yaml
 * NOTE: session has been moved to site config (site.session)
 */
const authConfigSchema = z.object({
  mode: authModeSchema.default('simple'),
  simple: simpleModeSchema.optional(),
  full: fullModeSchema.optional(),
});

export type AuthMode = z.infer<typeof authModeSchema>;
export type SimpleModeConfig = z.infer<typeof simpleModeSchema>;
export type FullModeConfig = z.infer<typeof fullModeSchema>;
export type AuthConfig = z.infer<typeof authConfigSchema>;

export { authConfigSchema, authModeSchema, simpleModeSchema, fullModeSchema };

/**
 * Type guard: Check if auth config is valid
 *
 * @param data - Unknown data to validate
 * @returns True if data matches AuthConfig schema
 */
export function isAuthConfig(data: unknown): data is AuthConfig {
  return authConfigSchema.safeParse(data).success;
}
