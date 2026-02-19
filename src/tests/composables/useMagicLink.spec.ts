// src/tests/composables/useMagicLink.spec.ts

import { useMagicLink } from '@/shared/composables/useMagicLink';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { setupTestPinia, type TestPiniaSetup } from '@/tests/setup';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
  }),
}));

describe('useMagicLink', () => {
  let setup: TestPiniaSetup;
  let csrfStore: ReturnType<typeof useCsrfStore>;

  beforeEach(async () => {
    setup = await setupTestPinia({ stubActions: false });
    csrfStore = useCsrfStore();
    csrfStore.shrimp = 'test-shrimp';
  });

  afterEach(() => {
    setup.axiosMock?.reset();
    vi.restoreAllMocks();
  });

  describe('requestMagicLink', () => {
    it('returns true and sets sent on success', async () => {
      setup.axiosMock?.onPost('/auth/email-login-request').reply(200, {
        success: 'Link sent',
      });

      const { requestMagicLink, sent, error } = useMagicLink();
      const result = await requestMagicLink('user@example.com');

      expect(result).toBe(true);
      expect(sent.value).toBe(true);
      expect(error.value).toBeNull();
    });

    it('returns false and sets error on server error response', async () => {
      setup.axiosMock?.onPost('/auth/email-login-request').reply(200, {
        error: 'Account not found',
        'field-error': ['login', 'Not found'],
      });

      const { requestMagicLink, sent, error, fieldError } = useMagicLink();
      const result = await requestMagicLink('bad@example.com');

      expect(result).toBe(false);
      expect(sent.value).toBe(false);
      expect(error.value).toBe('Account not found');
      expect(fieldError.value).toEqual(['login', 'Not found']);
    });

    it('retries transparently on 403 and succeeds', async () => {
      let callCount = 0;
      setup.axiosMock?.onPost('/auth/email-login-request').reply(() => {
        callCount++;
        if (callCount === 1) {
          return [403, { error: 'Forbidden' }];
        }
        return [200, { success: 'Link sent' }];
      });

      const { requestMagicLink, sent, error } = useMagicLink();
      const result = await requestMagicLink('user@example.com');

      expect(callCount).toBe(2);
      expect(result).toBe(true);
      expect(sent.value).toBe(true);
      expect(error.value).toBeNull();
    });

    it('shows sessionExpired when 403 retry also fails', async () => {
      setup.axiosMock?.onPost('/auth/email-login-request').reply(403, {
        error: 'Forbidden',
      });

      const { requestMagicLink, sent, error } = useMagicLink();
      const result = await requestMagicLink('user@example.com');

      expect(result).toBe(false);
      expect(sent.value).toBe(false);
      expect(error.value).toBe('web.auth.magicLink.sessionExpired');
    });

    it('returns false with networkError on network failure', async () => {
      setup.axiosMock?.onPost('/auth/email-login-request').networkError();

      const { requestMagicLink, error } = useMagicLink();
      const result = await requestMagicLink('user@example.com');

      expect(result).toBe(false);
      expect(error.value).toBe('web.auth.magicLink.networkError');
    });

    it('does not retry on non-403 HTTP errors', async () => {
      let callCount = 0;
      setup.axiosMock?.onPost('/auth/email-login-request').reply(() => {
        callCount++;
        return [500, { error: 'Internal Server Error' }];
      });

      const { requestMagicLink, error } = useMagicLink();
      const result = await requestMagicLink('user@example.com');

      expect(callCount).toBe(1);
      expect(result).toBe(false);
      expect(error.value).toBe('Internal Server Error');
    });
  });
});
