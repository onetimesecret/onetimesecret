// src/schemas/api/internal/responses/colonel-emailtools.ts
//
// Per-resource colonel/admin schemas for the Email Tools screen (ticket #44)
// and the rate-limit endpoints.
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are UNTOUCHED
// (the Zod tripwire, epic non-goal). These surface CLI-only powers
// (`bin/ots email {templates,preview,test}` and `bin/ots ratelimit keys`) that
// never had a colonel endpoint, so there is nothing to reuse. Distinct
// `emailtools` namespace so this screen never collides with another's contract
// (CONTRACT 2 / 3).
//
// The rate-limit inspect/reset UI was removed by design review (YAGNI — the
// CLI is the operator surface), but the three ratelimit endpoints remain live,
// so their shapes stay as registry/OpenAPI contract documentation.
//
// Shapes verified against the live colonel logic classes
// (apps/api/colonel/logic/colonel/{list_email_templates,preview_email_template,
// send_test_email,list_rate_limiters,inspect_rate_limit,reset_rate_limit}.rb),
// thin adapters over Onetime::Operations::Email::* and
// Onetime::Operations::RateLimit::*.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// ============================================================================
// Email templates — GET /api/colonel/email/templates
// ============================================================================

/** One template summary row (name + rendered formats). */
export const colonelEmailTemplateSchema = z.object({
  name: z.string(),
  class_name: z.string(),
  formats: z.array(z.string()),
});

/** ListEmailTemplates `record`: the picker's template list. */
export const colonelEmailTemplatesRecordSchema = z.object({
  templates: z.array(colonelEmailTemplateSchema),
});

/** ListEmailTemplates `details`: informational count. */
export const colonelEmailTemplatesDetailsSchema = z.object({
  count: z.number(),
});

// ============================================================================
// Template preview — GET /api/colonel/email/templates/:template/preview
// ============================================================================

/** PreviewEmailTemplate `record`: what was rendered. */
export const colonelEmailPreviewRecordSchema = z.object({
  template: z.string(),
  locale: z.string(),
  format: z.string(),
});

/** PreviewEmailTemplate `details`: the rendered body (text or HTML source). */
export const colonelEmailPreviewDetailsSchema = z.object({
  body: z.string(),
});

// ============================================================================
// Test send — POST /api/colonel/email/test
// ============================================================================

/** SendTestEmail `record`: the send outcome. `status` is dry_run / sent / enqueued. */
export const colonelEmailTestRecordSchema = z.object({
  to: z.string(),
  status: z.string(),
  sent: z.boolean(),
});

/** SendTestEmail `details`: the exact diagnostic email that was (or would be) sent. */
export const colonelEmailTestDetailsSchema = z.object({
  provider: z.string(),
  host: z.string(),
  from: z.string(),
  subject: z.string(),
  text_body: z.string(),
  timestamp: z.string(),
});

// ============================================================================
// Rate limiters — GET /api/colonel/ratelimit/limiters
// ============================================================================

/** One known limiter (kind + human subject description). */
export const colonelRateLimiterSchema = z.object({
  kind: z.string(),
  subject: z.string(),
});

/** ListRateLimiters `record`: the inspect panel's limiter picker. */
export const colonelRateLimitersRecordSchema = z.object({
  limiters: z.array(colonelRateLimiterSchema),
});

/** ListRateLimiters `details`: informational count. */
export const colonelRateLimitersDetailsSchema = z.object({
  count: z.number(),
});

// ============================================================================
// Rate-limit inspect — GET /api/colonel/ratelimit/inspect
// ============================================================================

/**
 * State of one backing Redis key. `ttl` is seconds-remaining or null (no expiry
 * / absent — the server collapses Redis's -1/-2 sentinels). `value` is the raw
 * stored string or null when the key is unset.
 */
export const colonelRateLimitEntrySchema = z.object({
  key: z.string(),
  ttl: z.number().nullable(),
  value: z.string().nullable(),
  exists: z.boolean(),
});

