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
 * Schema for incoming recipient in admin view.
 *
 * Uses hash instead of email to prevent exposing recipient addresses.
 */
export const domainIncomingRecipientSchema = z.object({
  hash: z.string().min(1),
  name: z.string(),
});

export type DomainIncomingRecipient = z.infer<typeof domainIncomingRecipientSchema>;

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
 * - recipients: List of allowed recipients (hashed emails + display names)
 * - max_recipients: Maximum number of recipients allowed
 * - created_at: When this config was created (Unix epoch -> Date)
 * - updated_at: When this config was last modified (Unix epoch -> Date)
 *
 * @example
 * ```typescript
 * const config = customDomainIncomingConfigSchema.parse({
 *   domain_id: 'domain123',
 *   enabled: true,
 *   recipients: [{ hash: 'abc123', name: 'Alice' }],
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
  domain_id: z.string(),
  enabled: z.boolean(),
  recipients: z.array(domainIncomingRecipientSchema).default([]),
  max_recipients: z.number().int().positive(),
  created_at: transforms.fromNumber.toDate,
  updated_at: transforms.fromNumber.toDate,
});

export type CustomDomainIncomingConfig = z.infer<typeof customDomainIncomingConfigSchema>;

// ---------------------------------------------------------------------------
// Request payload schemas
// ---------------------------------------------------------------------------

/**
 * Request body for PUT of incoming configuration (frontend use).
 *
 * This schema represents the frontend's intended payload - only the `enabled`
 * toggle is sent via PUT. The backend API endpoint also accepts `recipients`,
 * but the frontend manages recipients through separate add/remove endpoints
 * (PUT /api/domains/:extid/recipients).
 *
 * This intentional separation allows toggling enabled/disabled state
 * without requiring the frontend to re-send the (hashed) recipients list.
 */
export const putIncomingConfigPayloadSchema = z.object({
  enabled: z.boolean(),
});

export type PutIncomingConfigPayload = z.infer<typeof putIncomingConfigPayloadSchema>;

/**
 * Request body for PATCH (partial update) of incoming configuration.
 *
 * PATCH semantics: only provided fields are updated.
 * All fields are optional for true partial update.
 */
export const patchIncomingConfigPayloadSchema = z.object({
  enabled: z.boolean().optional(),
});

export type PatchIncomingConfigPayload = z.infer<typeof patchIncomingConfigPayloadSchema>;
