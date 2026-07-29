// src/tests/composables/useLinkSso.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useLinkSso } from '@/shared/composables/useLinkSso';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';

// Pass-through i18n: keys render as-is so assertions can match on the key.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

// CSRF store: verifyLink includes csrfStore.shrimp in the POST body.
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({ shrimp: 'test-shrimp' }),
}));

/**
 * useLinkSso Composable Tests (#3840 Phase 3 — sign-in interstitial)
 *
 * Verifies the GET challenge-context fetch and POST password verify, plus the
 * typed error classification the view branches on:
 * - invalid_password (retryable) vs invalid_token / link_conflict (dead-end)
 *   vs link_rate_limited (throttled; token still live — wait and retry)
 * - distinguished by an explicit backend { error_code } first, then the HTTP
 *   status family as defence (so a specific code on a shared status is never
 *   shadowed)
 */
describe('useLinkSso', () => {
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
  });

  describe('fetchChallenge', () => {
    it('returns the display context on success', async () => {
      axiosMock
        .onGet('/auth/link-sso/tok123')
        .reply(200, { provider: 'entra', email: 'user@example.com' });

      const { fetchChallenge, challenge, error, errorCode } = useLinkSso();
      const result = await fetchChallenge('tok123');

      expect(result).toEqual({ provider: 'entra', email: 'user@example.com' });
      expect(challenge.value).toEqual({ provider: 'entra', email: 'user@example.com' });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('url-encodes the token in the path', async () => {
      axiosMock.onGet('/auth/link-sso/a%2Fb').reply(200, { provider: 'oidc', email: 'a@b.com' });

      const { fetchChallenge } = useLinkSso();
      const result = await fetchChallenge('a/b');

      expect(result).toEqual({ provider: 'oidc', email: 'a@b.com' });
    });

    it('dead-ends (invalid_token) when the token is not found (404)', async () => {
      axiosMock.onGet('/auth/link-sso/gone').reply(404, { error: 'not found' });

      const { fetchChallenge, challenge, error, errorCode } = useLinkSso();
      const result = await fetchChallenge('gone');

      expect(result).toBeNull();
      expect(challenge.value).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
      expect(error.value).toBe('web.link_sso.errors.invalid_token');
    });

    it('dead-ends (invalid_token) when the token is gone (410)', async () => {
      axiosMock.onGet('/auth/link-sso/spent').reply(410, { error: 'gone' });

      const { fetchChallenge, errorCode } = useLinkSso();
      const result = await fetchChallenge('spent');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
    });

    it('treats a 200 error body as a spent token', async () => {
      axiosMock.onGet('/auth/link-sso/weird').reply(200, { error: 'expired' });

      const { fetchChallenge, errorCode } = useLinkSso();
      const result = await fetchChallenge('weird');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
    });
  });

  describe('verifyLink', () => {
    it('returns the success body (with redirect) on 200', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(200, { success: 'linked', redirect: '/dashboard' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'correct-password');

      expect(result).toEqual({ success: 'linked', redirect: '/dashboard' });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('accepts a success body without a redirect target', async () => {
      axiosMock.onPost('/auth/link-sso').reply(200, { success: 'linked' });

      const { verifyLink } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toEqual({ success: 'linked' });
    });

    it('sends the token, password, and shrimp', async () => {
      axiosMock.onPost('/auth/link-sso').reply(200, { success: 'linked' });

      const { verifyLink } = useLinkSso();
      await verifyLink('tok123', 'sekret');

      const body = JSON.parse(axiosMock.history.post[0].data);
      expect(body).toEqual({ token: 'tok123', password: 'sekret', shrimp: 'test-shrimp' });
    });

    it('classifies a wrong password (403) as invalid_password (retryable)', async () => {
      axiosMock.onPost('/auth/link-sso').reply(403, { error: 'invalid credentials' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'wrong');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_password');
      expect(error.value).toBe('web.link_sso.errors.invalid_password');
    });

    it('honors an explicit error_code (invalid_password) over the status', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(401, { error: 'nope', error_code: 'invalid_password' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'wrong');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_password');
    });

    it('classifies an expired token (410) as invalid_token (dead-end)', async () => {
      axiosMock.onPost('/auth/link-sso').reply(410, { error: 'expired' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
      expect(error.value).toBe('web.link_sso.errors.invalid_token');
    });

    // Backend returns 401 (not 404/410) with error_code 'link_expired' for a
    // consumed/expired token. Without the explicit code mapping the 401 would
    // fall through to invalid_password (retryable) — but the token is single-use,
    // so a retry can never succeed. It MUST dead-end.
    it('classifies a spent token (401 link_expired) as invalid_token (dead-end)', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(401, { error: 'expired', error_code: 'link_expired' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
      expect(error.value).toBe('web.link_sso.errors.invalid_token');
    });

    // MFA account: the backend returns the SAME body POST /auth/login returns for
    // MFA. The schema must NOT strip mfa_required (else the view would mark the
    // user fully authenticated and skip the OTP challenge).
    it('preserves mfa_required (does not strip it) on a 200 MFA response', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(200, { success: 'ok', mfa_required: true, mfa_methods: ['otp'] });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'correct-password');

      expect(result).toMatchObject({
        success: 'ok',
        mfa_required: true,
        mfa_methods: ['otp'],
      });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('honors an explicit error_code (invalid_token) on a 403', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(403, { error: 'stale', error_code: 'invalid_token' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
    });

    it('treats a 200 error body carrying invalid_token as a dead-end', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(200, { error: 'stale', error_code: 'invalid_token' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
    });

    // Backend emits 409 link_conflict when the account was re-emailed between
    // challenge mint and POST, or the (provider,issuer,uid) is already bound to
    // a different account. Terminal — without the mapping it fell through to
    // null and the view treated it as a retryable password error (#3889).
    it('classifies a conflict (409 link_conflict) as link_conflict (dead-end)', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(409, { error: 'conflict', error_code: 'link_conflict' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_conflict');
      expect(error.value).toBe('web.link_sso.errors.link_conflict');
    });

    it('falls back to link_conflict for a code-less 409', async () => {
      axiosMock.onPost('/auth/link-sso').reply(409, { error: 'conflict' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_conflict');
    });

    // Backend emits 429 link_rate_limited when the per-account/IP throttle
    // trips — BEFORE consuming the token, so the challenge is still live.
    // Without the mapping it fell through to null (generic copy) and the view
    // handed back a focused password field, immediately re-tripping the
    // throttle (#3889).
    it('classifies a throttle (429 link_rate_limited) as link_rate_limited', async () => {
      axiosMock.onPost('/auth/link-sso').reply(429, {
        error: 'Too many attempts. Please try again later.',
        error_code: 'link_rate_limited',
        retry_after: 60,
      });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_rate_limited');
      expect(error.value).toBe('web.link_sso.errors.link_rate_limited');
    });

    it('falls back to link_rate_limited for a code-less 429', async () => {
      axiosMock.onPost('/auth/link-sso').reply(429, { error: 'slow down' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_rate_limited');
    });

    // Backend emits 400 invalid_request when token/password are missing from
    // the body. The view's guards make that unreachable, but a crafted or
    // buggy submit must never be classified as a wrong password and invited
    // to retry (PR #3936 review).
    it('classifies a malformed submit (400 invalid_request) as invalid_request', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(400, { error: 'Token and password are required.', error_code: 'invalid_request' });

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_request');
      expect(error.value).toBe('web.link_sso.errors.invalid_request');
    });

    it('falls back to invalid_request for a code-less 400', async () => {
      axiosMock.onPost('/auth/link-sso').reply(400, { error: 'bad request' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_request');
    });

    // Ordering guard: the explicit code must be checked BEFORE the status-family
    // fallback, so a specific code arriving on a shared status is never
    // shadowed (mirrors the useSsoLinkConfirm resolver after #3882).
    it('honors an explicit error_code (link_expired) over a 409 status', async () => {
      axiosMock
        .onPost('/auth/link-sso')
        .reply(409, { error: 'expired', error_code: 'link_expired' });

      const { verifyLink, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_token');
    });

    it('falls back to a generic error for an unclassifiable failure (500)', async () => {
      axiosMock.onPost('/auth/link-sso').reply(500);

      const { verifyLink, error, errorCode } = useLinkSso();
      const result = await verifyLink('tok123', 'pw');

      expect(result).toBeNull();
      expect(errorCode.value).toBeNull();
      expect(error.value).toBe('web.link_sso.errors.generic');
    });
  });

  describe('clearError', () => {
    it('resets both error and errorCode', async () => {
      axiosMock.onPost('/auth/link-sso').reply(403, { error: 'nope' });

      const { verifyLink, clearError, error, errorCode } = useLinkSso();
      await verifyLink('tok123', 'wrong');
      expect(error.value).not.toBeNull();
      expect(errorCode.value).toBe('invalid_password');

      clearError();
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });
  });
});
