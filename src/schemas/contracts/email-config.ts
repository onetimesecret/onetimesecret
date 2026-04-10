// src/schemas/contracts/email-config.ts
//
// CustomDomain::EmailConfig contracts defining field names and wire format types.
// Shapes transform these to runtime types (e.g., timestamps -> Date).
//
// Architecture: contract -> shape -> API

/**
 * Per-Domain Email Configuration contracts.
 *
 * Stores email sending credentials for custom domains that manage their own
 * outbound email. This enables multi-tenant email where each domain can
 * configure their own SES, SendGrid, or Lettermint provider, or inherit
 * the system default.
 *
 * Design Decisions:
 *
 * 1. One-to-One with Domain: Each custom domain has at most one email
 *    config. The domain_id field is the identifier.
 *
 * 2. Provider Types: Supports 'ses', 'sendgrid', 'lettermint', and
 *    'inherit'. The 'inherit' type uses the system default email config.
 *
 * 3. Validation Status: Tracks whether the email config has been
 *    validated (DNS records verified, sender identity confirmed).
 *
 * 4. DNS Records: Provider-specific DNS records required for email
 *    authentication (SPF, DKIM, DMARC, etc.).
 *
 * @module contracts/email-config
 * @category Contracts
 * @see {@link "shapes/domains/email-config"} - Shapes with transforms
 */

import { z } from 'zod';

// ---------------------------------------------------------------------------
// Provider type schema
// ---------------------------------------------------------------------------

/**
 * Supported email provider types.
 *
 * - ses: Amazon Simple Email Service
 * - sendgrid: Twilio SendGrid
 * - lettermint: Lettermint transactional email
 * - inherit: Use system default email configuration
 *
 * @category Contracts
 */
export const emailProviderTypeSchema = z.enum(['ses', 'sendgrid', 'lettermint', 'inherit']);

export type EmailProviderType = z.infer<typeof emailProviderTypeSchema>;

// ---------------------------------------------------------------------------
// Validation status schema
// ---------------------------------------------------------------------------

/**
 * Email configuration validation status.
 *
 * - pending: Validation not yet attempted or in progress
 * - verified: DNS records and sender identity confirmed
 * - failed: Most recent validation attempt failed
 *
 * @category Contracts
 */
export const emailVerificationStatusSchema = z.enum(['pending', 'verified', 'failed']);

export type EmailVerificationStatus = z.infer<typeof emailVerificationStatusSchema>;

/** @deprecated Use emailVerificationStatusSchema — renamed to match backend field name */
export const emailValidationStatusSchema = emailVerificationStatusSchema;
/** @deprecated Use EmailVerificationStatus */
export type EmailValidationStatus = EmailVerificationStatus;

// ---------------------------------------------------------------------------
// DNS record schema
// ---------------------------------------------------------------------------

/**
 * DNS record status for email authentication verification.
 *
 * @category Contracts
 */
export const dnsRecordStatusSchema = z.enum(['pending', 'verified', 'failed']);

export type DnsRecordStatus = z.infer<typeof dnsRecordStatusSchema>;

/**
 * DNS record required for email authentication.
 *
 * Represents a single DNS record (SPF, DKIM, DMARC, etc.) that must be
 * configured for the domain's email provider.
 *
 * @category Contracts
 */
export const emailDnsRecordSchema = z.object({
  /** DNS record type (e.g., TXT, CNAME, MX). */
  type: z.string(),

  /** DNS record hostname. */
  name: z.string(),

  /** DNS record value. */
  value: z.string(),

  /** Verification status of this specific record. */
  status: dnsRecordStatusSchema,

  /** Whether the DNS record exists (from DnsRecordCheckWorker). Null if not yet checked. */
  dns_exists: z.boolean().nullable().optional(),

  /** Whether the DNS record value matches the provisioned value. Null if not yet checked. */
  value_matches: z.boolean().nullable().optional(),

  /** Whether the provider (e.g. Lettermint) has verified this specific record. Absent if no provider data yet. */
  provider_verified: z.boolean().nullable().optional(),
});

export type EmailDnsRecord = z.infer<typeof emailDnsRecordSchema>;

// ---------------------------------------------------------------------------
// Canonical schema
// ---------------------------------------------------------------------------

