// src/tests/composables/useAuth.signup.spec.ts

/**
 * signup() — the FIRST link of the redirect-preservation chain (#4305).
 *
 * The validated ?redirect must travel in the create-account POST BODY: the
 * backend stores it (pending_auth_redirect) and replays it from the
 * verify-account response, which is what lets the destination survive the
 * verification link being opened in a different browser session. The E2E
 * journey found this exact link missing once — the whole downstream chain was
 * wired while the POST silently sent nothing — so this spec pins the request
 * body, not just the navigation.
 */

import { useAuth } from '@/shared/composables/useAuth';
import { CHECK_EMAIL_STATE_KEY } from '@/shared/constants/checkEmail';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';
import { setupTestPinia } from '../setup';

// Mock vue-router - must be before any imports that use it
vi.mock('vue-router');

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

describe('useAuth - signup sends the redirect to the backend', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.shrimp = 'test-shrimp-token';

    mockRoute = { query: {} };
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as never);

    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created',
      next_action: 'verify_email',
    });
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  /** The JSON body of the (single) create-account POST. */
  function postedBody(): Record<string, unknown> {
    expect(axiosMock.history.post).toHaveLength(1);
    return JSON.parse(axiosMock.history.post[0].data as string);
  }

  it('puts a validated ?redirect in the POST body', async () => {
    mockRoute.query = { redirect: '/secret/abc?view=raw#content' };

    const { signup } = useAuth();
    expect(await signup('user@example.com', 'a-strong-passphrase')).toBe(true);

    expect(postedBody()).toMatchObject({
      login: 'user@example.com',
      redirect: '/secret/abc?view=raw#content',
    });
  });

  it('omits the key entirely when no redirect is present', async () => {
    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(postedBody()).not.toHaveProperty('redirect');
  });

  it.each([
    ['absolute URL', 'https://attacker.example'],
    ['protocol-relative', '//evil.example'],
    ['backslash authority', '/\\evil.example'],
  ] as const)('drops a %s redirect instead of sending it', async (_label, value) => {
    mockRoute.query = { redirect: value };

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(postedBody()).not.toHaveProperty('redirect');
  });

  it('sends billing params and redirect side by side', async () => {
    mockRoute.query = { product: 'identity_plus_v1', interval: 'year', redirect: '/pricing' };

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(postedBody()).toMatchObject({
      product: 'identity_plus_v1',
      interval: 'year',
      redirect: '/pricing',
    });
  });

  it('carries the redirect onto the /check-email query as well', async () => {
    // Same-session belt to the server-side suspenders: /check-email links the
    // user back to /signup with the redirect intact if they start over.
    mockRoute.query = { redirect: '/workspace/domains' };

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(router.push).toHaveBeenCalledWith(
      expect.objectContaining({
        path: '/check-email',
        query: { redirect: '/workspace/domains' },
      })
    );
  });

  it('routes verification-disabled signup to sign-in', async () => {
    axiosMock.resetHandlers();
    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created',
      next_action: 'sign_in',
    });

    const { signup } = useAuth();
    expect(await signup('user@example.com', 'a-strong-passphrase')).toBe(true);

    expect(router.push).toHaveBeenCalledWith({ path: '/signin' });
  });

  it('carries validated checkout and redirect context through sign-in', async () => {
    mockRoute.query = {
      product: 'untrusted-product',
      interval: 'untrusted-interval',
      redirect: '/account/settings/security',
    };
    axiosMock.resetHandlers();
    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created',
      next_action: 'sign_in',
      billing_redirect: {
        product: 'identity_plus_v1',
        interval: 'monthly',
        valid: true,
      },
    });

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(router.push).toHaveBeenCalledWith({
      path: '/signin',
      query: {
        product: 'identity_plus_v1',
        interval: 'monthly',
        redirect: '/account/settings/security',
      },
    });
  });

  it('drops the submitted plan pair when the server marks it invalid', async () => {
    mockRoute.query = {
      product: 'retired-plan',
      interval: 'monthly',
      redirect: '/pricing',
    };
    axiosMock.resetHandlers();
    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created',
      next_action: 'sign_in',
      billing_redirect: {
        product: 'retired-plan',
        interval: 'monthly',
        valid: false,
      },
    });

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(router.push).toHaveBeenCalledWith({
      path: '/signin',
      query: { redirect: '/pricing' },
    });
  });

  it('keeps the submitted plan pair when the server sends no billing_redirect', async () => {
    // Simple mode, and full mode without billing, answer with no verdict on
    // the plan. The login response validates the pair before checkout.
    mockRoute.query = { product: 'identity_plus_v1', interval: 'yearly' };
    axiosMock.resetHandlers();
    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created',
      next_action: 'sign_in',
    });

    const { signup } = useAuth();
    await signup('user@example.com', 'a-strong-passphrase');

    expect(router.push).toHaveBeenCalledWith({
      path: '/signin',
      query: { product: 'identity_plus_v1', interval: 'yearly' },
    });
  });

  it('routes verify_email to /check-email with the email in history state, not the URL', async () => {
    // beforeEach answers next_action 'verify_email'.
    mockRoute.query = { redirect: '/workspace/domains' };

    const { signup } = useAuth();
    expect(await signup('user@example.com', 'a-strong-passphrase')).toBe(true);

    expect(router.push).toHaveBeenCalledTimes(1);
    expect(router.push).toHaveBeenCalledWith({
      path: '/check-email',
      query: { redirect: '/workspace/domains' },
      state: { [CHECK_EMAIL_STATE_KEY]: 'user@example.com' },
    });
  });
});
