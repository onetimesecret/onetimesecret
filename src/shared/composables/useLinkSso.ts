// src/shared/composables/useLinkSso.ts

/**
 * Sign-in interstitial composable (SSO password-challenge linking — #3840 Phase 3)
 *
 * Drives the interstitial an UNAUTHENTICATED SSO sign-in is redirected to when
 * its IdP email matches an existing account that HAS a password (the H-3 case
 * that Phase 2 could only refuse). Two calls:
 * - fetchChallenge(token): GET /auth/link-sso/:token → { provider, email }
 *     (display-only context: which provider, which claimed email)
 * - verifyLink(token, password): POST /auth/link-sso { token, password }
 *     → on success the backend verifies the EXISTING password, binds
 *       (provider, issuer, uid) to the located account, and ESTABLISHES THE
 *       SESSION, returning an optional internal redirect target.
 *
 * INVARIANT (#3840): email may LOCATE an account; only a demonstrated CREDENTIAL
 * may BIND an identity. Here the credential is the account's existing password —
 * the interstitial is the password-proof path, nothing more. The challenge token
 * is single-use and short-lived (backend Familia TTL model); a spent, expired,
 * or unknown token yields a distinct error the UI treats as a dead-end (point
 * the user at the Phase 2 Connected Identities flow) rather than a retry.
 *
 * Backend contract (pinned; flag mismatches):
 * - GET  /auth/link-sso/:token  200 => { provider, email }
 *                               404/410 => token missing / expired / consumed
 * - POST /auth/link-sso         200 => { success, redirect? } (session established)
 *                                    or { success, mfa_required, ... } (MFA account —
 *                                    same body POST /auth/login returns; hand off to
 *                                    the shared /mfa-verify challenge, do NOT complete)
 *                               401 invalid_password => wrong password (retryable)
 *                               401 link_expired     => token expired / consumed (dead-end)
 *   The failure branch is distinguished by HTTP status and, when present, an
 *   { error_code } field ('invalid_password' vs 'invalid_token'/'expired_token'/
 *   'link_expired'). Legacy 403/404/410 statuses are still classified defensively.
 *
 * Mirrors useMfa / useConnectedIdentities: happy paths validate through a zod
 * schema; useAsyncHandler `wrap` manages the loading state and the unexpected
 * (technical) fallback. Failures are classified INSIDE the operation by reading
 * the axios error's `response` directly (the useMfa 422 pattern) — this is the
 * portable signal in both prod and the mock test harness — and surfaced as a
 * typed errorCode the view branches on.
 */

import {
  linkSsoChallengeResponseSchema,
  linkSsoVerifyResponseSchema,
  isAuthError,
  type LinkSsoChallenge,
  type LinkSsoChallengeResponse,
  type LinkSsoVerifyResponse,
  type LinkSsoVerifySuccess,
} from '@/schemas/api/auth/responses/auth';
import { useApi } from '@/shared/composables/useApi';
import { useAsyncHandler, createError } from '@/shared/composables/useAsyncHandler';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Distinguishes a retryable wrong-password failure from a dead-end token
 * failure (expired / spent / unknown challenge). The view keeps the user on the
 * password form for 'invalid_password' and points them at the settings flow for
 * 'invalid_token'.
 */
export type LinkSsoErrorCode = 'invalid_password' | 'invalid_token' | null;

/** Minimal shape of the axios error's carried response (status + parsed body). */
interface ErrorResponseLike {
  status?: number;
  data?: Record<string, unknown>;
}

/**
 * Maps an HTTP status and an optional backend { error_code } to the UI's typed
 * failure. Prefers the explicit backend code; falls back to the status family
 * (404/410 => spent token, 401/403/422 => wrong password). Returns null when the
 * failure is neither (e.g. a 5xx) so the caller surfaces a generic message.
 */
function resolveLinkErrorCode(
  status: number | undefined,
  backendCode: unknown
): LinkSsoErrorCode {
  if (
    backendCode === 'invalid_token' ||
    backendCode === 'expired_token' ||
    backendCode === 'link_expired' ||
    status === 404 ||
    status === 410
  ) {
    return 'invalid_token';
  }
  if (
    backendCode === 'invalid_password' ||
    status === 401 ||
    status === 403 ||
    status === 422
  ) {
    return 'invalid_password';
  }
  return null;
}

