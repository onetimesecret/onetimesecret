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

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

/**
 * Authentication mode
 */
const authModeSchema = z.enum(['basic', 'advanced']);

/**
 * Session configuration (shared between basic and advanced modes)
 */
const sessionConfigSchema = z.object({
  secret: nullableString,
  expire_after: z.number().int().positive().default(86400), // 24 hours
  key: z.string().default('onetime.session'),
  secure: z.boolean().default(true),
  same_site: z.enum(['strict', 'lax', 'none']).default('strict'),
});

/**
 * Basic mode settings (Redis-only authentication)
 */
const basicModeSchema = z.object({
  password_hash_cost: z.number().int().positive().optional(),
  session_timeout: z.number().int().positive().optional(),
});

/**
 * Advanced mode settings (Rodauth-based application)
 */
const advancedModeSchema = z.object({
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
 */
const authConfigSchema = z.object({
  mode: authModeSchema.default('basic'),
  session: sessionConfigSchema.optional(),
  basic: basicModeSchema.optional(),
  advanced: advancedModeSchema.optional(),
});

export type AuthMode = z.infer<typeof authModeSchema>;
export type SessionConfig = z.infer<typeof sessionConfigSchema>;
export type BasicModeConfig = z.infer<typeof basicModeSchema>;
export type AdvancedModeConfig = z.infer<typeof advancedModeSchema>;
export type AuthConfig = z.infer<typeof authConfigSchema>;

export {
  authConfigSchema,
  authModeSchema,
  sessionConfigSchema,
  basicModeSchema,
  advancedModeSchema,
};

/**
 * Type guard: Check if auth config is valid
 *
 * @param data - Unknown data to validate
 * @returns True if data matches AuthConfig schema
 */
export function isAuthConfig(data: unknown): data is AuthConfig {
  return authConfigSchema.safeParse(data).success;
}
