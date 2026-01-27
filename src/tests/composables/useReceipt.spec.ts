// src/tests/composables/useReceipt.spec.ts

import { useReceipt } from '@/shared/composables/useReceipt';
import { AxiosError } from 'axios';
import { useAuthStore } from '@/shared/stores/authStore';
import { useReceiptStore } from '@/shared/stores/receiptStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { Router, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';

import {
  mockBurnedReceiptRecord,
  mockReceiptDetails,
  mockReceiptRecord,
} from '../fixtures/receipt.fixture';

// Mock vue-i18n for useAsyncHandler dependency
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
  }),
}));

vi.mock('@/shared/stores/authStore');
vi.mock('@/shared/stores/receiptStore');
vi.mock('@/shared/stores/notificationsStore');
vi.mock('vue-router');

const storeMock: Partial<ReturnType<typeof useReceiptStore>> = {
  fetch: vi.fn(),
  record: mockReceiptRecord,
  details: mockReceiptDetails,
  setApiMode: vi.fn(),
  $reset: vi.fn(),
};

const authStoreMock: Partial<ReturnType<typeof useAuthStore>> = {
  isAuthenticated: true,
};

const notificationsMock: Partial<ReturnType<typeof useNotificationsStore>> = {
  show: vi.fn(),
};

const mockRouter: Router = getRouter();

vi.mocked(useRouter).mockReturnValue(mockRouter);
vi.mocked(useAuthStore).mockReturnValue(authStoreMock as ReturnType<typeof useAuthStore>);
vi.mocked(useReceiptStore).mockReturnValue(storeMock as ReturnType<typeof useReceiptStore>);
vi.mocked(useNotificationsStore).mockReturnValue(
  notificationsMock as ReturnType<typeof useNotificationsStore>
);

