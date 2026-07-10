// src/schemas/api/internal/responses/colonel-deliverability.ts
//
// Per-resource colonel/admin schemas for the email Deliverability section
// (bounces / complaints / suppression list) on the Email Tools screen.
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). This is the receiving side of email:
// the mailer's emails_sent counter proves mail went OUT; these endpoints show
// what came BACK (the data that diagnoses a sender-reputation problem):
//
//   - GetEmailDeliverability          → GET    /api/colonel/email/deliverability
//   - ListEmailSuppressions           → GET    …/deliverability/suppressions
//   - RemoveEmailSuppression          → DELETE …/deliverability/suppressions/:address
//   - ListEmailDeliverabilityEvents   → GET    …/deliverability/events
//   - IngestEmailDeliverabilityEvents → POST   …/deliverability/events
//
// Shapes verified against the live colonel logic classes
// (apps/api/colonel/logic/colonel/{get_email_deliverability,
// list_email_suppressions,remove_email_suppression,
// list_email_deliverability_events,ingest_email_deliverability_events}.rb),
// thin adapters over Onetime::EmailSuppression and
// Onetime::Operations::Email::{IngestFeedback,RemoveSuppression}.

import { createApiResponseSchema } from '@/schemas/api/base';
import { paginationSchema } from './colonel';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ============================================================================
// Summary — GET /api/colonel/email/deliverability
// ============================================================================

/**
 * GetEmailDeliverability `details`: the reputation-diagnosis counters.
 * `recent_*` are counted inside the trailing `window_days`; `sends_skipped`
 * is the lifetime tally of sends the suppression guard blocked.
 */
export const colonelDeliverabilitySummaryDetailsSchema = z.object({
  window_days: z.number(),
  counts: z.object({
    suppressed_total: z.number(),
    recent_bounces: z.number(),
    recent_complaints: z.number(),
    sends_skipped: z.number(),
  }),
  /**
   * ITEM 2 — per-provider last-sync status. Backend ALWAYS emits this key,
   * emitting an empty object `{}` when nothing has ever synced; `.optional()`
   * only guards legacy payloads. Empty object OR undefined => never synced
   * (the frontend warns). `last_synced_at` arrives as Unix-seconds → Date.
   */
  sync_status: z
    .record(
      z.string(),
      z.object({
        last_synced_at: transforms.fromNumber.toDate,
        imported: z.number(),
        result: z.string(),
      })
    )
    .optional(),
});

// ============================================================================
// Suppression list — GET /api/colonel/email/deliverability/suppressions
// ============================================================================

/**
 * One suppression entry. `reason` is bounce | complaint | manual; `source` is
 * free-form provenance (e.g. 'ses', 'smtp-sync', 'cli'). `created` arrives as
 * a Unix-second float and is transformed to Date.
 */
export const colonelEmailSuppressionSchema = z.object({
  address: z.string(),
  reason: z.string(),
  source: z.string(),
  created: transforms.fromNumber.toDate,
});

/** ListEmailSuppressions `details`: rows + pagination-with-search-echo. */
export const colonelEmailSuppressionsDetailsSchema = z.object({
  suppressions: z.array(colonelEmailSuppressionSchema),
  pagination: paginationSchema,
});

// ============================================================================
// Suppression removal — DELETE /api/colonel/email/deliverability/suppressions/:address
// ============================================================================

/** RemoveEmailSuppression `record`: the removal outcome. */
export const colonelEmailSuppressionRemoveRecordSchema = z.object({
  address: z.string(),
  removed: z.boolean(),
});

/** RemoveEmailSuppression `details`: an ack message. */
export const colonelEmailSuppressionRemoveDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Suppression add (manual) — POST /api/colonel/email/deliverability/suppressions
// ============================================================================

/**
 * AddEmailSuppression `record`: the add outcome (ITEM 6). `created` is true on a
 * new entry, false when the address was already suppressed (upsert). The request
 * carries ONLY `address` — `reason`/`source` are hardcoded server-side.
 */
