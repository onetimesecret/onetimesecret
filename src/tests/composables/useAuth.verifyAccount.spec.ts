// src/tests/composables/useAuth.verifyAccount.spec.ts

/**
 * verifyAccount() — the last hop of the signup journey.
 *
 * Account verification is the point where `?redirect=` used to die: the old
 * implementation pushed a bare { path: '/signin', state: { verified } } and
 * dropped whatever the user was originally trying to reach. Two sources can
 * supply the destination here, in this order:
 *
 *   1. the verify-account RESPONSE — the redirect the backend validated and
 *      stored at signup. This is the one that matters, because the
 *      verification link is opened from a mail client (often in a different
 *      browser), so the original query string is usually gone;
 *   2. a `?redirect=` still on the verification URL.
 *
 * Both are re-validated with isValidInternalPath — a server-supplied path is
 * not trusted blindly — and the destination rides in the QUERY so it survives
 * a fresh entry. The one-shot "just verified" flag keeps riding history STATE
 * (SIGNIN_VERIFIED_STATE_KEY) so Login.vue can clear it without remounting the
 * fullPath-keyed router-view. Both must be present together.
 *
 * Billing/plan intent outranks redirect, and the BACKEND applies that
 * precedence before answering — a response carrying a plan intent simply omits
 * `redirect`. There is nothing to assert here beyond "we use what we're given".
 */

import { SIGNIN_VERIFIED_STATE_KEY } from '@/shared/constants/signin';
import { useAuth } from '@/shared/composables/useAuth';
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

describe('useAuth - verifyAccount redirect preservation', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };

  /** The history-state flag that must survive every branch below. */
  const verifiedState = { state: { [SIGNIN_VERIFIED_STATE_KEY]: true } };

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.shrimp = 'test-shrimp-token';

    mockRoute = { query: {} };
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as never);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  /** Reply to the verify-account POST with an arbitrary success body. */
  function replyWith(body: Record<string, unknown>) {
    axiosMock.onPost('/auth/verify-account').reply(200, body);
  }

  describe('response-supplied redirect (the signup → email → verify journey)', () => {
    it('carries the response redirect into the /signin query', async () => {
      replyWith({ success: 'Your account has been verified', redirect: '/dashboard/settings' });

      const { verifyAccount } = useAuth();
      expect(await verifyAccount('verify-key-123')).toBe(true);

      expect(router.push).toHaveBeenCalledWith({
        path: '/signin',
        query: { redirect: '/dashboard/settings' },
        ...verifiedState,
      });
    });

    it('preserves the query string and hash of the stored redirect', async () => {
      replyWith({ success: 'Verified', redirect: '/secret/abc?view=raw#content' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/signin',
        query: { redirect: '/secret/abc?view=raw#content' },
        ...verifiedState,
      });
    });

    it('outranks a ?redirect still present on the verification URL', async () => {
      // Precedence: the stored value is the one the backend validated at
      // signup; a param on this URL is only the fallback.
      mockRoute.query = { redirect: '/from-the-url' };
      replyWith({ success: 'Verified', redirect: '/from-the-response' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/signin',
        query: { redirect: '/from-the-response' },
        ...verifiedState,
      });
    });
  });

  describe('query fallback', () => {
    it('uses ?redirect from the verification URL when the response omits one', async () => {
      mockRoute.query = { redirect: '/workspace/domains' };
      replyWith({ success: 'Verified' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/signin',
        query: { redirect: '/workspace/domains' },
        ...verifiedState,
      });
    });

    it('falls back to the query when the RESPONSE redirect is not a safe internal path', async () => {
      // A server-supplied path is re-validated, never trusted blindly.
      mockRoute.query = { redirect: '/workspace/domains' };
      replyWith({ success: 'Verified', redirect: 'https://evil.example/phish' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/signin',
        query: { redirect: '/workspace/domains' },
        ...verifiedState,
      });
    });
  });

  describe('invalid values are dropped', () => {
    const hostile = [
      ['protocol-relative', '//evil.example/phish'],
      ['absolute URL', 'https://evil.example/phish'],
      ['backslash authority', '/\\evil.example'],
      ['encoded traversal', '/%2e%2e/admin'],
      ['CRLF injection', '/x%0D%0ASet-Cookie:%20a=b'],
      ['over-length', '/' + 'a'.repeat(2048)],
    ] as const;

    it.each(hostile)('drops a %s redirect from the response', async (_label, value) => {
      replyWith({ success: 'Verified', redirect: value });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({ path: '/signin', ...verifiedState });
    });

    it.each(hostile)('drops a %s redirect from the query', async (_label, value) => {
      mockRoute.query = { redirect: value };
      replyWith({ success: 'Verified' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({ path: '/signin', ...verifiedState });
    });

    it('ignores a repeated ?redirect (array-valued query param)', async () => {
      // vue-router surfaces ?redirect=a&redirect=b as an array; only a single
      // string is a redirect target.
      mockRoute.query = { redirect: ['/a', '/b'] as unknown as string };
      replyWith({ success: 'Verified' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      expect(router.push).toHaveBeenCalledWith({ path: '/signin', ...verifiedState });
    });
  });

  describe('no redirect in play', () => {
    it('pushes a plain /signin, still carrying the verified flag', async () => {
      replyWith({ success: 'Your account has been verified' });

      const { verifyAccount } = useAuth();
      expect(await verifyAccount('verify-key-123')).toBe(true);

      expect(router.push).toHaveBeenCalledWith({ path: '/signin', ...verifiedState });
    });

    it('never puts the verified flag in the URL', async () => {
      mockRoute.query = { redirect: '/dashboard' };
      replyWith({ success: 'Verified', redirect: '/dashboard' });

      const { verifyAccount } = useAuth();
      await verifyAccount('verify-key-123');

      const target = vi.mocked(router.push).mock.calls[0][0] as {
        query?: Record<string, unknown>;
      };
      expect(target.query).toEqual({ redirect: '/dashboard' });
      expect(target.query).not.toHaveProperty(SIGNIN_VERIFIED_STATE_KEY);
      expect(target.query).not.toHaveProperty('verified');
    });
  });

  describe('failure', () => {
    it('does not navigate when verification fails', async () => {
      axiosMock.onPost('/auth/verify-account').reply(200, {
        error: 'invalid verification key',
      });

      const { verifyAccount, error } = useAuth();
      expect(await verifyAccount('bad-key')).toBe(false);

      expect(router.push).not.toHaveBeenCalled();
      expect(error.value).toBe('invalid verification key');
    });
  });
});
