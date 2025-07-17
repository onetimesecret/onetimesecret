/**
 * Configuration type definitions
 * Auto-generated from Zod schemas
 */

import { z } from 'zod/v4';
import { configSchema as mutableConfigSchema } from '@/schemas/config/mutable';
import { configSchema as staticConfigSchema } from '@/schemas/config/static';

export type MutableConfig = z.infer<typeof mutableConfigSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: MutableConfig;
};

export { mutableConfigSchema, staticConfigSchema };