/**
 * Canonical CustomDomain::EmailConfig contract schema.
 *
 * Defines field names matching the Ruby CustomDomain::EmailConfig model
 * and wire format. Shapes transform timestamps (number -> Date) for runtime use.
 *
 * @see lib/onetime/models/custom_domain/email_config.rb - Backend model
 * @category Contracts
 */
export const customDomainEmailConfigCanonical = z.object({
  /** Domain ID (references CustomDomain.identifier). */
  domain_id: z.string(),

  /** Email provider type (ses, sendgrid, lettermint, inherit). */
  provider: emailProviderTypeSchema,

  /** Whether email config is enabled for sending. */
  enabled: z.boolean(),

  /** Sender email address (e.g., noreply@example.com). */
  from_address: z.string(),

  /** Sender display name (e.g., "Acme Corp"). */
  from_name: z.string(),

  /** Reply-to address. Null if not configured (falls back to from_address). */
  reply_to: z.string().nullable(),

  /** Current verification status of the email configuration. */
  verification_status: emailVerificationStatusSchema,

  /** DNS records required for email authentication. */
  dns_records: z.array(emailDnsRecordSchema),

  /** Timestamp of last successful validation. Null if never validated. */
  last_validated_at: z.number().nullable(),

  /** Timestamp when DNS record check completed. Null if not yet checked or re-validate in progress. */
  dns_check_completed_at: z.number().nullable(),

  /** Timestamp when provider verification check completed. Null if not yet checked or re-validate in progress. */
  provider_check_completed_at: z.number().nullable(),

  /** Last error message if verification failed (e.g., "Provider status: not_found"). */
  last_error: z.string().nullable().optional(),

  /** Provider-specific domain identifier (e.g., SES domain identity ARN). */
  provider_domain_id: z.string().nullable(),

  /** Configuration creation timestamp (Unix epoch seconds). */
  created_at: z.number(),

  /** Last update timestamp (Unix epoch seconds). */
  updated_at: z.number(),
});

// ---------------------------------------------------------------------------
// Type exports
// ---------------------------------------------------------------------------

/** TypeScript type for CustomDomain::EmailConfig wire format. */
export type CustomDomainEmailConfigCanonical = z.infer<typeof customDomainEmailConfigCanonical>;

// ---------------------------------------------------------------------------
// PATCH payload schema (partial update - all fields optional)
// ---------------------------------------------------------------------------

/**
 * PATCH email configuration request payload schema.
 *
 * All fields are optional for partial update semantics.
 * Only provided fields are updated; omitted fields preserve existing values.
 *
 * Custom mail sender model: users configure sender identity only.
 * Provider credentials are resolved from installation-level configuration.
 *
 * @category Contracts
 */
export const patchEmailConfigPayloadSchema = z.object({
  /** Whether email config is enabled. */
  enabled: z.boolean().optional(),

  /** Sender email address. */
  from_address: z.string().email('From address must be a valid email').optional(),

  /** Sender display name. */
  from_name: z.string().min(1, 'From name is required').max(100, 'From name is too long').optional(),

  /** Reply-to address. */
  reply_to: z.string().email('Reply-to must be a valid email').optional().or(z.literal('')),
});

export type PatchEmailConfigPayload = z.infer<typeof patchEmailConfigPayloadSchema>;

// ---------------------------------------------------------------------------
// PUT payload schema (full replacement - required fields enforced)
// ---------------------------------------------------------------------------

/**
 * PUT email configuration request payload schema.
 *
 * Full replacement semantics - all required fields must be provided.
 * The request body IS the new state.
 *
 * Custom mail sender model: users configure sender identity only.
 * Provider credentials are resolved from installation-level configuration.
 *
 * @category Contracts
 */
export const putEmailConfigPayloadSchema = z.object({
  /** Whether email config is enabled. Defaults to false. */
  enabled: z.boolean().optional(),

  /** Sender email address. */
  from_address: z.string().email('From address must be a valid email'),

  /** Sender display name. */
  from_name: z.string().min(1, 'From name is required').max(100, 'From name is too long'),

  /** Reply-to address. Optional - omit or empty string to use from_address. */
  reply_to: z.string().email('Reply-to must be a valid email').optional().or(z.literal('')),
});

export type PutEmailConfigPayload = z.infer<typeof putEmailConfigPayloadSchema>;
