// src/schemas/api/incoming/responses/config.ts

import { z } from 'zod';

/**
 * Schema for incoming recipient configuration
 * Note: Uses hash instead of email to prevent exposing recipient addresses
 */
export const incomingRecipientSchema = z.object({
  hash: z.string().min(1),
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
 * Schema for API response wrapper for config
 */
export const incomingConfigResponseSchema = z.object({
  config: incomingConfigSchema,
});

export type IncomingConfigResponse = z.infer<typeof incomingConfigResponseSchema>;