export const colonelEmailSuppressionAddRecordSchema = z.object({
  address: z.string(),
  created: z.boolean(),
});

/** AddEmailSuppression `details`: an ack message. */
export const colonelEmailSuppressionAddDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Event feed — GET /api/colonel/email/deliverability/events
// ============================================================================

/**
 * One bounce/complaint event. `kind` is bounce | complaint; `reason` is the
 * provider diagnostic (e.g. the SMTP 5xx line) or null.
 */
export const colonelDeliverabilityEventSchema = z.object({
  id: z.string(),
  address: z.string(),
  kind: z.string(),
  reason: z.string().nullable(),
  source: z.string(),
  created: transforms.fromNumber.toDate,
});

/** ListEmailDeliverabilityEvents `details`: rows + pagination. */
export const colonelDeliverabilityEventsDetailsSchema = z.object({
  events: z.array(colonelDeliverabilityEventSchema),
  pagination: paginationSchema,
});

// ============================================================================
// Feedback ingest — POST /api/colonel/email/deliverability/events
// ============================================================================

/** IngestEmailDeliverabilityEvents `record`: per-batch acceptance counts. */
export const colonelDeliverabilityIngestRecordSchema = z.object({
  accepted: z.number(),
  rejected: z.number(),
});

/** IngestEmailDeliverabilityEvents `details`: first rejection reasons. */
export const colonelDeliverabilityIngestDetailsSchema = z.object({
  errors: z.array(z.string()),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelDeliverabilitySummaryDetails = z.infer<
  typeof colonelDeliverabilitySummaryDetailsSchema
>;
export type ColonelEmailSuppression = z.infer<typeof colonelEmailSuppressionSchema>;
export type ColonelDeliverabilityEvent = z.infer<typeof colonelDeliverabilityEventSchema>;

// ============================================================================
// Track B — live provider reads (item 9 send-log / item 10 recipient lookup /
// provider status). These three read the ACTIVE system transport only
// (Mailer.determine_provider), never a cross-provider matrix and never a stored
// record. Each payload carries TWO orthogonal booleans that must not collapse:
//   - `capability` — structural: does this provider's API offer the feature at
//     all? (SES send-log → false permanently, independent of the network.)
//   - `available`  — runtime: did the live call succeed? false + `error` note on
//     timeout / auth failure / any provider exception.
// Contract: docs/specs/colonel-ui + Track-B implementation contract §0-§3.
// ============================================================================

/**
 * A. GET /api/colonel/email/deliverability/provider-status → GetEmailProviderStatus
 *
 * SES-specific reputation block. `enforcement_status` is HEALTHY|PROBATION|
 * SHUTDOWN (tier drives the badge colour). Numeric bounce/complaint rates are
 * ALWAYS null on SESv2 (no numeric rate API) with `rate_note` explaining why —
 * a data-present-but-partial "degraded" state, NOT `available=false`.
 */
export const colonelEmailProviderStatusSesSchema = z.object({
  enforcement_status: z.string(),
  production_access_enabled: z.boolean(),
  sending_enabled: z.boolean(),
  max_24_hour_send: z.number(),
  sent_last_24_hours: z.number(),
  max_send_rate: z.number(),
  rate_bounce: z.number().nullable(),
  rate_complaint: z.number().nullable(),
  rate_note: z.string().nullable(),
});

/**
 * Lettermint-specific stats block over a fixed 30-day window. Rates are
 * computed server-side (`hard_bounced / sent`, guarded for sent==0 → null).
 */
export const colonelEmailProviderStatusLettermintSchema = z.object({
  window_days: z.number(),
  sent: z.number(),
  delivered: z.number(),
  hard_bounced: z.number(),
  // Nullable: Lettermint's /stats does not report complaints (confirmed against
  // the gem's stats_spec). null renders as "not reported", never a fake 0.
  spam_complaints: z.number().nullable(),
  opened: z.number(),
  clicked: z.number(),
  rate_bounce: z.number().nullable(),
  rate_complaint: z.number().nullable(),
  rate_note: z.string().nullable(),
});

/**
 * GetEmailProviderStatus `details`. Both provider blocks are ALWAYS present as
 * independently-nullable keys (NOT a discriminated union — the wire always
 * carries both `ses` and `lettermint`, one of them `null`). Non-live transports
 * (smtp/logger/…) return `capability=false` and both blocks null.
 */
export const colonelEmailProviderStatusDetailsSchema = z.object({
  provider: z.string(),
  capability: z.boolean(),
  available: z.boolean(),
  error: z.string().nullable(),
  ses: colonelEmailProviderStatusSesSchema.nullable(),
  lettermint: colonelEmailProviderStatusLettermintSchema.nullable(),
});

/**
 * B. GET /api/colonel/email/deliverability/lookup?address= → LookupEmailRecipient
 *
 * `local` (from EmailSuppression.lookup, keyed by the SAME normalized address)
 * is ALWAYS present — the local store is always readable. `provider_result` is
 * the live provider read, null when capability=false or available=false. A
 * not-found on the provider is NOT an error: it is `suppressed=false`,
 * available=true.
 */
export const colonelEmailRecipientLocalSchema = z.object({
  suppressed: z.boolean(),
  reason: z.string().nullable(),
  source: z.string().nullable(),
  // Unix seconds → Date; null when not suppressed. nullable() short-circuits
  // before the transform, so a null wire value stays null.
  created: transforms.fromNumber.toDate.nullable(),
});

export const colonelEmailRecipientProviderResultSchema = z.object({
  suppressed: z.boolean(),
  reason: z.string().nullable(),
  last_update_time: transforms.fromNumber.toDate.nullable(),
});

export const colonelEmailRecipientLookupDetailsSchema = z.object({
  address: z.string(),
  provider: z.string(),
  capability: z.boolean(),
  available: z.boolean(),
  error: z.string().nullable(),
  local: colonelEmailRecipientLocalSchema,
  provider_result: colonelEmailRecipientProviderResultSchema.nullable(),
});

/**
 * C. GET /api/colonel/email/deliverability/messages → ListEmailMessages
 *
 * The item-9 send log, sourced from the provider's OWN message API
 * (Lettermint /messages). SES has no per-message API → `capability=false`, empty
 * messages. Live-read PII (recipient addresses + subjects) is EXEMPT from the
 * at-rest address-hashing posture: colonel-only, never persisted.
 */
export const colonelEmailMessageSchema = z.object({
  id: z.string(),
  status: z.string(),
  subject: z.string(),
  to: z.array(z.string()),
  from_email: z.string(),
  // Nullable to match the backend contract: message_record emits
  // parse_time(created_at), which returns nil on a missing/unparseable row
  // timestamp (lettermint.rb parse_time). A non-nullable field would reject
  // the WHOLE send-log payload on a single such row, degrading the feed to a
  // permanent retry alert. Render a dash for null.
  created_at: transforms.fromNumber.toDate.nullable(),
});

/**
 * Cursor pagination for the send log. NEW schema (do NOT reuse
 * `paginationSchema`): Lettermint is cursor-paginated, so `total_count` /
 * `total_pages` may be null and the frontend uses `cursor` for "next", not a
 * page count.
 */
export const cursorPaginationSchema = z.object({
  page: z.number(),
  per_page: z.number(),
  total_count: z.number().nullable(),
  total_pages: z.number().nullable(),
  cursor: z.string().nullable(),
});

export const colonelEmailMessagesDetailsSchema = z.object({
  provider: z.string(),
  capability: z.boolean(),
  available: z.boolean(),
  error: z.string().nullable(),
  messages: z.array(colonelEmailMessageSchema),
  pagination: cursorPaginationSchema,
});

// GET /api/colonel/email/deliverability/provider-status → GetEmailProviderStatus
export const colonelEmailProviderStatusResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelEmailProviderStatusDetailsSchema
);

// GET /api/colonel/email/deliverability/lookup → LookupEmailRecipient
export const colonelEmailRecipientLookupResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelEmailRecipientLookupDetailsSchema
);

