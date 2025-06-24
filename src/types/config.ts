/**
 * Configuration type definitions
 * Auto-generated from Zod schemas
 */

import { z } from 'zod/v4';
import { mutableSettingsSchema, staticConfigSchema } from '@/schemas/config/settings';

export type MutableSettings = z.infer<typeof mutableSettingsSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: MutableSettings;
};

export { mutableSettingsSchema, staticConfigSchema };
