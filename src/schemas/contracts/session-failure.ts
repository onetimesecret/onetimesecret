// src/schemas/contracts/session-failure.ts
//
// Stable codes on authentication refusals (#4462, #4469).
//
// Mirrors `Onetime::SessionFailureCode` (lib/onetime/session/failure_code.rb).
// A 401 from any API surface or from `/auth` that was caused by the customer
// session, or by a credential the request presented, carries two additive
// fields:
//
//   code        the server's typed reason, verbatim
//   code_scope  the class of failure — what a client acts on
//
// Existing fields (`error`, `message`, `error_type`, `success`, `timestamp`)
// and statuses are unchanged. A 401 WITHOUT a code makes no statement about
// the customer session: a backend that predates this contract, or a 401
// that is about neither the session nor a credential.

import { z } from 'zod';

/** Scopes the server emits today. */
export const sessionFailureScopeValues = [
  // The customer session was examined and is not (or is no longer)
  // authenticated. Reconcile against the server; never mutate auth state in
  // the handler that saw the 401.
  'customer_session',
  // The session could not be verified (datastore outage). Not a verdict about
  // the session and never a sign-out.
  'verification_unavailable',
  // The admin-only idle/absolute timeout. The customer session is untouched.
  'admin_session',
  // A credential the request presented (a login, a second factor, a
  // re-authentication, an API key) was examined and rejected (#4469). Not a
  // statement about the customer session, which may be valid: the form that
  // sent the credential owns the message, and nothing is reconciled.
  'credential',
] as const;

export const sessionFailureScopeSchema = z.enum(sessionFailureScopeValues);
export type SessionFailureScope = z.infer<typeof sessionFailureScopeSchema>;

/** Every code the server can send, keyed to its scope. */
export const SESSION_FAILURE_CODES = {
  session_missing: 'customer_session',
  awaiting_mfa: 'customer_session',
  not_authenticated: 'customer_session',
  identity_missing: 'customer_session',
  surface_mismatch: 'customer_session',
  customer_not_found: 'customer_session',
  account_suspended: 'customer_session',
  stale_credentials: 'customer_session',
  admin_session_expired: 'admin_session',
  active_session_revoked: 'customer_session',
  active_session_unavailable: 'verification_unavailable',
  customer_unavailable: 'verification_unavailable',
  // The credential vocabulary (#4469), no finer than the message each path
  // already sends: one code for an unknown login and a wrong password.
  invalid_credentials: 'credential',
  api_key_invalid: 'credential',
  suspended_credentials: 'credential',
  // Answered with 403 by Rodauth (lockout, unverified account); the only
  // 403s that carry the pair.
  account_locked: 'credential',
  account_unverified: 'credential',
} as const satisfies Record<string, SessionFailureScope>;

export type SessionFailureCode = keyof typeof SESSION_FAILURE_CODES;

export const sessionFailureCodeValues = Object.keys(SESSION_FAILURE_CODES) as [
  SessionFailureCode,
  ...SessionFailureCode[],
];
export const sessionFailureCodeSchema = z.enum(sessionFailureCodeValues);

/**
 * The pair as it appears in a refusal body.
 *
 * `code` is an open string on purpose: `code_scope` is what a client acts on,
 * so a code added by a newer backend is still handled correctly by scope. An
 * unknown SCOPE fails the parse and the 401 is treated as uncoded.
 */
export const sessionFailureSchema = z.object({
  code: z.string().min(1),
  code_scope: sessionFailureScopeSchema,
});

export type SessionFailure = z.infer<typeof sessionFailureSchema>;

/**
 * Reads the session-failure pair off a rejected request.
 *
 * Accepts an axios-style error (`error.response`), a response, or a bare
 * body. Returns null unless the status is 401 (when a status is available)
 * and the body carries a valid pair — so every other rejection, and every
 * uncoded 401, is "no statement about the customer session". The one
 * exception is a 403 whose pair is in the `credential` scope (a locked-out
 * or unverified account, #4469): a form may read it, and the interceptor,
 * which reports 401s only, never reconciles on it.
 */
export function parseSessionFailure(input: unknown): SessionFailure | null {
  if (input === null || typeof input !== 'object') return null;

  const candidate = input as {
    response?: { status?: unknown; data?: unknown };
    status?: unknown;
    data?: unknown;
  };
  const response = candidate.response ?? (candidate.data !== undefined ? candidate : undefined);
  const status = response?.status;
  if (!statusCarriesScope(status)) return null;

  const body = response ? response.data : input;
  const parsed = sessionFailureSchema.safeParse(body);
  if (!parsed.success) return null;
  if (status === 403 && parsed.data.code_scope !== 'credential') return null;
  return parsed.data;
}

/** Whether a status can carry the pair at all: 401, or 403 for a credential refusal. */
function statusCarriesScope(status: unknown): boolean {
  return status === undefined || status === 401 || status === 403;
}
