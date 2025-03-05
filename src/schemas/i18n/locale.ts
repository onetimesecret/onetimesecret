// src/schemas/i18n/locale.ts

import { z } from 'zod';

/**
 * Validates ISO language codes:
 * - 2-letter code (en)
 * - 4-letter codes with separator (en, pt_PT, DE-at)
 * Case insensitive. Must match entire string.
 */
export const localeSchema = z
  .string()
  .min(2)
  .max(5)
  .regex(/^([a-z]{2})([_\-]([a-z]{2}))?$/i, 'Invalid locale format');

export type Locale = z.infer<typeof localeSchema>;
