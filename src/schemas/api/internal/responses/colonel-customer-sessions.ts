// src/schemas/api/internal/responses/colonel-customer-sessions.ts
//
// Per-customer colonel session view (spec docs/specs/colonel-ui/40-*).
//
// This is the SIDECAR-backed, per-customer companion to colonel-sessions.ts (the
// GLOBAL console). It is fed by Onetime::SessionMetadata#safe_dump — a POSITIVE
// allow-list that is the feature's security boundary: there is NO token, NO
// decrypted payload, NO email/secret field on the model, so none can appear here
// and the frontend physically cannot render one.
//
//   - ListCustomerSessions   → GET    /api/colonel/users/:user_id/sessions
//   - RevokeCustomerSession  → DELETE /api/colonel/users/:user_id/sessions/:session_id
//
// Shape verified VERBATIM against the SessionMetadata safe_dump_fields allow-list
// (lib/onetime/models/session_metadata.rb) and the logic adapters
// (apps/api/colonel/logic/colonel/{list_customer_sessions,revoke_customer_session}.rb).
// Epoch fields (created_at / last_activity_at) arrive as bare Unix-second numbers
// and are kept numeric. user_id is the customer EXTERNAL id (extid, 'ur...').

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// ============================================================================
// ListCustomerSessions — one customer's session rows
// ============================================================================

/**
 * A single per-customer session row — the SessionMetadata safe_dump shape
 * verbatim. Every field except session_id/user_id is nullable: org_id is the
 * active organization objid, resolved per write (null if the customer has no
 * org); ip_address/user_agent are copied as-is from the (already Otto-masked)
 * session data; auth_method is the primary login method stamped at auth time
 * ('password' | 'email_auth' | 'webauthn' | 'omniauth' | null for legacy);
 * mfa_used is a nullable boolean pending an enrichment path. There is NO
 * email/token field — that absence is the security guarantee.
 */
export const adminCustomerSessionSchema = z.object({
  session_id: z.string(),
  user_id: z.string(),
  org_id: z.string().nullable(),
  created_at: z.number().nullable(),
  last_activity_at: z.number().nullable(),
  ip_address: z.string().nullable(),
  user_agent: z.string().nullable(),
  auth_method: z.string().nullable(),
  mfa_used: z.boolean().nullable(),
});

/** ListCustomerSessions `details`: the customer's session rows + a count. */
export const colonelCustomerSessionsDetailsSchema = z.object({
  sessions: z.array(adminCustomerSessionSchema),
  count: z.number(),
});

// ============================================================================
// RevokeCustomerSession — guarded revoke ack
// ============================================================================

/** RevokeCustomerSession `record`: the revoked session's id + a revoked flag. */
export const colonelCustomerSessionRevokeRecordSchema = z.object({
  session_id: z.string(),
  revoked: z.boolean(),
});

/** RevokeCustomerSession `details`: a human-readable ack message. */
export const colonelCustomerSessionRevokeDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// RevokeAllCustomerSessions — offboarding / takeover bulk revoke ack
// ============================================================================

/**
 * RevokeAllCustomerSessions `record`: the total lockout, with kill counts so the
 * operator sees how complete the revoke was. `untracked_deleted` is the number of
 * killed blobs the sidecar index did NOT know about (pre-sidecar sessions the
 * best-effort scan swept up); `rodauth_rows_deleted` is 0 in simple mode / when no
 * auth account maps to the customer. `scan_capped` is true when the untracked
 * sweep hit its scan cap — tracked sessions are always killed, but an untracked
 * pre-sidecar session MAY have been missed and the operator should be warned.
 */
export const colonelCustomerSessionRevokeAllRecordSchema = z.object({
  revoked: z.boolean(),
  blobs_deleted: z.number(),
  untracked_deleted: z.number(),
  rodauth_rows_deleted: z.number(),
  scan_capped: z.boolean(),
});

/** RevokeAllCustomerSessions `details`: a human-readable ack message. */
export const colonelCustomerSessionRevokeAllDetailsSchema = z.object({
  message: z.string(),
});

// ============================================================================
// Type Exports
// ============================================================================

export type AdminCustomerSession = z.infer<typeof adminCustomerSessionSchema>;
export type ColonelCustomerSessionRevokeRecord = z.infer<
  typeof colonelCustomerSessionRevokeRecordSchema
>;
export type ColonelCustomerSessionRevokeAllRecord = z.infer<
  typeof colonelCustomerSessionRevokeAllRecordSchema
>;

// Wrapped response schemas for the per-customer sessions view.
// Internal-only; consumed by the Vue admin console, never exposed publicly.

// GET /api/colonel/users/:user_id/sessions → ListCustomerSessions
export const colonelCustomerSessionsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelCustomerSessionsDetailsSchema
);

// DELETE /api/colonel/users/:user_id/sessions/:session_id → RevokeCustomerSession
export const colonelCustomerSessionRevokeResponseSchema = createApiResponseSchema(
  colonelCustomerSessionRevokeRecordSchema,
  colonelCustomerSessionRevokeDetailsSchema
);

// POST /api/colonel/users/:user_id/sessions/revoke-all → RevokeAllCustomerSessions
export const colonelCustomerSessionRevokeAllResponseSchema = createApiResponseSchema(
  colonelCustomerSessionRevokeAllRecordSchema,
  colonelCustomerSessionRevokeAllDetailsSchema
);

export type ColonelCustomerSessionsResponse = z.infer<
  typeof colonelCustomerSessionsResponseSchema
>;
export type ColonelCustomerSessionRevokeResponse = z.infer<
  typeof colonelCustomerSessionRevokeResponseSchema
>;
export type ColonelCustomerSessionRevokeAllResponse = z.infer<
  typeof colonelCustomerSessionRevokeAllResponseSchema
>;
