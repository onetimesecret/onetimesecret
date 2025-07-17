// src/schemas/api/payloads/generate.ts

// NOTE: We may want to import some details from the metadata and secret schemas
// since they are obviously highly correleated with the conceal payload. For now,
// we will keep this simple and just define the payload schema here and keep it
// compacetic via diligence and testing.
//import { metadataSchema, secretSchema } from '@/schemas/models';

import { z } from 'zod/v4';

import { baseSecretPayloadSchema } from './base';

export const generatePayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('generate'),
});

export type GeneratePayload = z.infer<typeof generatePayloadSchema>;
