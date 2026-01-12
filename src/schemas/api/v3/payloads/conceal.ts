// src/schemas/api/v3/payloads/conceal.ts

// NOTE: We may want to import some details from the receipt and secret schemas
// since they are obviously highly correlated with the conceal payload. For now,
// we will keep this simple and just define the payload schema here and keep it
// copacetic via diligence and testing.
//import { receiptSchema, secretSchema } from '@/schemas/models';

import { z } from 'zod';

import { baseSecretPayloadSchema } from './base';

export const concealPayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('conceal'),
  secret: z.string().min(1),
});

export type ConcealPayload = z.infer<typeof concealPayloadSchema>;
