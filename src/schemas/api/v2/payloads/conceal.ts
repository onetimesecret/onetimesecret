// src/schemas/api/payloads/conceal.ts

// NOTE: We may want to import some details from the metadata and secret schemas
// since they are obviously highly correleated with the conceal payload. For now,
// we will keep this simple and just define the payload schema here and keep it
// compacetic via diligence and testing.
//import { metadataSchema, secretSchema } from '@/schemas/models';

import { z } from 'zod';

import { baseSecretPayloadSchema } from './base';

export const concealPayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('conceal'),
  secret: z.string().min(1),
});

export type ConcealPayload = z.infer<typeof concealPayloadSchema>;
