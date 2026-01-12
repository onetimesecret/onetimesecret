// src/schemas/api/v2/endpoints/conceal.ts

import { receiptSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';

/**
 * Schema for combined secret and receipt (conceal data)
 */
export const concealDataSchema = z.object({
  metadata: receiptSchema, // API response key remains 'metadata' for V2 compatibility
  secret: secretSchema,
  share_domain: z.string(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;
