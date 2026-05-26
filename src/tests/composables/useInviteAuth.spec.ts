// src/tests/composables/useInviteAuth.spec.ts

/**
 * Tests for the useInviteAuth composable — the authentication flow used
 * during organization invite acceptance.
 *
 * Key behavior under test: signupAndAccept and loginAndAccept must call
 * authStore.setAuthenticated(true) in a fire-and-forget manner (void, not
 * await). Awaiting would yield to the microtask queue, letting Vue flush
 * a re-render that unmounts InviteSignUpForm before emit('success') reaches
 * the parent AcceptInvite view.
 *
 * The source code pattern assertion guards against regression: if someone
 * changes `void authStore.setAuthenticated(true)` back to `await`, the
 * invite flow silently breaks (page refreshes without redirect).
 */

import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useInviteAuth } from '@/apps/session/composables/useInviteAuth';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { readFileSync } from 'fs';
import { dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

// Mock vue-i18n to provide translation function
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
}));

describe('useInviteAuth', () => {
  let axiosMock: AxiosMockAdapter;
  let authStore: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;
  let _csrfStore: ReturnType<typeof useCsrfStore>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;

    authStore = useAuthStore();
    bootstrapStore = useBootstrapStore();
    _csrfStore = useCsrfStore();

    // Stub bootstrap refresh to resolve immediately (CSRF refresh)
    vi.spyOn(bootstrapStore, 'refresh').mockResolvedValue(undefined as any);
  });

  afterEach(() => {
    axiosMock.restore();
    authStore.$reset();
    bootstrapStore.$reset();
    vi.clearAllMocks();
    vi.restoreAllMocks();
  });

  // ── Source code invariant ────────────────────────────────────────────
  // Guards against reverting the fire-and-forget fix. If someone changes
  // `void authStore.setAuthenticated(true)` to `await authStore.setAuthenticated(true)`,
  // the invite onboarding flow silently breaks.

  describe('source code invariants', () => {
    let sourceCode: string;

    beforeEach(() => {
      const filePath = resolve(__dirname, '../../apps/session/composables/useInviteAuth.ts');
      sourceCode = readFileSync(filePath, 'utf-8');
    });

    it('signupAndAccept uses fire-and-forget (not await) for setAuthenticated', () => {
      // Must NOT use `await` — fire-and-forget prevents reactive cascade unmounting form.
      // The .catch() handler surfaces background failures without re-introducing await.
      expect(sourceCode).not.toMatch(/await\s+authStore\.setAuthenticated/);
      expect(sourceCode).toContain('authStore.setAuthenticated(true).catch(');
    });

    it('loginAndAccept uses fire-and-forget (not await) for setAuthenticated', () => {
      // Both methods must use the same fire-and-forget + .catch pattern
      const catchCalls = sourceCode.match(/authStore\.setAuthenticated\(true\)\.catch\(/g);
      expect(catchCalls).toHaveLength(2); // One in signupAndAccept, one in loginAndAccept
    });
  });

  // ── signupAndAccept ──────────────────────────────────────────────────

  describe('signupAndAccept', () => {
    // The new endpoint: POST /api/invite/:token/signup
    // Email is derived from the invite token, not sent in the request body

    it('returns success when server accepts the signup', async () => {
      axiosMock.onPost('/api/invite/invite-token-abc123/signup').reply(200, {});
      axiosMock.onPost('/api/invite/invite-token-abc123/accept').reply(200, {});
      // Mock setAuthenticated to avoid the real implementation side-effects
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept(
        'user@example.com', // Ignored by new endpoint - email comes from token
        'securePassword1',
        true,
        'invite-token-abc123'
      );

      expect(result).toEqual({ success: true });
    });

    // Regression for issue #3221: the signup endpoint leaves the invitation
    // in pending state. The composable must chain POST /api/invite/:token/accept
    // against the established session to complete the join. If this regresses,
    // users land at /orgs with a still-pending invitation and no membership.
    it('POSTs /api/invite/:token/accept after a successful signup', async () => {
      axiosMock.onPost('/api/invite/chain-token/signup').reply(200, {});
      axiosMock.onPost('/api/invite/chain-token/accept').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'chain-token');

      expect(result.success).toBe(true);
      const acceptCall = axiosMock.history.post.find(
        (req) => req.url === '/api/invite/chain-token/accept'
      );
      expect(acceptCall).toBeDefined();
    });

    // /accept failure post-signup is non-fatal: the user is authenticated, and
    // the AcceptInvite page's direct_accept handler will let them retry.
    // signupAndAccept still returns success so the parent view can render the
    // post-signup state.
    it('returns success even when /accept fails after signup', async () => {
      axiosMock.onPost('/api/invite/tok-nf/signup').reply(200, {});
      axiosMock.onPost('/api/invite/tok-nf/accept').reply(404, { error: 'not found' });
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'tok-nf');

      expect(result.success).toBe(true);
    });

    it('calls setAuthenticated(true) on success', async () => {
      axiosMock.onPost('/api/invite/tok123/signup').reply(200, {});
      const spy = vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      await signupAndAccept('user@example.com', 'pw12345678', true, 'tok123');

      expect(spy).toHaveBeenCalledWith(true);
    });

    it('does NOT await setAuthenticated — returns before it resolves', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {});

      // setAuthenticated returns a promise that never resolves during this test
      let setAuthResolved = false;
      vi.spyOn(authStore, 'setAuthenticated').mockImplementation(async () => {
        await new Promise((resolve) => setTimeout(resolve, 5000));
        setAuthResolved = true;
      });

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept('user@example.com', 'pw12345678', true, 'tok');

      // signupAndAccept returned successfully even though setAuthenticated has not resolved
      expect(result).toEqual({ success: true });
      expect(setAuthResolved).toBe(false);
    });

    it('sends password, agree, shrimp in the POST body (not email)', async () => {
      axiosMock.onPost('/api/invite/tok-abc/signup').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      // Note: email and skill params are ignored by the new endpoint
      await signupAndAccept('user@example.com', 'pw12345678', true, 'tok-abc', 'developer');

      const requestData = JSON.parse(axiosMock.history.post[0].data);
      // New endpoint does NOT send login/email - it's derived from the token
      expect(requestData).toMatchObject({
        password: 'pw12345678',
        agree: true,
        locale: 'en',
      });
      // Verify old fields are NOT sent
      expect(requestData).not.toHaveProperty('login');
      expect(requestData).not.toHaveProperty('invite_token');
      expect(requestData).not.toHaveProperty('skill');
    });

    it('refreshes CSRF before posting', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(bootstrapStore.refresh).toHaveBeenCalledOnce();
    });

    it('returns error when server responds with error field', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {
        error: 'Unable to create account',
        'field-error': ['password', 'Password too weak'],
      });

      const { signupAndAccept, error, fieldErrors } = useInviteAuth();
      const result = await signupAndAccept('dup@e.com', 'pw12345678', true, 'tok');

      // accountExists is always returned (false unless error contains "already exists")
      expect(result).toEqual({ success: false, error: 'Unable to create account', accountExists: false });
      expect(error.value).toBe('Unable to create account');
      expect(fieldErrors.value).toEqual({ password: 'Password too weak' });
    });

    it('returns accountExists: true when server indicates account already exists', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {
        error: 'An account already exists with this email',
      });

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept('existing@e.com', 'pw12345678', true, 'tok');

      expect(result.success).toBe(false);
      expect(result.accountExists).toBe(true);
    });

    it('does not call setAuthenticated on server error response', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {
        error: 'Unable to create account',
      });
      const spy = vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(spy).not.toHaveBeenCalled();
    });

    it('returns error on network failure', async () => {
      axiosMock.onPost('/api/invite/tok/signup').networkError();

      const { signupAndAccept, error } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(error.value).toBeDefined();
    });

    it('sets isLoading during the request and clears it after', async () => {
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept, isLoading } = useInviteAuth();

      expect(isLoading.value).toBe(false);
      const promise = signupAndAccept('u@e.com', 'pw12345678', true, 'tok');
      // isLoading is set synchronously at the start
      expect(isLoading.value).toBe(true);
      await promise;
      expect(isLoading.value).toBe(false);
    });

    it('clears isLoading even on error', async () => {
      axiosMock.onPost('/api/invite/tok/signup').networkError();

      const { signupAndAccept, isLoading } = useInviteAuth();
      await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(isLoading.value).toBe(false);
    });

    it('proceeds even if CSRF refresh fails', async () => {
      vi.spyOn(bootstrapStore, 'refresh').mockRejectedValue(new Error('CSRF fail'));
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { signupAndAccept } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(result).toEqual({ success: true });
    });

    it('returns 404 error for invalid/non-existent token', async () => {
      axiosMock.onPost('/api/invite/invalid-tok/signup').reply(404, {
        error: 'Invitation not found or expired',
      });

      const { signupAndAccept, error } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'invalid-tok');

      expect(result.success).toBe(false);
      expect(error.value).toContain('not found');
    });

    it('returns error for expired invitation', async () => {
      axiosMock.onPost('/api/invite/expired-tok/signup').reply(422, {
        error: 'Invitation has expired',
      });

      const { signupAndAccept, error } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'expired-tok');

      expect(result.success).toBe(false);
      expect(error.value).toContain('expired');
    });
  });

  // ── loginAndAccept ───────────────────────────────────────────────────

  describe('loginAndAccept', () => {
    it('returns success when server accepts the login', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});
      axiosMock.onPost('/api/invite/tok-abc/accept').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept } = useInviteAuth();
      const result = await loginAndAccept('user@example.com', 'pw12345678', 'tok-abc');

      expect(result).toEqual({ success: true });
    });

    // Regression for issue #3221: after_login no longer auto-accepts. The
    // composable issues the explicit POST /api/invite/:token/accept so the
    // existing-user flow lands on the same acceptance path as the signup flow.
    it('POSTs /api/invite/:token/accept after a successful login', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});
      axiosMock.onPost('/api/invite/login-chain/accept').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept } = useInviteAuth();
      const result = await loginAndAccept('u@e.com', 'pw12345678', 'login-chain');

      expect(result.success).toBe(true);
      const acceptCall = axiosMock.history.post.find(
        (req) => req.url === '/api/invite/login-chain/accept'
      );
      expect(acceptCall).toBeDefined();
    });

    it('calls setAuthenticated(true) on success', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});
      const spy = vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept } = useInviteAuth();
      await loginAndAccept('u@e.com', 'pw12345678', 'tok');

      expect(spy).toHaveBeenCalledWith(true);
    });

    it('does NOT await setAuthenticated — returns before it resolves', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});

      let setAuthResolved = false;
      vi.spyOn(authStore, 'setAuthenticated').mockImplementation(async () => {
        await new Promise((resolve) => setTimeout(resolve, 5000));
        setAuthResolved = true;
      });

      const { loginAndAccept } = useInviteAuth();
      const result = await loginAndAccept('u@e.com', 'pw12345678', 'tok');

      expect(result).toEqual({ success: true });
      expect(setAuthResolved).toBe(false);
    });

    it('sends invite_token in the POST body', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept } = useInviteAuth();
      await loginAndAccept('user@example.com', 'pw12345678', 'tok-xyz');

      const requestData = JSON.parse(axiosMock.history.post[0].data);
      expect(requestData).toMatchObject({
        login: 'user@example.com',
        password: 'pw12345678',
        invite_token: 'tok-xyz',
        locale: 'en',
      });
    });

    it('returns MFA required when server indicates mfa_required', async () => {
      axiosMock.onPost('/auth/login').reply(200, { mfa_required: true });

      const { loginAndAccept } = useInviteAuth();
      const result = await loginAndAccept('u@e.com', 'pw12345678', 'tok-abc');

      expect(result).toEqual({
        success: false,
        requiresMfa: true,
        redirect: '/invite/tok-abc',
      });
    });

    it('updates bootstrapStore for MFA flow', async () => {
      axiosMock.onPost('/auth/login').reply(200, { mfa_required: true });
      const updateSpy = vi.spyOn(bootstrapStore, 'update');

      const { loginAndAccept } = useInviteAuth();
      await loginAndAccept('u@e.com', 'pw12345678', 'tok');

      expect(updateSpy).toHaveBeenCalledWith({
        awaiting_mfa: true,
        authenticated: false,
      });
    });

    it('does not call setAuthenticated when MFA is required', async () => {
      axiosMock.onPost('/auth/login').reply(200, { mfa_required: true });
      const spy = vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept } = useInviteAuth();
      await loginAndAccept('u@e.com', 'pw12345678', 'tok');

      expect(spy).not.toHaveBeenCalled();
    });

    it('returns error when server responds with error field', async () => {
      axiosMock.onPost('/auth/login').reply(200, {
        error: 'Invalid credentials',
        'field-error': ['password', 'Incorrect password'],
      });

      const { loginAndAccept, error, fieldErrors } = useInviteAuth();
      const result = await loginAndAccept('u@e.com', 'wrong', 'tok');

      expect(result).toEqual({ success: false, error: 'Invalid credentials' });
      expect(error.value).toBe('Invalid credentials');
      expect(fieldErrors.value).toEqual({ password: 'Incorrect password' });
    });

    it('returns error on network failure', async () => {
      axiosMock.onPost('/auth/login').networkError();

      const { loginAndAccept, error } = useInviteAuth();
      const result = await loginAndAccept('u@e.com', 'pw12345678', 'tok');

      expect(result.success).toBe(false);
      expect(error.value).toBeDefined();
    });

    it('sets and clears isLoading', async () => {
      axiosMock.onPost('/auth/login').reply(200, {});
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue(undefined);

      const { loginAndAccept, isLoading } = useInviteAuth();

      expect(isLoading.value).toBe(false);
      const promise = loginAndAccept('u@e.com', 'pw12345678', 'tok');
      expect(isLoading.value).toBe(true);
      await promise;
      expect(isLoading.value).toBe(false);
    });
  });

  // ── clearErrors ──────────────────────────────────────────────────────

  describe('clearErrors', () => {
    it('clears error and fieldErrors state', async () => {
      // Uses the new invite signup endpoint
      axiosMock.onPost('/api/invite/tok/signup').reply(200, {
        error: 'Some error',
        'field-error': ['password', 'Bad password'],
      });

      const { signupAndAccept, clearErrors, error, fieldErrors } = useInviteAuth();
      await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(error.value).toBe('Some error');
      expect(fieldErrors.value).toEqual({ password: 'Bad password' });

      clearErrors();

      expect(error.value).toBeNull();
      expect(fieldErrors.value).toEqual({});
    });
  });

  // ── extractErrorInfo (tested indirectly) ─────────────────────────────

  describe('error extraction', () => {
    it('extracts error from axios error when no response data', async () => {
      // Uses the new invite signup endpoint
      axiosMock.onPost('/api/invite/tok/signup').reply(() => {
        throw { message: 'Request failed', response: undefined };
      });

      const { signupAndAccept, error } = useInviteAuth();
      const result = await signupAndAccept('u@e.com', 'pw12345678', true, 'tok');

      expect(result.success).toBe(false);
      // Should fall back to error.message or default
      expect(error.value).toBeDefined();
    });

    it('extracts error from response data on axios error', async () => {
      axiosMock.onPost('/auth/login').reply(422, {
        error: 'Validation failed',
        'field-error': ['login', 'Email format invalid'],
      });

      const { loginAndAccept, error, fieldErrors } = useInviteAuth();
      const result = await loginAndAccept('bad-email', 'pw12345678', 'tok');

      expect(result.success).toBe(false);
      expect(error.value).toBe('Validation failed');
      expect(fieldErrors.value).toEqual({ login: 'Email format invalid' });
    });
  });
});
