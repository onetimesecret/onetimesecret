// src/schemas/config/runtime.ts

/**
 * Runtime Configuration Schema
 *
 * The runtime configuration combines static settings that define the application's
 * structure and capabilities with mutable settings that control behavior and rules.
 * Static settings take precedence in conflicts, creating a unified configuration
 * that serves as the single source of truth for both what the system can do and
 * how it should operate.
 */

import { z } from 'zod/v4';

import { configSchema as staticConfigSchema } from './static';
import { configSchema as mutableConfigSchema } from './mutable';

/**
 * configSchema - Defines the shape of the mutable configuration.
 *
 * **SPECIALE WAARSCHUWING**
 *
 * From the docs for `extend`:
 *    This API can be used to overwrite existing fields! Be careful with
 *    this power! If the two schemas share keys, B will override A.
 *
 * A = mutableConfigSchema
 * B = staticConfigSchema
 *
 * @see https://zod.dev/api?id=extend
 *
 */
const configSchema = z.object({
  ...mutableConfigSchema.shape,
  ...staticConfigSchema.shape,
});

export type Config = z.infer<typeof configSchema>;

export { configSchema };
