// src/schemas/api/incoming/requests/incoming-secret.ts

import { z } from 'zod';

/**
 * Schema for incoming secret creation payload
 * The server chooses the lifetime and may require a sender-supplied passphrase.
 * Memo is optional - only secret and recipient are required
 * Recipient is now a hash string instead of email for security
 * Note: Memo max length validation is enforced by backend config and UI component
 */
export const incomingSecretPayloadSchema = z.object({
  memo: z.string().optional().default(''),
  secret: z.string().min(1),
  passphrase: z.string().optional(),
  recipient: z.string().min(1), // Now expects hash instead of email
});

export type IncomingSecretPayload = z.infer<typeof incomingSecretPayloadSchema>;

/** HTTP transport wrapper; the content schema above remains the frontend form type. */
export const incomingSecretRequestSchema = z.object({
  secret: incomingSecretPayloadSchema,
});

export type IncomingSecretRequest = z.infer<typeof incomingSecretRequestSchema>;
