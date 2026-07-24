// src/shared/composables/useSsoLinkConfirm.ts

/**
 * Mailbox-proof SSO linking composable (#3840 Phase 4)
 *
 * Drives the consent page an emailed link points at when an UNAUTHENTICATED SSO
 * sign-in resolves to an existing PASSWORDLESS account (the H-3 case Phase 3's
 * password-proof path cannot serve — there is no password to prove). The token
 * reached the user ONLY via a link mailed to the on-file address, so possessing
 * it proves mailbox control. Two calls:
 * - fetchPendingLink(token): GET /auth/sso-link-confirm/:token → { provider, email }
 *     display-only context (which provider, which claimed email). NEVER consumes
 *     the token — a mail/link prefetch of the GET must not burn the single-use
 *     token before the user consents.
 * - confirmLink(token): POST /auth/sso-link-confirm { token }
 *     → the backend atomically consumes the token, binds (provider, issuer, uid)
 *       to the located account, and ESTABLISHES THE SESSION via Rodauth's own
 *       login path (the same one POST /auth/login uses). No password: mailbox
 *       possession is the credential, exactly as magic-link authenticates a
 *       passwordless account.
 *
 * INVARIANT (#3840): email may LOCATE an account; only a demonstrated credential
 * may BIND an identity. Here the credential is MAILBOX CONTROL. The token is
 * single-use and short-lived; every failure is a DEAD-END (the token is spent or
 * the account moved) — there is no retryable input on this page, so the view
 * surfaces the specific reason and points the user back to sign in with SSO,
 * which re-issues the email.
 *
 * Backend contract (pinned; flag mismatches):
 * - GET  /auth/sso-link-confirm/:token  200 => { provider, email }
 *                                       404 { error, error_code: 'link_expired' }
 *                                             => missing / consumed / expired
 *                                       500 { error } => code-less; the STORE read
 *                                             failed, so the token is untouched and
 *                                             still live. Classified 'link_error',
 *                                             NOT 'link_expired' (see
 *                                             fetchFallbackForStatus).
 * - POST /auth/sso-link-confirm  200 => { success, redirect? } (session established)
 *                                    or { success, mfa_required, ... } (MFA account —
 *                                    identical body POST /auth/login returns; hand off
 *                                    to the shared /mfa-verify challenge, do NOT complete)
 *                                400 invalid_request  => token missing from the body
 *                                401 link_expired     => token spent/expired, or the
 *                                                        account vanished / not loginable
 *                                409 link_conflict    => account re-emailed since issuance,
 *                                                        or (provider,issuer,uid) bound elsewhere
 *                                409 link_invalidated => a credential change advanced the
 *                                                        account's password watermark
 *                                409 link_error       => the backend could not READ the
 *                                                        watermark (its outage, not a
 *                                                        credential change); still terminal —
 *                                                        the token was consumed first
 *   The failure branch is distinguished by an { error_code } field and, defensively,
 *   the HTTP status.
 *
 * Mirrors useLinkSso: happy paths validate through a zod schema; useAsyncHandler
 * `wrap` manages the loading state and the unexpected (technical) fallback.
 * Failures are classified INSIDE the operation by reading the axios error's
 * `response` directly (the useMfa 422 pattern) — the portable signal in both prod
 * and the mock test harness — and surfaced as a typed errorCode the view branches on.
 */

import {
  ssoLinkConfirmDisplayResponseSchema,
  ssoLinkConfirmResponseSchema,
  isAuthError,
  type SsoLinkConfirmDisplay,
  type SsoLinkConfirmDisplayResponse,
  type SsoLinkConfirmResponse,
  type SsoLinkConfirmSuccess,
} from '@/schemas/api/auth/responses/auth';
import { useApi } from '@/shared/composables/useApi';
import { useAsyncHandler, createError } from '@/shared/composables/useAsyncHandler';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Typed failure the view maps to copy. They differ in WHY the link can't be
 * completed and therefore in the message shown before sending the user back to
 * sign in. All are terminal for the current attempt — there is no retryable
 * input on this page. The one code whose UNDERLYING token may still be live is
 * 'link_error' raised by the GET path (our outage, nothing consumed), so its
 * copy must never claim the link expired; returning to sign in re-issues a fresh
 * email and works regardless.
 */
