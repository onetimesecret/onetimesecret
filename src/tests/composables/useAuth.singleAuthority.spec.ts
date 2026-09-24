// src/tests/composables/useAuth.singleAuthority.spec.ts
//
// Regression suite for ADR-046#auth-completion-caller-contract.
//
// Corrects the pre-#4497 bug where a caller finished a first-factor auth POST,
// then blindly router.push()'d to /mfa-verify or Dashboard regardless of what
// the follow-up /bootstrap/me refresh reported. A 'failed' / 'refused' /
// 'superseded' refresh outcome now blocks navigation:
//
//   - 'superseded': success-by-delegation, no-op — a newer coordinator run
//     owns the outcome.
//   - 'failed' / 'refused': retry verification (never the auth POST) and, if
//     still not applied, surface a retryable local error.
//   - 'applied' but status not matching destination: surface an error.
//
// This suite mocks authStore.refresh directly so the coordinator internals
// stay orthogonal to the caller contract under test.

import { useAuth } from '@/shared/composables/useAuth';
import { useAuthStore } from '@/shared/stores/authStore';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';
import { setupTestPinia } from '../setup';

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
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

describe('useAuth — auth-completion caller contract (ADR-046#auth-completion-caller-contract)', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };
  let authStore: ReturnType<typeof useAuthStore>;
  let csrfStore: ReturnType<typeof useCsrfStore>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();
    mockRoute = { query: {} };

    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);

    authStore = useAuthStore();
    csrfStore = useCsrfStore();
    csrfStore.shrimp = 'test-shrimp';
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    vi.restoreAllMocks();
    router.reset();
  });

  describe('successful auth POST + failed bootstrap refresh', () => {
    it('does NOT navigate to Dashboard when the follow-up snapshot fails', async () => {
      // Login POST succeeds (no MFA required)…
      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in' });

      // …but the follow-up refresh (setAuthenticated) and the recovery
      // retries all report 'failed'. Nothing landed, so navigation is
      // forbidden.
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue('failed');
      vi.spyOn(authStore, 'refresh').mockResolvedValue('failed');

      const { login, error } = useAuth();
      const result = await login('user@example.com', 'password');

      expect(result).toBe(false);
      expect(router.push).not.toHaveBeenCalled();
      // A retryable local error was surfaced via useAsyncHandler's onError.
      expect(error.value).not.toBeNull();
    });

    it('does NOT navigate when the follow-up refresh is refused', async () => {
      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in' });

      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue('refused');
      vi.spyOn(authStore, 'refresh').mockResolvedValue('refused');

      const { login, error } = useAuth();
      const result = await login('user@example.com', 'password');

      expect(result).toBe(false);
      expect(router.push).not.toHaveBeenCalled();
      expect(error.value).not.toBeNull();
    });
  });

  describe("'superseded' is success-by-delegation, not an error", () => {
    it('no-ops WITHOUT surfacing an error when superseded on the initial call', async () => {
      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in' });

      // A newer coordinator run has already reconciled; setAuthenticated
      // reports superseded on the very first call. Nothing to do — the
      // newer run owns the destination.
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue('superseded');
      const refreshSpy = vi.spyOn(authStore, 'refresh').mockResolvedValue('applied');

      const { login, error } = useAuth();
      const result = await login('user@example.com', 'password');

      expect(result).toBe(false);
      expect(router.push).not.toHaveBeenCalled();
      // NOT an error: the newer run is expected to complete.
      expect(error.value).toBeNull();
      // No recovery retries once the initial call returned superseded.
      expect(refreshSpy).not.toHaveBeenCalled();
    });

    it('no-ops when the retry lands on a superseded outcome', async () => {
      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in' });

      // Initial fails; the first retry hits a newer coordinator run.
      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue('failed');
      vi.spyOn(authStore, 'refresh').mockResolvedValue('superseded');

      const { login, error } = useAuth();
      const result = await login('user@example.com', 'password');

      expect(result).toBe(false);
      expect(router.push).not.toHaveBeenCalled();
      expect(error.value).toBeNull();
    });
  });

  describe('recovery does not re-POST the auth mutation', () => {
    it('retries verification (ordinary refresh) rather than the login POST', async () => {
      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in' });

      vi.spyOn(authStore, 'setAuthenticated').mockResolvedValue('failed');
      const refreshSpy = vi.spyOn(authStore, 'refresh').mockResolvedValue('failed');

      const { login } = useAuth();
      await login('user@example.com', 'password');

      // Two recovery retries after the initial setAuthenticated call.
      expect(refreshSpy).toHaveBeenCalledTimes(2);
      expect(refreshSpy).toHaveBeenNthCalledWith(1, {
        kind: 'ordinary',
        reason: 'retry',
      });
      expect(refreshSpy).toHaveBeenNthCalledWith(2, {
        kind: 'ordinary',
        reason: 'retry',
      });

      // The auth POST fired ONCE — the single-use consumable is not repeated.
      expect(axiosMock.history.post.filter((r) => r.url === '/auth/login')).toHaveLength(1);
    });
  });
});
