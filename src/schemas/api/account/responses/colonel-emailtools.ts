// src/schemas/api/account/responses/colonel-emailtools.ts
//
// Per-resource colonel/admin schemas for the Email + Rate-limit Tools screen
// (ticket #44).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are UNTOUCHED
// (the Zod tripwire, epic non-goal). These surface CLI-only powers
// (`bin/ots email {templates,preview,test}` and `bin/ots ratelimit keys`) that
// never had a colonel endpoint, so there is nothing to reuse. Distinct
// `emailtools` namespace so this screen never collides with another's contract
// (CONTRACT 2 / 3).
//
// Shapes verified against the live colonel logic classes
// (apps/api/colonel/logic/colonel/{list_email_templates,preview_email_template,
// send_test_email,list_rate_limiters,inspect_rate_limit,reset_rate_limit}.rb),
// thin adapters over Onetime::Operations::Email::* and
// Onetime::Operations::RateLimit::*.

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