export type SsoLinkConfirmErrorCode =
  | 'link_expired'
  | 'link_conflict'
  | 'link_invalidated'
  | 'link_error'
  | 'invalid_request'
  | null;

/** Minimal shape of the axios error's carried response (status + parsed body). */
interface ErrorResponseLike {
  status?: number;
  data?: Record<string, unknown>;
}

/**
 * Maps an HTTP status and an optional backend { error_code } to the UI's typed
 * failure. Prefers the explicit backend code (the backend always sends one);
 * falls back to the status family only defensively. Returns null when the failure
 * is neither (e.g. an unclassifiable 5xx) so the caller surfaces a generic message.
 *
 * The five codes below are exactly the set apps/web/auth/routes/sso_link_confirm.rb
 * emits — keep them in lockstep with that route.
 *
 * link_invalidated and link_error share HTTP 409, so ONLY the explicit backend code
 * separates them (the status-family fallback collapses both to link_conflict). They
 * differ in blame, not in outcome: a real credential change vs. a backend that could
 * not read the credential state. Both stay terminal.
 */
function resolveConfirmErrorCode(
  status: number | undefined,
  backendCode: unknown
): SsoLinkConfirmErrorCode {
  if (backendCode === 'link_invalidated') return 'link_invalidated';
  if (backendCode === 'link_error') return 'link_error';
  if (backendCode === 'link_conflict') return 'link_conflict';
  if (backendCode === 'invalid_request') return 'invalid_request';
  if (backendCode === 'link_expired') return 'link_expired';
  // Status-family fallback (backend always sends a code; this is defence only).
  if (status === 401 || status === 404 || status === 410) return 'link_expired';
  if (status === 409) return 'link_conflict';
  if (status === 400) return 'invalid_request';
  return null;
}

/**
 * Dead-end bias for a GET (display-context) failure the backend did NOT classify
 * with an { error_code }.
 *
 * apps/web/auth/routes/sso_link_confirm.rb returns a bare 500 { error: 'Failed to
 * load linking request' } — no error_code — when the SsoLinkVerification load
 * raises (datastore outage). The token is UNTOUCHED and still live for its full
 * TTL, so biasing that to 'link_expired' would tell the user their link is dead
 * and push them back through SSO to re-issue when a reload would have worked.
 * 'link_error' names the real cause ("something went wrong on our side") without
 * asserting the link is spent. Same for a transport failure with no response at
 * all. Anything else (4xx) genuinely does mean missing / consumed / expired.
 */
function fetchFallbackForStatus(status: number | undefined): SsoLinkConfirmErrorCode {
  if (status === undefined || status >= 500) return 'link_error';
  return 'link_expired';
}

