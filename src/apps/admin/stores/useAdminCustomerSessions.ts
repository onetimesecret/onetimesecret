// src/apps/admin/stores/useAdminCustomerSessions.ts

import type { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { ref } from 'vue';

import { confirmHeaders } from '@/apps/admin/utils/confirmHeader';
import { reasonBodyArgs, reasonQueryArgs } from '@/apps/admin/utils/operatorReason';
import { useApi } from '@/shared/composables/useApi';
import {
  colonelCustomerSessionsResponseSchema,
  colonelCustomerSessionRevokeResponseSchema,
  colonelCustomerSessionRevokeAllResponseSchema,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import type {
  AdminCustomerSession,
  ColonelCustomerSessionRevokeAllRecord as RevokeAllRecord,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import { gracefulParse } from '@/utils/schemaValidation';

/**
 * Per-CUSTOMER session store (spec docs/specs/colonel-ui/40-*).
 *
 * The SIDECAR-backed companion to {@link useAdminSessions} (the GLOBAL scan
 * console). Where that store paginates a bounded SCAN of every `session:*` key,
 * this one reads ONE customer's `active_sessions` sorted-set projection via the
 * SessionMetadata safe_dump allow-list — no token, no payload, no email/secret
 * can appear because none exists on the model.
 *
 *   - fetchForCustomer(userId) → GET    /api/colonel/users/:user_id/sessions
 *   - revoke(userId, handle, confirm, reason?) → DELETE …/sessions/:session_handle
 *   - revokeAll(userId, confirm, reason?) → POST …/sessions/revoke-all
 *
 * Both revoke verbs are TIER 1 destructive (#4326): the server refuses them
 * unless the request carries the account identifier (email, public id when it
 * has none) in X-OTS-Confirm. The trailing `reason` is the OPTIONAL operator
 * WHY (#4338) — orthogonal to the confirmation, and absent by default, so an
 * action taken without one is the request it always was.
 *
 * Sessions are identified by session_handle, a non-reversible digest of the raw
 * session id (finding F-01) — the raw sid (a live cookie value) never reaches
 * the client.
 *
 * `userId` is the customer EXTERNAL id (extid, 'ur…') — the same value the
 * detail view is keyed by. Not paginated: a single customer's active-session
 * list is small and bounded, so it fetches whole. Reads never audit; the revoke
 * mutations are audited SERVER-SIDE.
 */

/** Zero-count fallback when the revoke-all ack drifts from its schema. */
const EMPTY_REVOKE_ALL: RevokeAllRecord = {
  revoked: true,
  blobs_deleted: 0,
  untracked_deleted: 0,
  rodauth_rows_deleted: 0,
  scan_capped: false,
};

/** The per-customer sessions collection URL (extid, 'ur…'). */
function sessionsUrl(userId: string): string {
  return `/api/colonel/users/${encodeURIComponent(userId)}/sessions`;
}

/** Schema-check the list payload; the store decides how to degrade on a miss. */
function parseSessionsResponse(data: unknown) {
  return gracefulParse(
    colonelCustomerSessionsResponseSchema,
    data,
    'ColonelCustomerSessionsResponse'
  );
}

/**
 * DELETE one session. The account identifier rides X-OTS-Confirm (#4326) — the
 * server refuses this verb without it — and the optional operator reason (#4338)
 * rides the QUERY STRING beside it, because DELETE bodies are not reliably
 * parsed across this stack. The ack is schema-checked as a live tripwire; drift
 * never fails the action, because a 2xx means it already happened server-side.
 */
async function requestRevoke(
  $api: AxiosInstance,
  userId: string,
  sessionHandle: string,
  confirm: string,
  reason?: string
): Promise<void> {
  // Absent reason contributes NOTHING to the config — the request is then
  // byte-identical to the pre-#4338 one.
  const [reasonConfig] = reasonQueryArgs(reason);
  const response = await $api.delete(
    `${sessionsUrl(userId)}/${encodeURIComponent(sessionHandle)}`,
    { headers: confirmHeaders(confirm), ...reasonConfig }
  );
  gracefulParse(
    colonelCustomerSessionRevokeResponseSchema,
    response.data,
    'ColonelCustomerSessionRevokeResponse'
  );
}

/**
 * POST the bulk revoke; ack drift degrades to the zero-count fallback. This one
 * has a body, so the optional reason (#4338) rides it; with no reason the body
 * stays `undefined` exactly as before.
 */
async function requestRevokeAll(
  $api: AxiosInstance,
  userId: string,
  confirm: string,
  reason?: string
): Promise<RevokeAllRecord> {
  const [body] = reasonBodyArgs(reason);
  const response = await $api.post(`${sessionsUrl(userId)}/revoke-all`, body, {
    headers: confirmHeaders(confirm),
  });
  const result = gracefulParse(
    colonelCustomerSessionRevokeAllResponseSchema,
    response.data,
    'ColonelCustomerSessionRevokeAllResponse'
  );
  return result.ok ? result.data.record : EMPTY_REVOKE_ALL;
}

export const useAdminCustomerSessions = defineStore('adminCustomerSessions', () => {
  /** The customer's active session rows (whole list — never paginated). */
  const sessions = ref<AdminCustomerSession[]>([]);
  /**
   * The acting colonel's own request session HANDLE whenever the API can identify
   * it — independent of whether it appears in `sessions` (the component does
   * the row matching). Null when unidentifiable or before/after a failed fetch.
   */
  const currentSessionHandle = ref<string | null>(null);
  /** True while a request is in flight. */
  const loading = ref(false);
  /** The last thrown network/HTTP error, or null. */
  const error = ref<Error | null>(null);
  /** The context label when the payload failed Zod validation, else null. */
  const validationError = ref<string | null>(null);

  const $api = useApi();

  /**
   * Fetch one customer's active sessions.
   *
   * @param userId the customer's external id (extid, 'ur…').
   * @returns the session rows, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (rows are cleared first).
   */
  async function fetchForCustomer(
    userId: string
  ): Promise<AdminCustomerSession[] | null> {
    loading.value = true;
    error.value = null;
    validationError.value = null;
    currentSessionHandle.value = null; // reset up-front; only a 2xx re-populates it
    try {
      const response = await $api.get(sessionsUrl(userId));
      const result = parseSessionsResponse(response.data);
      if (!result.ok) {
        // Contract mismatch: degrade to empty; gracefulParse already reported it.
        validationError.value = 'ColonelCustomerSessionsResponse';
        sessions.value = [];
        return null;
      }
      sessions.value = result.data.details?.sessions ?? [];
      currentSessionHandle.value = result.data.details?.current_session_handle ?? null;
      return sessions.value;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      sessions.value = [];
      error.value = err instanceof Error ? err : new Error(String(err));
      throw error.value;
    } finally {
      loading.value = false;
    }
  }

  /**
   * Revoke one of the customer's sessions (logs that user out mid-flight, so the
   * view gates it behind a confirm dialog). Drops the row ONLY after a 2xx — the
   * drop is sequenced after the awaited DELETE, so a failure throws before it and
   * the row stays. Throws the network/HTTP error for useAdminMutation to catch.
   *
   * @param confirm the account identifier the server gates the verb on (#4326).
   * @param reason the OPTIONAL operator why (#4338), recorded in the trail.
   */
  async function revoke(
    userId: string,
    handle: string,
    confirm: string,
    reason?: string
  ): Promise<void> {
    await requestRevoke($api, userId, handle, confirm, reason);
    sessions.value = sessions.value.filter((s) => s.session_handle !== handle);
  }

  /**
   * Revoke ALL sessions (offboarding/takeover); clears the list, returns kill
   * counts. `reason` is the OPTIONAL operator why (#4338) — offboarding and
   * account-takeover response read identically in the trail without it.
   */
  async function revokeAll(
    userId: string,
    confirm: string,
    reason?: string
  ): Promise<RevokeAllRecord> {
    const record = await requestRevokeAll($api, userId, confirm, reason);
    sessions.value = []; // every session is gone regardless of ack shape
    return record;
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    sessions.value = [];
    currentSessionHandle.value = null;
    loading.value = false;
    error.value = null;
    validationError.value = null;
  }

  return {
    // State
    sessions,
    currentSessionHandle,
    loading,
    error,
    validationError,
    // Actions
    fetchForCustomer,
    revoke,
    revokeAll,
    $reset,
  };
});
