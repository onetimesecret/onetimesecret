// src/schemas/api/incoming.ts

import { z } from 'zod';
import { baseSecretPayloadSchema } from './payloads/base';

/**
 * Schema for incoming recipient configuration
 */
export const incomingRecipientSchema = z.object({
  email: z.string().email(),
  name: z.string(),
});

export type IncomingRecipient = z.infer<typeof incomingRecipientSchema>;

/**
 * Schema for incoming secrets configuration response from API
 */
export const incomingConfigSchema = z.object({
  enabled: z.boolean(),
  memo_max_length: z.number().int().positive().default(50),
  recipients: z.array(incomingRecipientSchema).default([]),
  default_ttl: z.number().int().positive().optional(),
});

export type IncomingConfig = z.infer<typeof incomingConfigSchema>;

/**
 * Schema for incoming secret creation payload
 * Extends base secret payload with memo field
 */
export const incomingSecretPayloadSchema = baseSecretPayloadSchema.extend({
  kind: z.literal('incoming'),
  secret: z.string().min(1),
  memo: z.string().min(1).max(50), // Max will be validated against config
  recipient: z.string().email(),
});

export type IncomingSecretPayload = z.infer<typeof incomingSecretPayloadSchema>;

/**
 * Schema for incoming secret creation response
 */
export const incomingSecretResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  metadata_key: z.string().optional(),
  secret_key: z.string().optional(),
});

export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