/* eslint-disable max-lines-per-function */
export function useSsoLinkConfirm() {
  const { t } = useI18n();
  const $api = useApi();
  const csrfStore = useCsrfStore();

  const pendingLink = ref<SsoLinkConfirmDisplay | null>(null);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const errorCode = ref<SsoLinkConfirmErrorCode>(null);

  const { wrap } = useAsyncHandler({
    notify: false,
    setLoading: (loading) => (isLoading.value = loading),
    onError: () => {
      // Failures are classified inside the operation (setConfirmError). Only fill
      // a generic message for an unexpected throw the operation did not classify
      // (e.g. a zod parse failure) so the view never dead-ends silently.
      if (error.value === null) {
        errorCode.value = null;
        error.value = t('web.sso_link_confirm.errors.generic');
      }
    },
  });

  function clearError() {
    error.value = null;
    errorCode.value = null;
  }

  function messageForCode(code: SsoLinkConfirmErrorCode): string {
    if (code === 'link_expired') return t('web.sso_link_confirm.errors.link_expired');
    if (code === 'link_conflict') return t('web.sso_link_confirm.errors.link_conflict');
    if (code === 'link_invalidated') return t('web.sso_link_confirm.errors.link_invalidated');
    if (code === 'link_error') return t('web.sso_link_confirm.errors.link_error');
    return t('web.sso_link_confirm.errors.generic');
  }

  /**
   * Classifies and stores a failure from the (status, backend error_code) pair.
   * `fallback` biases an unclassifiable failure. The POST passes none (generic
   * message); the GET passes fetchFallbackForStatus, because any failed load of
   * the display context leaves nothing to show and deserves a specific reason.
   */
  function setConfirmError(
    status: number | undefined,
    backendCode: unknown,
    fallback: SsoLinkConfirmErrorCode = null
  ): string {
    const code = resolveConfirmErrorCode(status, backendCode) ?? fallback;
    errorCode.value = code;
    error.value = messageForCode(code);
    return error.value;
  }

  function readErrorResponse(err: unknown): ErrorResponseLike | undefined {
    return (err as { response?: ErrorResponseLike }).response;
  }

  /**
   * Loads the display context for the pending link. Returns null on any failure
   * (error/errorCode are set via setConfirmError); the view then renders the
   * dead-end state instead of the consent CTA. DISPLAY-ONLY — never consumes the
   * token.
   */
  async function fetchPendingLink(token: string): Promise<SsoLinkConfirmDisplay | null> {
    clearError();

    const result = await wrap(async () => {
      let response;
      try {
        response = await $api.get<SsoLinkConfirmDisplayResponse>(
          `/auth/sso-link-confirm/${encodeURIComponent(token)}`
        );
      } catch (err) {
        // No usable context either way, but WHY matters: a code-less 5xx (or no
        // response at all) is our outage with the token still live, not a spent
        // link. See fetchFallbackForStatus.
        const resp = readErrorResponse(err);
        setConfirmError(resp?.status, resp?.data?.error_code, fetchFallbackForStatus(resp?.status));
        throw err;
      }

      const validated = ssoLinkConfirmDisplayResponseSchema.parse(response.data);

      // A 200 that still carries an error body is unusual; treat it as a spent
      // token so the view dead-ends rather than showing a broken consent CTA.
      if (isAuthError(validated)) {
        const rawCode = (response.data as Record<string, unknown>)?.error_code;
        setConfirmError(response.status, rawCode, 'link_expired');
        throw createError(t('web.sso_link_confirm.errors.link_expired'), 'human', 'error');
      }

      pendingLink.value = validated;
      return validated;
    });

    if (!result) {
      pendingLink.value = null;
    }
    return result ?? null;
  }

  /**
   * Confirms the link: POSTs the token (mailbox possession is the proof — no
   * password). On success the backend binds the identity and establishes the
   * session, returning the standard login body (optionally MFA-pending); the
   * caller syncs client auth state and navigates. Returns null on failure; the
   * caller reads errorCode for the specific dead-end message.
   */
  async function confirmLink(token: string): Promise<SsoLinkConfirmSuccess | null> {
    clearError();

    const result = await wrap(async () => {
      let response;
      try {
        response = await $api.post<SsoLinkConfirmResponse>('/auth/sso-link-confirm', {
          token,
          shrimp: csrfStore.shrimp,
        });
      } catch (err) {
        const resp = readErrorResponse(err);
        setConfirmError(resp?.status, resp?.data?.error_code);
        throw err;
      }

      const validated = ssoLinkConfirmResponseSchema.parse(response.data);

      // Defensive: a 200 carrying an error body. Classify it the same way so the
      // view branches consistently on errorCode.
      if (isAuthError(validated)) {
        const rawCode = (response.data as Record<string, unknown>)?.error_code;
        const message = setConfirmError(response.status, rawCode);
        throw createError(message, 'human', 'error');
      }

      return validated;
    });

    return result ?? null;
  }

  return {
    pendingLink,
    isLoading,
    error,
    errorCode,
    fetchPendingLink,
    confirmLink,
    clearError,
  };
}
