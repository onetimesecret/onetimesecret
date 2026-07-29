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
 *                               400 invalid_request   => token or password missing from the
 *                                                       body. The view's guards prevent this
 *                                                       (empty token dead-ends on mount, empty
 *                                                       password blocks submit); classified so
 *                                                       a crafted or buggy submit never reads
 *                                                       as a wrong password
 *                               401 invalid_password  => wrong password (retryable)
 *                               401 link_expired      => token expired / consumed (dead-end)
 *                               409 link_conflict     => the email re-resolved to a different
 *                                                       account since mint, or the
 *                                                       (provider,issuer,uid) is already bound
 *                                                       elsewhere (dead-end — retry can never
 *                                                       succeed)
 *                               429 link_rate_limited => too many password attempts for this
 *                                                       account/IP; refused BEFORE consuming
 *                                                       the token, so waiting and retrying can
 *                                                       succeed — but the view must NOT invite
 *                                                       an immediate retry
 *   The failure branch is distinguished by an { error_code } field
 *   ('invalid_request' / 'link_expired' / 'invalid_password' / 'link_conflict' /
 *   'link_rate_limited' — the exact set apps/web/auth/routes/link_sso.rb emits;
 *   keep in lockstep with that route) and, defensively, the HTTP status family.
 *   'invalid_token' / 'expired_token' are frontend-side legacy aliases (no Ruby
 *   route emits them) kept in the resolver as defence.
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
 * Typed failure the view branches on:
 * - 'invalid_password'  — wrong password; the view keeps the user on the form
 *                         for another try.
 * - 'invalid_token'     — dead-end token failure (expired / spent / unknown
 *                         challenge); the view points at the settings flow.
 * - 'link_conflict'     — dead-end: the account moved or the identity is bound
 *                         to a different account. Terminal — a retry against
 *                         this challenge can never succeed, so the view must
 *                         NOT re-offer the password form.
 * - 'link_rate_limited' — too many attempts; the backend refused BEFORE
 *                         consuming the token, so waiting and retrying can
 *                         succeed. The copy says "wait" — the view must not
 *                         clear/refocus the password field, which would invite
 *                         an immediate retry that re-trips the throttle.
 * - 'invalid_request'   — malformed submit (token or password missing from the
 *                         body). Unreachable via the view's guards; classified
 *                         so a crafted or buggy request is never presented as
 *                         a wrong password (no field clear/refocus).
 */
export type LinkSsoErrorCode =
  | 'invalid_password'
  | 'invalid_token'
  | 'link_conflict'
  | 'link_rate_limited'
  | 'invalid_request'
  | null;

/** Minimal shape of the axios error's carried response (status + parsed body). */
interface ErrorResponseLike {
  status?: number;
  data?: Record<string, unknown>;
}

const BACKEND_CODE_MAP: Record<string, NonNullable<LinkSsoErrorCode>> = {
  invalid_password: 'invalid_password',
  link_conflict: 'link_conflict',
  link_rate_limited: 'link_rate_limited',
  invalid_request: 'invalid_request',
  link_expired: 'invalid_token',
  // Frontend-side legacy aliases — no backend route emits these; defence only.
  invalid_token: 'invalid_token',
  expired_token: 'invalid_token',
};

const STATUS_FAMILY_MAP: Record<number, NonNullable<LinkSsoErrorCode>> = {
  400: 'invalid_request',
  404: 'invalid_token',
  410: 'invalid_token',
  409: 'link_conflict',
  429: 'link_rate_limited',
  401: 'invalid_password',
  403: 'invalid_password',
  422: 'invalid_password',
};

/**
 * Maps an HTTP status and an optional backend { error_code } to the UI's typed
 * failure. The explicit backend code is checked FIRST — before any status-family
 * fallback — so a specific code arriving on a shared status can never be
 * shadowed (mirrors useSsoLinkConfirm's resolver after #3882). The status
 * families (400 => malformed request, 404/410 => spent token, 409 => conflict,
 * 429 => rate limited, 401/403/422 => wrong password) are defence for a
 * code-less response. Returns null when the failure is neither (e.g. a 5xx)
 * so the caller surfaces a generic message.
 */
function resolveLinkErrorCode(
  status: number | undefined,
  backendCode: unknown
): LinkSsoErrorCode {
  if (typeof backendCode === 'string' && backendCode in BACKEND_CODE_MAP) {
    return BACKEND_CODE_MAP[backendCode];
  }
  if (status !== undefined && status in STATUS_FAMILY_MAP) {
    return STATUS_FAMILY_MAP[status];
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
    if (code === 'link_conflict') return t('web.link_sso.errors.link_conflict');
    if (code === 'link_rate_limited') return t('web.link_sso.errors.link_rate_limited');
    if (code === 'invalid_request') return t('web.link_sso.errors.invalid_request');
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