/** InspectRateLimit `record`: the inspected limiter + subject. */
export const colonelRateLimitInspectRecordSchema = z.object({
  kind: z.string(),
  subject: z.string(),
});

/** InspectRateLimit `details`: per-key state. */
export const colonelRateLimitInspectDetailsSchema = z.object({
  entries: z.array(colonelRateLimitEntrySchema),
});

// ============================================================================
// Rate-limit reset — POST /api/colonel/ratelimit/reset
// ============================================================================

/** ResetRateLimit `record`: the reset outcome. */
export const colonelRateLimitResetRecordSchema = z.object({
  kind: z.string(),
  subject: z.string(),
  cleared: z.boolean(),
});

/** ResetRateLimit `details`: how many keys were removed + an ack message. */
export const colonelRateLimitResetDetailsSchema = z.object({
  deleted: z.number(),
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelEmailTemplate = z.infer<typeof colonelEmailTemplateSchema>;
export type ColonelEmailPreviewDetails = z.infer<typeof colonelEmailPreviewDetailsSchema>;
export type ColonelEmailTestRecord = z.infer<typeof colonelEmailTestRecordSchema>;
export type ColonelEmailTestDetails = z.infer<typeof colonelEmailTestDetailsSchema>;
export type ColonelRateLimiter = z.infer<typeof colonelRateLimiterSchema>;
export type ColonelRateLimitEntry = z.infer<typeof colonelRateLimitEntrySchema>;
export type ColonelRateLimitResetDetails = z.infer<typeof colonelRateLimitResetDetailsSchema>;

// Wrapped response schemas for the colonel Email Tools screen (ticket #44) and
// the rate-limit endpoints. Internal-only; never exposed publicly.
//
// The view imports the email envelopes DIRECTLY (CONTRACT 3) so it typechecks
// independently of the registry. The three ratelimit envelopes are
// registry-only: the inspect/reset UI was removed by design review, but the
// endpoints remain live and these document their contracts.

// GET /api/colonel/email/templates → ListEmailTemplates
export const colonelEmailTemplatesResponseSchema = createApiResponseSchema(
  colonelEmailTemplatesRecordSchema,
  colonelEmailTemplatesDetailsSchema
);

// GET /api/colonel/email/templates/:template/preview → PreviewEmailTemplate
export const colonelEmailPreviewResponseSchema = createApiResponseSchema(
  colonelEmailPreviewRecordSchema,
  colonelEmailPreviewDetailsSchema
);

// POST /api/colonel/email/test → SendTestEmail
export const colonelEmailTestResponseSchema = createApiResponseSchema(
  colonelEmailTestRecordSchema,
  colonelEmailTestDetailsSchema
);

// GET /api/colonel/ratelimit/limiters → ListRateLimiters
export const colonelRateLimitersResponseSchema = createApiResponseSchema(
  colonelRateLimitersRecordSchema,
  colonelRateLimitersDetailsSchema
);

// GET /api/colonel/ratelimit/inspect → InspectRateLimit
export const colonelRateLimitInspectResponseSchema = createApiResponseSchema(
  colonelRateLimitInspectRecordSchema,
  colonelRateLimitInspectDetailsSchema
);

// POST /api/colonel/ratelimit/reset → ResetRateLimit
export const colonelRateLimitResetResponseSchema = createApiResponseSchema(
  colonelRateLimitResetRecordSchema,
  colonelRateLimitResetDetailsSchema
);

export type ColonelEmailTemplatesResponse = z.infer<typeof colonelEmailTemplatesResponseSchema>;
export type ColonelEmailPreviewResponse = z.infer<typeof colonelEmailPreviewResponseSchema>;
export type ColonelEmailTestResponse = z.infer<typeof colonelEmailTestResponseSchema>;
export type ColonelRateLimitersResponse = z.infer<typeof colonelRateLimitersResponseSchema>;
export type ColonelRateLimitInspectResponse = z.infer<typeof colonelRateLimitInspectResponseSchema>;
export type ColonelRateLimitResetResponse = z.infer<typeof colonelRateLimitResetResponseSchema>;
