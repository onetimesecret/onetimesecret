// src/schemas/api/v3/requests/content/generate.ts

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