describe('useReceipt', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('lifecycle', () => {
    const store = {
      init: vi.fn(),
      fetch: vi.fn().mockResolvedValue(mockReceiptRecord),
      burn: vi.fn().mockResolvedValue(undefined),
      record: ref(null),
      details: ref(null),
      canBurn: ref(false),
      setApiMode: vi.fn(),
      $reset: vi.fn(),
    };

    beforeEach(() => {
      vi.mocked(useReceiptStore).mockReturnValue(store as ReturnType<typeof useReceiptStore>);
    });

    it('should initialize with empty state', () => {
      const { record, details, isLoading, passphrase } = useReceipt('test-key');

      expect(record.value).toBeNull();
      expect(details.value).toBeNull();
      expect(isLoading.value).toBe(false);
      expect(passphrase.value).toBe('');
    });

    it('should cleanup state on reset', () => {
      const { reset, passphrase } = useReceipt('test-key');

      passphrase.value = 'secret123';
      reset();

      expect(passphrase.value).toBe('');
      expect(store.$reset).toHaveBeenCalled();
    });
  });

  describe('lifecycle', () => {
    it('should handle error state reset', () => {
      const { error, reset } = useReceipt('test-key');
      error.value = {
        name: 'ApplicationError' as const,
        message: 'Test error',
        type: 'human',
        severity: 'error',
        code: null,
      };
      reset();
      expect(error.value).toBeNull();
    });

    it('should handle loading state', () => {
      const { isLoading } = useReceipt('test-key');
      expect(isLoading.value).toBe(false);
    });

    it('should initialize with empty passphrase', () => {
      const { passphrase } = useReceipt('test-key');
      expect(passphrase.value).toBe('');
    });
  });

  describe('router integration', () => {
    // More idiomatic router mock
    const routerMock = {
      push: vi.fn(),
      currentRoute: ref({
        name: 'Test',
        params: {},
        query: {},
      }),
      replace: vi.fn(),
      back: vi.fn(),
      forward: vi.fn(),
      go: vi.fn(),
    } satisfies Partial<Router>;

    beforeEach(() => {
      vi.mocked(useRouter).mockReturnValue(routerMock);
      const storeMock = {
        burn: vi.fn().mockResolvedValue(undefined),
        canBurn: ref(true),
        fetch: vi.fn(),
        record: ref(null),
        details: ref(null),
        isLoading: ref(false),
        setApiMode: vi.fn(),
        $reset: vi.fn(),
      };
      vi.mocked(useReceiptStore).mockReturnValue(storeMock as ReturnType<typeof useReceiptStore>);
    });

    it('should redirect after burn with correct params', async () => {
      const { burn } = useReceipt('test-key');
      await burn();

      expect(routerMock.push).toHaveBeenCalledWith({
        name: 'Receipt link',
        params: { receiptIdentifier: 'test-key' },
        query: expect.objectContaining({
          ts: expect.any(String),
        }),
      });
    });

    it('should include timestamp in redirect query', async () => {
      const { burn } = useReceipt('test-key');
      vi.useFakeTimers();
      const now = new Date('2024-01-01');
      vi.setSystemTime(now);

      await burn();

      expect(routerMock.push).toHaveBeenCalledWith(
        expect.objectContaining({
          query: { ts: now.getTime().toString() },
        })
      );

      vi.useRealTimers();
    });
  });

  describe('fetching metadata', () => {
    const store = {
      fetch: vi.fn().mockImplementation(async () => {
        store.record.value = mockReceiptRecord;
        store.details.value = mockReceiptDetails;
        return;
      }),
      record: ref(null),
      details: ref(null),
      isLoading: ref(false),
      setApiMode: vi.fn(),
    };

    beforeEach(() => {
      vi.mocked(useReceiptStore).mockReturnValue(store);
      store.record.value = null;
      store.details.value = null;
      store.isLoading.value = false;
    });

    it('should handle successful metadata fetch', async () => {
      const { fetch, record, details, isLoading } = useReceipt('test-key');

      const promise = fetch();
      expect(isLoading.value).toBe(true);

      await promise;
      expect(store.fetch).toHaveBeenCalledWith('test-key');
      expect(record.value).toEqual(mockReceiptRecord);
      expect(details.value).toEqual(mockReceiptDetails);
      expect(isLoading.value).toBe(false);
    });

    it('should handle fetch errors', async () => {
      // Setup
      const networkError = new Error('Network error');
      store.fetch.mockRejectedValueOnce(networkError);
      const notifications = { show: vi.fn() };
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);

      // Execute
      const { fetch, isLoading, error } = useReceipt('test-key');
      await fetch();

      // Verify
      expect(store.fetch).toHaveBeenCalledWith('test-key');
      expect(isLoading.value).toBe(false);
      expect(notifications.show).toHaveBeenCalledWith('web.COMMON.unexpected_error', 'error', 'top');
      expect(error.value).toBeDefined();
      expect(error.value?.type).toBe('technical');
      expect(error.value?.severity).toBe('error');
    });

    it('should handle 404 errors as human-facing', async () => {
      // Setup
      const notFoundError = new AxiosError(
        'Request failed with status 404',
        'ERR_NOT_FOUND',
        undefined,
        undefined,
        {
          status: 404,
          data: { message: 'Secret not found or has been burned' },
        } as any
      );

      store.fetch.mockRejectedValueOnce(notFoundError);
      const notifications = { show: vi.fn() };
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);

      // Execute
      const { fetch, isLoading, error } = useReceipt('test-key');
      await fetch();

      // Verify
      expect(store.fetch).toHaveBeenCalledWith('test-key');
      expect(isLoading.value).toBe(false);
      expect(error.value).toMatchObject({
        message: 'Secret not found or has been burned',
        type: 'human',
        severity: 'error',
        code: 404,
      });
      expect(notifications.show).toHaveBeenCalledWith(
        'Secret not found or has been burned',
        'error',
        'top'
      );
    });
  });

  describe('burning secrets', () => {
    it('should handle successful burn operation', async () => {
      const store = {
        burn: vi.fn().mockResolvedValue(mockBurnedReceiptRecord),
        fetch: vi.fn().mockResolvedValue(mockBurnedReceiptRecord),
        canBurn: ref(true),
        record: ref(mockReceiptRecord),
        details: ref(mockReceiptDetails),
        setApiMode: vi.fn(),
      };
      const notifications = { show: vi.fn() };
      const mockRouter = {
        push: vi.fn().mockResolvedValue(undefined), // Router push returns a promise
      } as unknown as Router;

      vi.mocked(useReceiptStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(mockRouter);

      const { burn, passphrase } = useReceipt('test-key');
      passphrase.value = 'secret123';

      // Wait for all async operations to complete
      await burn();

      // Verify the entire sequence completed
      expect(store.burn).toHaveBeenCalledWith('test-key', 'secret123');

      // expect(notifications.show).toHaveBeenCalledWith('Secret burned successfully', 'success');
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'Receipt link',
        params: { receiptIdentifier: 'test-key' },
        query: expect.objectContaining({ ts: expect.any(String) }),
      });
    });

    it('should prevent plop burn attempts', async () => {
      // Setup
      const store = {
        burn: vi.fn(),
        fetch: vi.fn().mockResolvedValue(mockReceiptRecord),
        canBurn: ref(false),
        record: ref(mockReceiptRecord),
        setApiMode: vi.fn(),
      };
      const notifications = { show: vi.fn() };
      const router = { push: vi.fn() };

      vi.mocked(useReceiptStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(router);

      // Execute
      const { burn, error } = useReceipt('test-key');
      await burn();

      // Verify
      expect(store.burn).not.toHaveBeenCalled();
      expect(error.value).toMatchObject({
        message: 'Cannot burn this secret',
        type: 'human',
        severity: 'error',
      });
      expect(notifications.show).toHaveBeenCalledWith('Cannot burn this secret', 'error', 'top');
    });
  });

  describe('API mode selection', () => {
    const store = {
      fetch: vi.fn().mockResolvedValue(mockReceiptRecord),
      burn: vi.fn(),
      record: ref(null),
      details: ref(null),
      canBurn: ref(false),
      setApiMode: vi.fn(),
      $reset: vi.fn(),
    };

    beforeEach(() => {
      vi.mocked(useReceiptStore).mockReturnValue(store as ReturnType<typeof useReceiptStore>);
      store.setApiMode.mockClear();
    });

    it('uses authenticated mode when user is authenticated', () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated: true,
      } as ReturnType<typeof useAuthStore>);

      useReceipt('test-key');

      expect(store.setApiMode).toHaveBeenCalledWith('authenticated');
    });

    it('uses public mode when user is not authenticated', () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated: false,
      } as ReturnType<typeof useAuthStore>);

      useReceipt('test-key');

      expect(store.setApiMode).toHaveBeenCalledWith('public');
    });

    it('uses public mode when isAuthenticated is null/undefined', () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated: null,
      } as unknown as ReturnType<typeof useAuthStore>);

      useReceipt('test-key');

      expect(store.setApiMode).toHaveBeenCalledWith('public');
    });

    it('usePublicApi: true forces public mode regardless of auth state', () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated: true,
      } as ReturnType<typeof useAuthStore>);

      useReceipt('test-key', { usePublicApi: true });

      expect(store.setApiMode).toHaveBeenCalledWith('public');
    });

    it('usePublicApi: false forces authenticated mode regardless of auth state', () => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated: false,
      } as ReturnType<typeof useAuthStore>);

      useReceipt('test-key', { usePublicApi: false });

      expect(store.setApiMode).toHaveBeenCalledWith('authenticated');
    });
  });
});
