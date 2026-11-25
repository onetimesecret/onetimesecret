// src/schemas/shapes/domains/incoming-config.ts
//
// CustomDomain::IncomingConfig shapes with runtime transforms.
// Admin-facing schema for managing incoming secrets configuration per domain.
//
// Architecture: shape -> API
// - This file: Shapes with transforms for API responses
// - api/domains/requests/incoming-config.ts: Request schemas
// - api/domains/responses/incoming-config.ts: Response schemas
//
// Note: This differs from src/schemas/api/incoming/responses/config.ts which
// is the public-facing config for secret senders. This schema is for domain
// administrators managing the incoming feature settings.

import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ---------------------------------------------------------------------------
// Recipient schema (matches public schema)
// ---------------------------------------------------------------------------

/**
 * Schema for an incoming recipient in the admin/owner view.
 *
 * The admin endpoint (`/api/domains/:extid/incoming-config`) returns and
 * accepts plaintext `{email, name}` because the authenticated owner is
 * managing their own configuration and the client needs to round-trip
 * the existing list on save without losing entries.
 *
 * The anonymous-sender shape (hashed digests) lives in
 * `src/schemas/api/incoming/responses/config.ts` — a different concern.
 */
export const domainIncomingRecipientSchema = z.object({
  email: z.string().email(),
  name: z.string(),
});

export type DomainIncomingRecipient = z.infer<typeof domainIncomingRecipientSchema>;

const incomingSettings = {
  passphrase_required: z.boolean().optional(),
  max_ttl: z.number().int().min(60).max(Number.MAX_SAFE_INTEGER).nullable().optional(),
  email_disabled: z.boolean().optional()
    .describe('Reserved setting. Incoming delivery continues by email.'),
};

// ---------------------------------------------------------------------------
// CustomDomain::IncomingConfig schema
// ---------------------------------------------------------------------------

/**
 * CustomDomain::IncomingConfig schema with transforms.
 *
 * Admin-facing schema for the incoming secrets feature configuration.
 * Used by domain owners to manage whether incoming secrets are enabled
 * and configure recipient limits.
 *
 * Fields:
 * - domain_id: The domain this config belongs to
 * - enabled: Whether incoming secrets are enabled for this domain
 * - recipients: List of recipients (plaintext email + display name; this
 *   is the admin/owner view — the anonymous-sender hashed shape lives in
 *   src/schemas/api/incoming/responses/config.ts)
 * - max_recipients: Maximum number of recipients allowed
 * - created_at: When this config was created (Unix epoch -> Date | null)
 * - updated_at: When this config was last modified (Unix epoch -> Date | null)
 *
 * @example
 * ```typescript
 * const config = customDomainIncomingConfigSchema.parse({
 *   domain_id: 'domain123',
 *   enabled: true,
 *   recipients: [{ email: 'alice@example.com', name: 'Alice' }],
 *   max_recipients: 20,
 *   created_at: 1609459200,
 *   updated_at: 1609545600,
 * });
 *
 * console.log(config.enabled); // true
 * console.log(config.created_at instanceof Date); // true
 * ```
 */
export const customDomainIncomingConfigSchema = z.object({
  ...incomingSettings,
  domain_id: z.string(),
  enabled: z.boolean(),
  recipients: z.array(domainIncomingRecipientSchema).default([]),
  max_recipients: z.number().int().positive(),
  // GetIncomingConfig returns null timestamps when no IncomingConfig record
  // exists yet for the domain (unconfigured state). After the first save the
  // backend populates real timestamps.
  created_at: transforms.fromNumber.toDateNullish,
  updated_at: transforms.fromNumber.toDateNullish,
});

export type CustomDomainIncomingConfig = z.infer<typeof customDomainIncomingConfigSchema>;

// ---------------------------------------------------------------------------
// Request payload schemas
// ---------------------------------------------------------------------------

/**
 * Request body for PUT of incoming configuration.
 *
 * A settings-only update preserves the enabled flag and recipients. Supplying
 * recipients replaces the entire list. Null clears the lifetime.
 */
export const putIncomingConfigPayloadSchema = z.object({
  ...incomingSettings,
  enabled: z.boolean().optional(),
  recipients: z.array(domainIncomingRecipientSchema).optional(),
});

export type PutIncomingConfigPayload = z.infer<typeof putIncomingConfigPayloadSchema>;
