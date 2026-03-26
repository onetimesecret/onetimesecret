// src/schemas/api/v3/requests/content/conceal.ts

import { z } from 'zod';

import { baseSecretPayloadSchema } from './base';

export const concealPayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('conceal'),
  secret: z.string().min(1),
});

export type ConcealPayload = z.infer<typeof concealPayloadSchema>;
