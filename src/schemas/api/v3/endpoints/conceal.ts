// src/schemas/api/v3/endpoints/conceal.ts

import { metadataBaseSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';

/**
 * Schema for metadata returned by conceal endpoint
 * Uses base schema since URLs are not computed during creation
 */
export const concealMetadataSchema = metadataBaseSchema.extend({
  identifier: z.string(),
});

/**
 * Schema for combined secret and metadata (conceal data)
 * Uses conceal-specific metadata schema without URL fields
 */
export const concealDataSchema = z.object({
  metadata: concealMetadataSchema,
  secret: secretSchema,
  share_domain: z.string().nullable(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;
export type ConcealMetadata = z.infer<typeof concealMetadataSchema>;
