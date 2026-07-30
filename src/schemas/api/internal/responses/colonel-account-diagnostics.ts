// src/schemas/api/internal/responses/colonel-account-diagnostics.ts
//
// Per-account auth diagnostics — the "why can't this user log in / sign up"
// panel on the colonel customer detail view.
//
//   - GetAccountDiagnostics → GET /api/colonel/users/:user_id/diagnostics
//
// Shape mirrors Auth::Operations::Customers::Diagnose (the single
// implementation, shared with `bin/ots customers diagnose`): a derived
// `findings` triage list plus the raw evidence `sections`. Every section
// degrades independently server-side (`available: false` + reason) — e.g.
// simple auth mode has no SQL authdb — so each section schema admits the
// unavailable variant with every data field optional.
//
// `available` marks which variant arrived, but it is OPTIONAL here on purpose,
// and that is one half of a deliberate pair. Requiring it would mean a server
// that stops emitting it for one section fails the whole parse, and
// useResourceFetch answers a parse failure by discarding the response and
// setting `validationError` — blanking the entire break-glass panel during
// exactly the incident it exists to triage. So version skew degrades a cell
// instead of the panel, and the CONSUMER is fail-closed to pay for it:
// AdminAccountDiagnosticsSection's `sectionOk()` treats a section as usable
// only on an explicit `available === true`, so a missing flag renders
// "Unknown" rather than a fabricated healthy value. Do not tighten this field
// without moving the guard, or loosen that guard without tightening this.
//
// Epoch fields are bare Unix-second numbers.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// ============================================================================
// Findings — the triage summary the panel renders as callouts
// ============================================================================

export const accountDiagnosisFindingSchema = z.object({
  severity: z.enum(['critical', 'warning', 'info']),
  code: z.string(),
  message: z.string(),
});

// ============================================================================
// Sections — raw per-source evidence
// ============================================================================

/**
 * Fields shared by every degradable section. `reason_code` is the
 * machine-readable counterpart to the human `reason` — notably `authdb_error`
 * (the database did not answer, so account existence is UNKNOWABLE) versus
 * `simple_mode` (there is no SQL authdb by design). `no_email` marks the
 * benign case where there was simply nothing to inspect (an orphan looked up
 * by extid or account id carries no address to rate-limit), as opposed to a
 * read that failed.
 */
const sectionAvailability = {
  available: z.boolean().optional(),
  reason: z.string().nullable().optional(),
  reason_code: z
    .enum(['simple_mode', 'no_account', 'authdb_error', 'no_email'])
    .nullable()
    .optional(),
};

/** Redis-side customer record state. */
export const diagnosisCustomerSectionSchema = z.object({
  found: z.boolean(),
  extid: z.string().nullable().optional(),
  email: z.string().nullable().optional(),
  role: z.string().nullable().optional(),
  verified: z.boolean().nullable().optional(),
  suspended: z.boolean().nullable().optional(),
  suspended_at: z.number().nullable().optional(),
  suspended_reason: z.string().nullable().optional(),
  created: z.number().nullable().optional(),
  last_login: z.number().nullable().optional(),
  locale: z.string().nullable().optional(),
  planid: z.string().nullable().optional(),
  error: z.string().nullable().optional(),
});

/** Rodauth accounts row + linked identities. */
export const diagnosisAuthAccountSectionSchema = z.object({
  ...sectionAvailability,
  found: z.boolean().optional(),
  account_id: z.number().nullable().optional(),
  status: z.string().nullable().optional(),
  email: z.string().nullable().optional(),
  email_matches_customer: z.boolean().nullable().optional(),
  linked_extid: z.string().nullable().optional(),
  created_at: z.number().nullable().optional(),
  has_password: z.boolean().nullable().optional(),
  password_changed_at: z.number().nullable().optional(),
  last_login_at: z.number().nullable().optional(),
  external_identities: z
    .array(z.object({ provider: z.string(), issuer: z.string().nullable() }))
    .optional(),
});

export const diagnosisMfaSectionSchema = z.object({
  ...sectionAvailability,
  otp_enabled: z.boolean().optional(),
  otp_failures: z.number().nullable().optional(),
  webauthn_credentials: z.number().optional(),
});

export const diagnosisVerificationSectionSchema = z.object({
  ...sectionAvailability,
  pending: z.boolean().optional(),
  requested_at: z.number().nullable().optional(),
  email_last_sent: z.number().nullable().optional(),
});

export const diagnosisPasswordResetSectionSchema = z.object({
  ...sectionAvailability,
  pending: z.boolean().optional(),
  deadline: z.number().nullable().optional(),
  email_last_sent: z.number().nullable().optional(),
});

export const diagnosisLockoutSectionSchema = z.object({
  ...sectionAvailability,
  login_failures: z.number().optional(),
  locked: z.boolean().optional(),
  deadline: z.number().nullable().optional(),
  email_last_sent: z.number().nullable().optional(),
});

export const diagnosisSessionsSectionSchema = z.object({
  ...sectionAvailability,
  active_count: z.number().optional(),
  last_use: z.number().nullable().optional(),
});

/** Newest-first tail of Rodauth's account_authentication_audit_logs. */
export const diagnosisAuditLogEntrySchema = z.object({
  at: z.number().nullable(),
  message: z.string(),
  metadata: z.unknown().optional(),
});

export const diagnosisAuditLogSectionSchema = z.object({
  ...sectionAvailability,
  entries: z.array(diagnosisAuditLogEntrySchema).optional(),
});

/** Login rate limiter keys (RateLimit::Inspect entry shape verbatim). */
export const diagnosisRateLimitEntrySchema = z.object({
  key: z.string(),
  ttl: z.number().nullable(),
  value: z.string().nullable(),
  exists: z.boolean(),
});

export const diagnosisRateLimitsSectionSchema = z.object({
  ...sectionAvailability,
  entries: z.array(diagnosisRateLimitEntrySchema).optional(),
});

export const accountDiagnosisSectionsSchema = z.object({
  customer: diagnosisCustomerSectionSchema,
  auth_account: diagnosisAuthAccountSectionSchema,
  mfa: diagnosisMfaSectionSchema,
  verification: diagnosisVerificationSectionSchema,
  password_reset: diagnosisPasswordResetSectionSchema,
  lockout: diagnosisLockoutSectionSchema,
  sessions: diagnosisSessionsSectionSchema,
  audit_log: diagnosisAuditLogSectionSchema,
  rate_limits: diagnosisRateLimitsSectionSchema,
});

// ============================================================================
// Response envelope
// ============================================================================

export const colonelAccountDiagnosticsRecordSchema = z.object({
  identifier: z.string(),
  found: z.boolean(),
});

export const colonelAccountDiagnosticsDetailsSchema = z.object({
  findings: z.array(accountDiagnosisFindingSchema),
  sections: accountDiagnosisSectionsSchema,
});

// GET /api/colonel/users/:user_id/diagnostics → GetAccountDiagnostics
export const colonelAccountDiagnosticsResponseSchema = createApiResponseSchema(
  colonelAccountDiagnosticsRecordSchema,
  colonelAccountDiagnosticsDetailsSchema
);

// ============================================================================
// Type Exports
// ============================================================================

export type AccountDiagnosisFinding = z.infer<typeof accountDiagnosisFindingSchema>;
export type AccountDiagnosisSections = z.infer<typeof accountDiagnosisSectionsSchema>;
export type DiagnosisAuditLogEntry = z.infer<typeof diagnosisAuditLogEntrySchema>;
export type ColonelAccountDiagnosticsResponse = z.infer<
  typeof colonelAccountDiagnosticsResponseSchema
>;
