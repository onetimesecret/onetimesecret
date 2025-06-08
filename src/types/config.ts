/**
 * Configuration type definitions
 * Auto-generated from Zod schemas
 */

import { z } from 'zod/v4';
import { systemSettingsSchema, staticConfigSchema } from '@/schemas/config/settings';

export type SystemSettings = z.infer<typeof systemSettingsSchema>;
export type StaticConfig = z.infer<typeof staticConfigSchema>;

export type ApplicationConfig = {
  static?: StaticConfig;
  dynamic?: SystemSettings;
};

export { systemSettingsSchema, staticConfigSchema };