/* eslint-disable max-lines-per-function */
export function useLinkSso() {
  const { t } = useI18n();
  const $api = useApi();
  const csrfStore = useCsrfStore();

  const challenge = ref<LinkSsoChallenge | null>(null);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const errorCode = ref<LinkSsoErrorCode>(null);

  const { wrap } = useAsyncHandler({
    notify: false,
    setLoading: (loading) => (isLoading.value = loading),
    onError: () => {
      // Failures are classified inside the operation (setLinkError). Only fill a
      // generic message for an unexpected throw the operation did not classify
      // (e.g. a zod parse failure) so the view never dead-ends silently.
      if (error.value === null) {
        errorCode.value = null;
        error.value = t('web.link_sso.errors.generic');
      }
    },
  });

  function clearError() {
    error.value = null;
    errorCode.value = null;
  }

  function messageForCode(code: LinkSsoErrorCode): string {
    if (code === 'invalid_token') return t('web.link_sso.errors.invalid_token');
    if (code === 'invalid_password') return t('web.link_sso.errors.invalid_password');
    return t('web.link_sso.errors.generic');
  }

  /**
   * Classifies and stores a failure from the (status, backend error_code) pair.
   * `fallback` lets a caller bias an unclassifiable failure — e.g. any GET of the
   * challenge context that fails at all means there is no usable context, so the
   * fetch biases to 'invalid_token' (dead-end) rather than a generic retry.
   */
  function setLinkError(
    status: number | undefined,
    backendCode: unknown,
    fallback: LinkSsoErrorCode = null
  ): string {
    const code = resolveLinkErrorCode(status, backendCode) ?? fallback;
    errorCode.value = code;
    error.value = messageForCode(code);
    return error.value;
  }

  function readErrorResponse(err: unknown): ErrorResponseLike | undefined {
    return (err as { response?: ErrorResponseLike }).response;
  }

  /**
   * Loads the display context for the challenge token. Returns null on any
   * failure (error/errorCode are set via setLinkError); the view then renders
   * the dead-end state instead of the password form.
   */
  async function fetchChallenge(token: string): Promise<LinkSsoChallenge | null> {
    clearError();

    const result = await wrap(async () => {
      let response;
      try {
        response = await $api.get<LinkSsoChallengeResponse>(
          `/auth/link-sso/${encodeURIComponent(token)}`
        );
      } catch (err) {
        // Any failure to load the context means the token is spent/expired/
        // unknown — bias the dead-end classification to 'invalid_token'.
        const resp = readErrorResponse(err);
        setLinkError(resp?.status, resp?.data?.error_code, 'invalid_token');
        throw err;
      }

      const validated = linkSsoChallengeResponseSchema.parse(response.data);

      // A 200 that still carries an error body is unusual; treat it as a spent
      // token so the view dead-ends rather than showing a broken password form.
      if (isAuthError(validated)) {
        const rawCode = (response.data as Record<string, unknown>)?.error_code;
        setLinkError(response.status, rawCode, 'invalid_token');
        throw createError(t('web.link_sso.errors.invalid_token'), 'human', 'error');
      }

      challenge.value = validated;
      return validated;
    });

    if (!result) {
      challenge.value = null;
    }
    return result ?? null;
  }

  /**
   * Verifies the account's EXISTING password against the challenge token. On
   * success the backend establishes the session and returns the validated
   * response (optionally carrying an internal redirect target); the caller syncs
   * client auth state and navigates. Returns null on failure; the caller reads
   * errorCode to decide retry (invalid_password) vs dead-end (invalid_token).
   */
  async function verifyLink(
    token: string,
    password: string
  ): Promise<LinkSsoVerifySuccess | null> {
    clearError();

    const result = await wrap(async () => {
      let response;
      try {
        response = await $api.post<LinkSsoVerifyResponse>('/auth/link-sso', {
          token,
          password,
          shrimp: csrfStore.shrimp,
        });
      } catch (err) {
        const resp = readErrorResponse(err);
        setLinkError(resp?.status, resp?.data?.error_code);
        throw err;
      }

      const validated = linkSsoVerifyResponseSchema.parse(response.data);

      // Defensive: a 200 carrying an error body. Classify it the same way so the
      // view branches consistently on errorCode.
      if (isAuthError(validated)) {
        const rawCode = (response.data as Record<string, unknown>)?.error_code;
        const message = setLinkError(response.status, rawCode);
        throw createError(message, 'human', 'error');
      }

      return validated;
    });

    return result ?? null;
  }

  return {
    challenge,
    isLoading,
    error,
    errorCode,
    fetchChallenge,
    verifyLink,
    clearError,
  };
}
