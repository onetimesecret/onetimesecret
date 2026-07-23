// src/tests/composables/useSsoLinkConfirm.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useSsoLinkConfirm } from '@/shared/composables/useSsoLinkConfirm';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';

// Pass-through i18n: keys render as-is so assertions can match on the key.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

// CSRF store: confirmLink includes csrfStore.shrimp in the POST body.
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({ shrimp: 'test-shrimp' }),
}));

/**
 * useSsoLinkConfirm Composable Tests (#3840 Phase 4 — mailbox-proof linking)
 *
 * Verifies the GET display-context fetch and the POST confirm (NO password —
 * mailbox possession is the proof), plus the typed error classification the view
 * branches on. Every failure is terminal; they differ only in the reason:
 * link_expired / link_conflict / link_invalidated / invalid_request — distinguished
 * by the backend { error_code } and, defensively, the HTTP status.
 */
describe('useSsoLinkConfirm', () => {
  let axiosMock: AxiosMockAdapter;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
  });

  describe('fetchPendingLink', () => {
    it('returns the display context on success', async () => {
      axiosMock
        .onGet('/auth/sso-link-confirm/tok123')
        .reply(200, { provider: 'entra', email: 'user@example.com' });

      const { fetchPendingLink, pendingLink, error, errorCode } = useSsoLinkConfirm();
      const result = await fetchPendingLink('tok123');

      expect(result).toEqual({ provider: 'entra', email: 'user@example.com' });
      expect(pendingLink.value).toEqual({ provider: 'entra', email: 'user@example.com' });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('url-encodes the token in the path', async () => {
      axiosMock
        .onGet('/auth/sso-link-confirm/a%2Fb')
        .reply(200, { provider: 'oidc', email: 'a@b.com' });

      const { fetchPendingLink } = useSsoLinkConfirm();
      const result = await fetchPendingLink('a/b');

      expect(result).toEqual({ provider: 'oidc', email: 'a@b.com' });
    });

    it('dead-ends (link_expired) when the token is not found (404)', async () => {
      axiosMock
        .onGet('/auth/sso-link-confirm/gone')
        .reply(404, { error: 'no longer valid', error_code: 'link_expired' });

      const { fetchPendingLink, pendingLink, error, errorCode } = useSsoLinkConfirm();
      const result = await fetchPendingLink('gone');

      expect(result).toBeNull();
      expect(pendingLink.value).toBeNull();
      expect(errorCode.value).toBe('link_expired');
      expect(error.value).toBe('web.sso_link_confirm.errors.link_expired');
    });

    it('treats a 200 error body as a spent token (link_expired)', async () => {
      axiosMock.onGet('/auth/sso-link-confirm/weird').reply(200, { error: 'expired' });

      const { fetchPendingLink, errorCode } = useSsoLinkConfirm();
      const result = await fetchPendingLink('weird');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_expired');
    });

    it('dead-ends (link_expired) on an unexpected server error (500)', async () => {
      axiosMock.onGet('/auth/sso-link-confirm/boom').reply(500, { error: 'failed to load' });

      const { fetchPendingLink, errorCode } = useSsoLinkConfirm();
      const result = await fetchPendingLink('boom');

      // Any GET failure means no usable context; the fetch biases to link_expired.
      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_expired');
    });
  });

  describe('confirmLink', () => {
    it('returns the success body (with redirect) on 200', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(200, { success: 'linked', redirect: '/dashboard' });

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toEqual({ success: 'linked', redirect: '/dashboard' });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('accepts a success body without a redirect target', async () => {
      axiosMock.onPost('/auth/sso-link-confirm').reply(200, { success: 'linked' });

      const { confirmLink } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toEqual({ success: 'linked' });
    });

    it('sends the token and shrimp — and NO password', async () => {
      axiosMock.onPost('/auth/sso-link-confirm').reply(200, { success: 'linked' });

      const { confirmLink } = useSsoLinkConfirm();
      await confirmLink('tok123');

      const body = JSON.parse(axiosMock.history.post[0].data);
      expect(body).toEqual({ token: 'tok123', shrimp: 'test-shrimp' });
      expect(body).not.toHaveProperty('password');
    });

    it('classifies a missing token (400 invalid_request)', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(400, { error: 'token required', error_code: 'invalid_request' });

      const { confirmLink, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('invalid_request');
    });

    it('classifies a spent/expired token (401 link_expired)', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(401, { error: 'expired', error_code: 'link_expired' });

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_expired');
      expect(error.value).toBe('web.sso_link_confirm.errors.link_expired');
    });

    it('classifies an account/identity conflict (409 link_conflict)', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(409, { error: 'could not complete', error_code: 'link_conflict' });

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_conflict');
      expect(error.value).toBe('web.sso_link_confirm.errors.link_conflict');
    });

    // A watermark-advancing credential change and a plain conflict are both 409;
    // the explicit error_code is what disambiguates them (status alone can't).
    it('classifies a credential change (409 link_invalidated) via error_code', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(409, { error: 'credentials changed', error_code: 'link_invalidated' });

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_invalidated');
      expect(error.value).toBe('web.sso_link_confirm.errors.link_invalidated');
    });

    // MFA account: the backend returns the SAME body POST /auth/login returns for
    // MFA. The schema must NOT strip mfa_required (else the view would mark the
    // user fully authenticated and skip the OTP challenge).
    it('preserves mfa_required (does not strip it) on a 200 MFA response', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(200, { success: 'ok', mfa_required: true, mfa_methods: ['otp'] });

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toMatchObject({
        success: 'ok',
        mfa_required: true,
        mfa_methods: ['otp'],
      });
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });

    it('treats a 200 error body carrying link_conflict as classified', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(200, { error: 'stale', error_code: 'link_conflict' });

      const { confirmLink, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toBeNull();
      expect(errorCode.value).toBe('link_conflict');
    });

    it('falls back to a generic error for an unclassifiable failure (500)', async () => {
      axiosMock.onPost('/auth/sso-link-confirm').reply(500);

      const { confirmLink, error, errorCode } = useSsoLinkConfirm();
      const result = await confirmLink('tok123');

      expect(result).toBeNull();
      expect(errorCode.value).toBeNull();
      expect(error.value).toBe('web.sso_link_confirm.errors.generic');
    });
  });

  describe('clearError', () => {
    it('resets both error and errorCode', async () => {
      axiosMock
        .onPost('/auth/sso-link-confirm')
        .reply(409, { error: 'nope', error_code: 'link_conflict' });

      const { confirmLink, clearError, error, errorCode } = useSsoLinkConfirm();
      await confirmLink('tok123');
      expect(error.value).not.toBeNull();
      expect(errorCode.value).toBe('link_conflict');

      clearError();
      expect(error.value).toBeNull();
      expect(errorCode.value).toBeNull();
    });
  });
});
