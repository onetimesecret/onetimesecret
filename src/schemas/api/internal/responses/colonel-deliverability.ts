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
export type ColonelEmailDeliverabilityEventsResponse = z.infer<
  typeof colonelEmailDeliverabilityEventsResponseSchema
>;
export type ColonelEmailDeliverabilityIngestResponse = z.infer<
  typeof colonelEmailDeliverabilityIngestResponseSchema
>;
