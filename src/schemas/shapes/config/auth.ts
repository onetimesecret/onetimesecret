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

import {
  authConfigSchema,
  authModeSchema,
  simpleModeSchema,
  fullModeSchema,
  isAuthConfig,
} from '@/schemas/contracts/config/auth';
import { augment, type AugmentTree } from '@/schemas/utils/augment';

export {
  authConfigSchema,
  authModeSchema,
  simpleModeSchema,
  fullModeSchema,
  isAuthConfig,
};

export type {
  AuthConfig,
  AuthMode,
  SimpleModeConfig,
  FullModeConfig,
} from '@/schemas/contracts/config/auth';

const authModeShape = authModeSchema;

const simpleModeTree: AugmentTree = {
  password_hash_cost: (n) => n.int().positive().optional(),
  session_timeout: (n) => n.int().positive().optional(),
};

const fullModeTree: AugmentTree = {
  /**
   * Application database connection URL
   *
   * SQLite paths:
   *   - 'sqlite://:memory:' - In-memory, no persistence (dev/test only)
   *   - 'sqlite://data/auth.db' - Relative path
   *   - 'sqlite:///data/auth.db' - Absolute path
   */
  database_url: (s) => s.default('sqlite://data/auth.db'),
};

const simpleModeShape = augment(simpleModeSchema, simpleModeTree);
const fullModeShape = augment(fullModeSchema, fullModeTree);

const authConfigShape = augment(authConfigSchema, {
  mode: (e) => e.default('simple'),
  simple: simpleModeTree,
  full: fullModeTree,
});

export { authConfigShape, authModeShape, simpleModeShape, fullModeShape };
