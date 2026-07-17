// src/apps/admin/stores/useAdminCustomerSessions.ts

import { defineStore } from 'pinia';
import { ref } from 'vue';

import { useApi } from '@/shared/composables/useApi';
import {
  colonelCustomerSessionsResponseSchema,
  colonelCustomerSessionRevokeResponseSchema,
  colonelCustomerSessionRevokeAllResponseSchema,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import type {
  AdminCustomerSession,
  ColonelCustomerSessionRevokeAllRecord,
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
 *   - revoke(userId, sessionId) → DELETE /api/colonel/users/:user_id/sessions/:session_id
 *   - revokeAll(userId) → POST /api/colonel/users/:user_id/sessions/revoke-all
 *
 * `userId` is the customer EXTERNAL id (extid, 'ur…') — the same value the
 * detail view is keyed by. Not paginated: a single customer's active-session
 * list is small and bounded, so it fetches whole. Reads never audit; the revoke
 * mutations are audited SERVER-SIDE.
 */

/** Zero-count fallback when the revoke-all ack drifts from its schema. */
const EMPTY_REVOKE_ALL: ColonelCustomerSessionRevokeAllRecord = {
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

export const useAdminCustomerSessions = defineStore('adminCustomerSessions', () => {
  /** The customer's active session rows (whole list — never paginated). */
  const sessions = ref<AdminCustomerSession[]>([]);
  /**
   * The acting colonel's own request session id whenever the API can identify
   * it — independent of whether it appears in `sessions` (the component does
   * the row matching). Null when unidentifiable or before/after a failed fetch.
   */
  const currentSessionId = ref<string | null>(null);
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
    currentSessionId.value = null; // reset up-front; only a 2xx re-populates it
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
      currentSessionId.value = result.data.details?.current_session_id ?? null;
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
   * the row stays. The ack is schema-checked as a live tripwire (never fails the
   * action on drift). Throws the network/HTTP error for useAdminMutation to catch.
   */
  async function revoke(userId: string, sessionId: string): Promise<void> {
    const response = await $api.delete(
      `${sessionsUrl(userId)}/${encodeURIComponent(sessionId)}`
    );
    gracefulParse(
      colonelCustomerSessionRevokeResponseSchema,
      response.data,
      'ColonelCustomerSessionRevokeResponse'
    );
    sessions.value = sessions.value.filter((s) => s.session_id !== sessionId);
  }

  /** Revoke ALL sessions (offboarding/takeover); clears the list, returns kill counts. */
  async function revokeAll(userId: string): Promise<ColonelCustomerSessionRevokeAllRecord> {
    const response = await $api.post(`${sessionsUrl(userId)}/revoke-all`);
    const schema = colonelCustomerSessionRevokeAllResponseSchema;
    const result = gracefulParse(schema, response.data, 'ColonelCustomerSessionRevokeAllResponse');
    sessions.value = []; // every session is gone regardless of ack shape
    return result.ok ? result.data.record : EMPTY_REVOKE_ALL;
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    sessions.value = [];
    currentSessionId.value = null;
    loading.value = false;
    error.value = null;
    validationError.value = null;
  }

  return {
    // State
    sessions,
    currentSessionId,
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