// GET /api/colonel/email/deliverability/messages → ListEmailMessages
export const colonelEmailMessagesResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelEmailMessagesDetailsSchema
);

export type ColonelEmailProviderStatusDetails = z.infer<
  typeof colonelEmailProviderStatusDetailsSchema
>;
export type ColonelEmailRecipientLookupDetails = z.infer<
  typeof colonelEmailRecipientLookupDetailsSchema
>;
export type ColonelEmailMessage = z.infer<typeof colonelEmailMessageSchema>;
export type ColonelEmailProviderStatusResponse = z.infer<
  typeof colonelEmailProviderStatusResponseSchema
>;
export type ColonelEmailRecipientLookupResponse = z.infer<
  typeof colonelEmailRecipientLookupResponseSchema
>;
export type ColonelEmailMessagesResponse = z.infer<
  typeof colonelEmailMessagesResponseSchema
>;

// Wrapped response schemas for the email Deliverability section (bounces /
// complaints / suppression list) on the colonel Email Tools screen.
// Internal-only; never exposed publicly.
//
// The section component imports these DIRECTLY (CONTRACT 3) so it typechecks
// independently of the registry; the registry keys link them to the logic
// classes for OpenAPI generation.

// GET /api/colonel/email/deliverability → GetEmailDeliverability
export const colonelEmailDeliverabilityResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelDeliverabilitySummaryDetailsSchema
);

