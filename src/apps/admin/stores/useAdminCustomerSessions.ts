// src/apps/admin/stores/useAdminCustomerSessions.ts

import { defineStore } from 'pinia';
import { ref } from 'vue';

import { useApi } from '@/shared/composables/useApi';
import {
  colonelCustomerSessionsResponseSchema,
  colonelCustomerSessionRevokeResponseSchema,
} from '@/schemas/api/internal/responses/colonel-customer-sessions';
import type { AdminCustomerSession } from '@/schemas/api/internal/responses/colonel-customer-sessions';
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
 *
 * `userId` is the customer EXTERNAL id (extid, 'ur…') — the same value the
 * detail view is keyed by. Not paginated: a single customer's active-session
 * list is small and bounded, so it fetches whole. Reads never audit; the revoke
 * mutation is audited SERVER-SIDE.
 */
export const useAdminCustomerSessions = defineStore('adminCustomerSessions', () => {
  /** The customer's active session rows (whole list — never paginated). */
  const sessions = ref<AdminCustomerSession[]>([]);
  /** True while a request is in flight. */
  const loading = ref(false);
  /** The last thrown network/HTTP error, or null. */
  const error = ref<Error | null>(null);
  /** The context label when the payload failed Zod validation, else null. */
  const validationError = ref<string | null>(null);

  const $api = useApi();

  function sessionsUrl(userId: string): string {
    return `/api/colonel/users/${encodeURIComponent(userId)}/sessions`;
  }

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
    try {
      const response = await $api.get(sessionsUrl(userId));
      const result = gracefulParse(
        colonelCustomerSessionsResponseSchema,
        response.data,
        'ColonelCustomerSessionsResponse'
      );
      if (!result.ok) {
        // Contract mismatch: degrade to empty; gracefulParse already reported it.
        validationError.value = 'ColonelCustomerSessionsResponse';
        sessions.value = [];
        return null;
      }
      sessions.value = result.data.details?.sessions ?? [];
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
   * view gates this behind a confirm dialog). Optimistically drops the row ONLY
   * after a 2xx — the drop is sequenced after the awaited DELETE, so a failure
   * throws before it and the row stays. The ack is run through the schema to keep
   * the contract a live tripwire without failing the action on ack drift.
   *
   * @throws the network/HTTP error on failure (the caller — useAdminMutation —
   *   captures it for the dialog and the row is preserved for retry).
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

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    sessions.value = [];
    loading.value = false;
    error.value = null;
    validationError.value = null;
  }

  return {
    // State
    sessions,
    loading,
    error,
    validationError,
    // Actions
    fetchForCustomer,
    revoke,
    $reset,
  };
});
