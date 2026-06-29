// src/tests/composables/useAuth.resendVerification.spec.ts

/**
 * Tests for the resendVerificationEmail method in the useAuth composable.
 *
 * This covers the self-service "resend verification email" recovery flow for
 * Unverified accounts that cannot log in (no session). The endpoint is
 * unauthenticated and parameterized by `login` (email).
 *
 * FROZEN CROSS-TRACK CONTRACT:
 *   - Endpoint: POST /api/account/resend-verification-email (auth=noauth, json)
 *   - Request body: { login, shrimp, locale }
 *   - Success: HTTP 200, body EXACTLY { sent: true } for EVERY account state
 *     (nonexistent / verified / unverified-just-sent / throttled / internal error).
 *   - ANTI-ENUMERATION: body + status are byte-identical across all account
 *     states; the only observable difference is server-side logging. So the
 *     composable must resolve `true` for any accepted, well-formed request and
 *     must NOT reveal whether the email exists or was actually sent.
 *   - ONLY malformed requests (blank/missing login, bad CSRF) may be non-200,
 *     surfaced to the client as an auth-error body { error: '...' }.
 *
 * These tests verify that resendVerificationEmail():
 * 1. Makes the correct API call to the agreed endpoint path.
 * 2. Sends the expected payload (login, shrimp, locale).
 * 3. Returns true on the uniform { sent: true } success response.
 * 4. Returns false and sets error on an auth-error body { error: '...' }.
 * 5. Handles network and 5xx failures gracefully.
 *
 * Mirrors: src/tests/composables/useAuth.emailChange.spec.ts
 */

import { useAuth } from '@/shared/composables/useAuth';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';
import { setupTestPinia } from '../setup';

// Mock vue-router
vi.mock('vue-router');

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
}));

// Mock logging service
vi.mock('@/services/logging.service', () => ({
  loggingService: {
    debug: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

const ENDPOINT = '/api/account/resend-verification-email';

describe('useAuth - resendVerificationEmail', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Wire up vue-router mocks
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue({ query: {} } as any);

    // Set up CSRF store with a shrimp token
    const csrfStore = useCsrfStore();
    csrfStore.shrimp = 'test-shrimp';
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  it('returns true on the uniform { sent: true } success response', async () => {
    axiosMock.onPost(ENDPOINT).reply(200, { sent: true });

    const { resendVerificationEmail } = useAuth();
    const result = await resendVerificationEmail('a@example.com');

    expect(result).toBe(true);
  });

  it('posts to the agreed endpoint path', async () => {
    axiosMock.onPost(ENDPOINT).reply(200, { sent: true });

    const { resendVerificationEmail } = useAuth();
    await resendVerificationEmail('a@example.com');

    expect(axiosMock.history.post).toHaveLength(1);
    expect(axiosMock.history.post[0].url).toBe(ENDPOINT);
  });

  it('sends correct payload with login, shrimp, and locale', async () => {
    axiosMock.onPost(ENDPOINT).reply(200, { sent: true });

    const { resendVerificationEmail } = useAuth();
    await resendVerificationEmail('a@example.com');

    const requestData = JSON.parse(axiosMock.history.post[0].data);
    expect(requestData.login).toBe('a@example.com');
    expect(requestData.shrimp).toBe('test-shrimp');
    expect(requestData.locale).toBe('en');
  });

  it('does not leak whether the email exists (uniform success regardless of input)', async () => {
    // Anti-enumeration: backend returns identical { sent: true } for every
    // account state, so the composable resolves true for any accepted request.
    axiosMock.onPost(ENDPOINT).reply(200, { sent: true });

    const { resendVerificationEmail, error } = useAuth();

    expect(await resendVerificationEmail('nonexistent@example.com')).toBe(true);
    expect(await resendVerificationEmail('verified@example.com')).toBe(true);
    expect(await resendVerificationEmail('unverified@example.com')).toBe(true);
    expect(error.value).toBeNull();
  });

  it('returns false and sets error on an auth-error body', async () => {
    // Only malformed requests (blank/missing login, bad CSRF) may surface an
    // error body. The endpoint still replies 200 with { error: '...' }.
    axiosMock.onPost(ENDPOINT).reply(200, { error: 'Email is required' });

    const { resendVerificationEmail, error } = useAuth();
    const result = await resendVerificationEmail('');

    expect(result).toBe(false);
    expect(error.value).toBe('Email is required');
  });

  it('populates fieldError from a field-error tuple', async () => {
    axiosMock.onPost(ENDPOINT).reply(200, {
      error: 'Validation failed',
      'field-error': ['login', 'is not a valid email'],
    });

    const { resendVerificationEmail, fieldError } = useAuth();
    await resendVerificationEmail('bad-email');

    expect(fieldError.value).toEqual(['login', 'is not a valid email']);
  });

  it('returns false on network error', async () => {
    axiosMock.onPost(ENDPOINT).networkError();

    const { resendVerificationEmail } = useAuth();
    const result = await resendVerificationEmail('a@example.com');

    expect(result).toBe(false);
  });

  it('returns false on server 500 error', async () => {
    axiosMock.onPost(ENDPOINT).reply(500, { error: 'Internal server error' });

    const { resendVerificationEmail } = useAuth();
    const result = await resendVerificationEmail('a@example.com');

    expect(result).toBe(false);
  });

  it('clears previous errors before making request', async () => {
    // First call fails with an error body
    axiosMock.onPost(ENDPOINT).replyOnce(200, { error: 'Email is required' });

    const { resendVerificationEmail, error } = useAuth();
    await resendVerificationEmail('');
    expect(error.value).toBe('Email is required');

    // Second call succeeds - error should be cleared
    axiosMock.onPost(ENDPOINT).replyOnce(200, { sent: true });

    await resendVerificationEmail('a@example.com');
    expect(error.value).toBeNull();
  });
});
