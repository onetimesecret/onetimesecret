// src/schemas/api/internal/responses/colonel-sessions.ts
//
// Per-resource colonel/admin schemas for the Sessions console (ticket #40).
//
// NEW schemas only — the frozen colonel contracts in ./colonel.ts are untouched
// (the Zod tripwire, epic non-goal). These three shapes are for the net-new
// session endpoints (there was no old colonel session screen — CLI-only until
// now):
//
//   - ListSessions     → GET    /api/colonel/sessions             (list + search)
//   - GetSessionDetail → GET    /api/colonel/sessions/:session_id (detail drawer)
//   - DeleteSession    → DELETE /api/colonel/sessions/:session_id (guarded revoke)
//
// Shapes verified against the live logic classes
// (apps/api/colonel/logic/colonel/{list_sessions,get_session_detail,delete_session}.rb),
// which are thin adapters over Onetime::Operations::Sessions::{List,Inspect,Delete}.
// Epoch fields (created_at / authenticated_at / ttl) arrive as bare Unix-second
// numbers and are kept numeric (mirroring the existing `bannedIPSchema.banned_at`).

import { createApiResponseSchema } from '@/schemas/api/base';
import { paginationSchema } from './colonel';
import { z } from 'zod';

// ============================================================================
// ListSessions — list row + details
// ============================================================================

/**
 * A single session summary row (ListSessions `details.sessions[]`). `session_id`
 * is the bare id used for routing + revoke; `key` is the resolved Redis key.
 * Identity fields are nullable (anonymous / pre-auth sessions carry no email or
 * external id). `created_at` is `authenticated_at` as a Unix-second number.
 */
export const colonelSessionSchema = z.object({
  session_id: z.string(),
  key: z.string(),
  authenticated: z.boolean(),
  email: z.string().nullable(),
  external_id: z.string().nullable(),
  role: z.string().nullable(),
  ip_address: z.string().nullable(),
  user_agent: z.string().nullable(),
  created_at: z.number().nullable(),
});

/**
 * Keyspace shape for the listing. The list shows only identity sessions
 * (`pagination.total_count`); `scanned` is how many session keys were examined,
 * `anonymous_count` how many CSRF-only sessions were hidden, and `scan_capped`
 * whether the bounded scan hit its cap (identity sessions beyond the window are
 * not listed — the by-id inspect path is unaffected).
 */
export const colonelSessionScanSchema = z.object({
  scanned: z.number(),
  anonymous_count: z.number(),
  scan_capped: z.boolean(),
});

/** Sessions list response details: rows + pagination + keyspace scan meta. */
export const colonelSessionsDetailsSchema = z.object({
  sessions: z.array(colonelSessionSchema),
  pagination: paginationSchema,
  scan: colonelSessionScanSchema,
});

// ============================================================================
// GetSessionDetail — detail drawer
// ============================================================================

/**
 * The typed field read-out for one session (GetSessionDetail `record`). `ttl` is
 * the Redis TTL in seconds (-1 no expiry, -2 gone). The remaining fields are
 * best-effort projections of the session payload and are all nullable because a
 * session may be anonymous / partially populated. `account_id` may arrive as a
 * string or number depending on the auth backend.
 */
export const colonelSessionDetailRecordSchema = z.object({
  session_id: z.string(),
  key: z.string(),
  ttl: z.number().nullable(),
  authenticated: z.boolean(),
  email: z.string().nullable(),
  external_id: z.string().nullable(),
  account_id: z.union([z.string(), z.number()]).nullable(),
  role: z.string().nullable(),
  locale: z.string().nullable(),
  ip_address: z.string().nullable(),
  user_agent: z.string().nullable(),
  org_context: z.string().nullable(),
  authenticated_at: z.number().nullable(),
  // Rodauth records the auth methods as a LIST (e.g. ["password", "totp"]); a
  // string form is accepted for legacy/plaintext sessions. (This was declared
  // `z.string()` while the console never decrypted — the field was always null
  // via the `_raw` fallback, so the array shape only surfaced once decode landed.)
  authenticated_by: z.union([z.string(), z.array(z.string())]).nullable(),
  active_session_id: z.string().nullable(),
});

/**
 * GetSessionDetail `details`: the full parsed session payload for the raw
 * inspector. Keys are arbitrary (colonel-only, parity with `ots session
 * inspect`), so this is an open record.
 */
export const colonelSessionDetailDetailsSchema = z.object({
  data: z.record(z.string(), z.unknown()),
});

// ============================================================================
// DeleteSession — guarded revoke ack
// ============================================================================

/** DeleteSession `record`: the revoked session's id + a deleted flag. */
export const colonelSessionDeleteRecordSchema = z.object({
  session_id: z.string(),
  deleted: z.boolean(),
});

/** DeleteSession `details`: a human-readable ack message. */
export const colonelSessionDeleteDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type ColonelSession = z.infer<typeof colonelSessionSchema>;
export type ColonelSessionScan = z.infer<typeof colonelSessionScanSchema>;
export type ColonelSessionDetailRecord = z.infer<typeof colonelSessionDetailRecordSchema>;
export type ColonelSessionDetailDetails = z.infer<typeof colonelSessionDetailDetailsSchema>;
export type ColonelSessionDeleteRecord = z.infer<typeof colonelSessionDeleteRecordSchema>;

// Wrapped response schemas for the colonel Sessions console (ticket #40).
// Internal-only; consumed by the Vue admin console, never exposed publicly.
//
// The view + store import these DIRECTLY (CONTRACT 3) so they typecheck
// independently of the registry; the Integrate step adds the registry keys from
// wiringInstructions.

// GET /api/colonel/sessions → ListSessions
export const colonelSessionsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelSessionsDetailsSchema
);

// GET /api/colonel/sessions/:session_id → GetSessionDetail
export const colonelSessionDetailResponseSchema = createApiResponseSchema(
  colonelSessionDetailRecordSchema,
  colonelSessionDetailDetailsSchema
);

// DELETE /api/colonel/sessions/:session_id → DeleteSession
export const colonelSessionDeleteResponseSchema = createApiResponseSchema(
  colonelSessionDeleteRecordSchema,
  colonelSessionDeleteDetailsSchema
);

export type ColonelSessionsResponse = z.infer<typeof colonelSessionsResponseSchema>;
export type ColonelSessionDetailResponse = z.infer<typeof colonelSessionDetailResponseSchema>;
export type ColonelSessionDeleteResponse = z.infer<typeof colonelSessionDeleteResponseSchema>;
