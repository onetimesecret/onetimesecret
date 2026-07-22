// src/shared/composables/useConnectedIdentities.ts

/**
 * Connected Identities composable (SSO account-linking — #3840 Phase 2)
 *
 * Manages the SSO identities linked to the authenticated account:
 * - fetchIdentities(): GET /auth/identities (account-scoped list)
 * - removeIdentity(id): DELETE /auth/identities/:id (CSRF-protected)
 *
 * INVARIANT: email may LOCATE an account; only a demonstrated CREDENTIAL may
 * BIND an identity. Here the credential is the active authenticated session, so
 * both endpoints only ever read/mutate the caller's own rows (the backend
 * scopes every query by session_value — a cross-account id filters to 0 rows,
 * so there is no IDOR to defend against on the client).
 *
 * Backend contract:
 * - GET    200 => { identities: [{ id, provider, issuer, uid }] }
 * - DELETE 200 => { success: string }
 *     - 401 => not logged in / invalid session
 *     - 404 => identity not owned by the caller OR does not exist
 *     - 409 => { error, error_code: 'last_credential' } — removing the FINAL
 *              identity of an SSO-only account (no usable password) is refused
 *              because it would lock the user out.
 *     - 500 => unexpected failure
 *
 * Mirrors useMfa: happy paths validate the response through a zod schema; the
 * useAsyncHandler `wrap` drives reactive loading/error and maps failures via
 * onError. Success emits a notification; the caller renders `error`/`errorCode`.
 */

import {
  identitiesResponseSchema,
  removeIdentityResponseSchema,
  isAuthError,
  type ConnectedIdentity,
  type IdentitiesResponse,
  type RemoveIdentityResponse,
} from '@/schemas/api/auth/responses/auth';
import type { ApplicationError } from '@/schemas/errors';
import { useApi } from '@/shared/composables/useApi';
import { useAsyncHandler, createError } from '@/shared/composables/useAsyncHandler';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Distinguishes the SSO-only lockout guard (409 last_credential) from generic
 * failures so the UI can surface "keep at least one sign-in method" guidance
 * instead of a bare error.
 */
export type IdentityErrorCode = 'last_credential' | null;

/* eslint-disable max-lines-per-function */
export function useConnectedIdentities() {
  const { t } = useI18n();
  const $api = useApi();
  const csrfStore = useCsrfStore();
  const notificationsStore = useNotificationsStore();

  const identities = ref<ConnectedIdentity[]>([]);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const errorCode = ref<IdentityErrorCode>(null);

  const { wrap } = useAsyncHandler({
    notify: false,
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err: ApplicationError) => {
      const status = typeof err.code === 'number' ? err.code : null;
      const backendCode =
        err.details && typeof err.details === 'object'
          ? (err.details as Record<string, unknown>).error_code
          : undefined;

      if (status === 409 && backendCode === 'last_credential') {
        errorCode.value = 'last_credential';
        error.value = t('web.auth.connections.errors.last_credential');
        return;
      }
      if (status === 404) {
        error.value = t('web.auth.connections.errors.not_found');
        return;
      }
      if (status === 401) {
        error.value = t('web.auth.connections.errors.unauthorized');
        return;
      }
      error.value = t('web.auth.connections.errors.generic');
    },
  });

  function clearError() {
    error.value = null;
    errorCode.value = null;
  }

  /**
   * Fetches the SSO identities linked to the current account.
   * Returns [] on error (error state is set via onError).
   */
  async function fetchIdentities(): Promise<ConnectedIdentity[]> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.get<IdentitiesResponse>('/auth/identities');
      const validated = identitiesResponseSchema.parse(response.data);
      identities.value = validated.identities;
      return validated.identities;
    });

    if (!result) {
      identities.value = [];
    }
    return result ?? [];
  }

  /**
   * Removes a single linked identity by its account_identities row id.
   *
   * @param id - numeric account_identities PK (the delete handle)
   * @returns true when the row was removed
   *
   * The DELETE is CSRF-protected like /auth/active-sessions and all non-SSO
   * /auth routes. On success the row is dropped from local state and a
   * notification is shown. A 409 last_credential surfaces via errorCode.
   */
  async function removeIdentity(id: number): Promise<boolean> {
    clearError();

    const result = await wrap(async () => {
      const response = await $api.delete<RemoveIdentityResponse>(`/auth/identities/${id}`, {
        // Mirror /auth/active-sessions: send shrimp in the body in addition to
        // the axios interceptor's X-CSRF-Token header (either satisfies the
        // guard; both is belt-and-suspenders).
        data: { shrimp: csrfStore.shrimp },
      });
      const validated = removeIdentityResponseSchema.parse(response.data);

      // A 200 that still carries an error body would be unusual, but guard so a
      // malformed success never silently drops a row.
      if (isAuthError(validated)) {
        throw createError(t('web.auth.connections.errors.generic'), 'human', 'error');
      }

      identities.value = identities.value.filter((identity) => identity.id !== id);
      notificationsStore.show(t('web.auth.connections.removed_success'), 'success', 'top');
      return true;
    });

    return result ?? false;
  }

  return {
    identities,
    isLoading,
    error,
    errorCode,
    fetchIdentities,
    removeIdentity,
    clearError,
  };
}