// GET /api/colonel/email/deliverability/suppressions → ListEmailSuppressions
export const colonelEmailSuppressionsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelEmailSuppressionsDetailsSchema
);

// DELETE /api/colonel/email/deliverability/suppressions/:address → RemoveEmailSuppression
export const colonelEmailSuppressionRemoveResponseSchema = createApiResponseSchema(
  colonelEmailSuppressionRemoveRecordSchema,
  colonelEmailSuppressionRemoveDetailsSchema
);

// POST /api/colonel/email/deliverability/suppressions → AddEmailSuppression (ITEM 6)
export const colonelEmailSuppressionAddResponseSchema = createApiResponseSchema(
  colonelEmailSuppressionAddRecordSchema,
  colonelEmailSuppressionAddDetailsSchema
);

// GET /api/colonel/email/deliverability/events → ListEmailDeliverabilityEvents
export const colonelEmailDeliverabilityEventsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelDeliverabilityEventsDetailsSchema
);

// POST /api/colonel/email/deliverability/events → IngestEmailDeliverabilityEvents
export const colonelEmailDeliverabilityIngestResponseSchema = createApiResponseSchema(
  colonelDeliverabilityIngestRecordSchema,
  colonelDeliverabilityIngestDetailsSchema
);

export type ColonelEmailDeliverabilityResponse = z.infer<
  typeof colonelEmailDeliverabilityResponseSchema
>;
export type ColonelEmailSuppressionsResponse = z.infer<
  typeof colonelEmailSuppressionsResponseSchema
>;
export type ColonelEmailSuppressionRemoveResponse = z.infer<
  typeof colonelEmailSuppressionRemoveResponseSchema
>;
export type ColonelEmailSuppressionAddResponse = z.infer<
  typeof colonelEmailSuppressionAddResponseSchema
>;
export type ColonelEmailDeliverabilityEventsResponse = z.infer<
  typeof colonelEmailDeliverabilityEventsResponseSchema
>;
export type ColonelEmailDeliverabilityIngestResponse = z.infer<
  typeof colonelEmailDeliverabilityIngestResponseSchema
>;
