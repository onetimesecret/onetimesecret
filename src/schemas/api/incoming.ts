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
 * Schema for API response wrapper for config
 */
export const incomingConfigResponseSchema = z.object({
  config: incomingConfigSchema,
});

export type IncomingConfigResponse = z.infer<typeof incomingConfigResponseSchema>;

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
 * Schema for receipt record in the response
 * Note: Many fields can be null from the API, use .nullish() to accept both null and undefined
 */
const receiptRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  custid: z.string().nullish(),
  owner_id: z.string().nullish(),
  state: z.string().nullish(),
  secret_shortid: z.string().nullish(),
  shortid: z.string().nullish(),
  memo: z.string().nullish(),
  recipients: z.string().nullish(),
  // Additional fields from actual API response
  secret_ttl: z.number().nullish(),
  receipt_ttl: z.number().nullish(),
  lifespan: z.number().nullish(),
  share_domain: z.string().nullish(),
  created: z.number().nullish(),
  updated: z.number().nullish(),
  shared: z.number().nullish(),
  received: z.number().nullish(),
  burned: z.number().nullish(),
  viewed: z.number().nullish(),
  show_recipients: z.boolean().nullish(),
  is_viewed: z.boolean().nullish(),
  is_received: z.boolean().nullish(),
  is_burned: z.boolean().nullish(),
  is_expired: z.boolean().nullish(),
  is_orphaned: z.boolean().nullish(),
  is_destroyed: z.boolean().nullish(),
  has_passphrase: z.boolean().nullish(),
});

/**
 * Schema for secret object in the response
 */
const secretRecordSchema = z.object({
  identifier: z.string(),
  key: z.string(),
  state: z.string().nullish(),
  shortid: z.string().nullish(),
  // Additional fields from actual API response
  secret_ttl: z.number().nullish(),
  lifespan: z.number().nullish(),
  has_passphrase: z.boolean().nullish(),
  verification: z.boolean().nullish(),
  created: z.number().nullish(),
  updated: z.number().nullish(),
});

/**
 * Schema for incoming secret creation response
 * Matches the actual V3 API response format
 *
 * Note: V3 API uses modern "receipt" terminology exclusively.
 */
export const incomingSecretResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().nullish(),
  shrimp: z.string().nullish(),
  custid: z.string().nullish(),
  record: z.object({
    receipt: receiptRecordSchema,
    secret: secretRecordSchema,
  }),
  details: z
    .object({
      memo: z.string().nullish(),
      recipient: z.string().nullish(),
    })
    .nullish(),
});

export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;

/**
 * Schema for recipient validation request
 */
export const validateRecipientPayloadSchema = z.object({
  recipient: z.string().min(1),
});

export type ValidateRecipientPayload = z.infer<typeof validateRecipientPayloadSchema>;

/**
 * Schema for recipient validation response
 */
export const validateRecipientResponseSchema = z.object({
  recipient: z.string(),
  valid: z.boolean(),
});

export type ValidateRecipientResponse = z.infer<typeof validateRecipientResponseSchema>;
