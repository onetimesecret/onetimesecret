// src/schemas/api/incoming.ts

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
 * Schema for incoming secret creation payload
 * Simple payload - passphrase and ttl come from backend config
 * Memo is optional - only secret and recipient are required
 * Recipient is now a hash string instead of email for security
 * Note: Memo max length validation is enforced by backend config and UI component
 */
export const incomingSecretPayloadSchema = z.object({
  memo: z.string().optional().default(''),
  secret: z.string().min(1),
  recipient: z.string().min(1), // Now expects hash instead of email
});

export type IncomingSecretPayload = z.infer<typeof incomingSecretPayloadSchema>;

/**
 * Schema for metadata object in the response
 */
const metadataRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  custid: z.string(),
  state: z.string(),
  secret_shortkey: z.string(),
  shortkey: z.string(),
  memo: z.string().optional(),
  recipients: z.string().optional(),
});

/**
 * Schema for secret object in the response
 */
const secretRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  state: z.string(),
  shortkey: z.string(),
});

/**
 * Schema for incoming secret creation response
 * Matches the actual V2 API response format
 */
export const incomingSecretResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
  shrimp: z.string().optional(),
  custid: z.string().optional(),
  record: z.object({
    metadata: metadataRecordSchema,
    secret: secretRecordSchema,
  }),
  details: z.object({
    memo: z.string(),
    recipient: z.string(),
  }).optional(),
});

export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
