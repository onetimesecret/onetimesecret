// src/schemas/api/endpoints/conceal.ts
import { metadataSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';

/**
 * Schema for combined secret and metadata (conceal data)
 */
export const concealDataSchema = z.object({
  metadata: metadataSchema,
  secret: secretSchema,
  share_domain: z.string(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;
