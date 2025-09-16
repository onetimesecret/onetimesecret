// src/schemas/api/payloads/generate.ts

// NOTE: We may want to import some details from the metadata and secret schemas
// since they are obviously highly correleated with the conceal payload. For now,
// we will keep this simple and just define the payload schema here and keep it
// compacetic via diligence and testing.
//import { metadataSchema, secretSchema } from '@/schemas/models';

import { z } from 'zod';

import { baseSecretPayloadSchema } from './base';

export const generatePayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('generate'),

  // Optional password generation settings
  length: z.number().int().min(4).max(128).optional(),
  character_sets: z.object({
    uppercase: z.boolean().optional(),
    lowercase: z.boolean().optional(),
    numbers: z.boolean().optional(),
    symbols: z.boolean().optional(),
    exclude_ambiguous: z.boolean().optional(),
  }).optional(),
});

export type GeneratePayload = z.infer<typeof generatePayloadSchema>;
