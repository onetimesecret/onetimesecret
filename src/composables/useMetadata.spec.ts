// src/composables/useMetadata.spec.ts

import { useMetadata } from '@/composables/useMetadata';
import { AxiosError } from 'axios';
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi, Mock } from 'vitest';
import { ref } from 'vue';
import { Router, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';

import { mockBurnedMetadataRecord, mockMetadataDetails, mockMetadataRecord } from '../fixtures/metadata.fixture';

vi.mock('@/stores/metadataStore');
vi.mock('@/stores/notificationsStore');
vi.mock('vue-router');

const storeMock: Partial<ReturnType<typeof useMetadataStore>> = {
  fetch: vi.fn(),
  record: mockMetadataRecord,
  details: mockMetadataDetails,
  $reset: vi.fn(),
};

const notificationsMock: Partial<ReturnType<typeof useNotificationsStore>> = {
  show: vi.fn(),
};

const mockRouter: Router = getRouter();

vi.mocked(useRouter).mockReturnValue(mockRouter);
vi.mocked(useMetadataStore).mockReturnValue(storeMock as ReturnType<typeof useMetadataStore>);
vi.mocked(useNotificationsStore).mockReturnValue(notificationsMock as ReturnType<typeof useNotificationsStore>);

const mockMetadata = { id: 'test-key', value: 'secret-data' };

describe('useMetadata', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  describe('lifecycle', () => {
    const store = {
      fetch: vi.fn().mockResolvedValue(mockMetadataRecord),
      record: ref(null),
      details: ref(null),
      isLoading: ref(false),
      $reset: vi.fn(),
    };

    beforeEach(() => {
      vi.mocked(useMetadataStore).mockReturnValue(store);
    });

    it('should initialize with empty state', () => {
      const { record, details, isLoading, passphrase } = useMetadata('test-key');

      expect(record.value).toBeNull();
      expect(details.value).toBeNull();
      expect(isLoading.value).toBe(false);
      expect(passphrase.value).toBe('');
    });

    it('should cleanup state on reset', () => {
      const { reset, passphrase } = useMetadata('test-key');

      passphrase.value = 'secret123';
      reset();

      expect(passphrase.value).toBe('');
      expect(store.$reset).toHaveBeenCalled();
    });
  });

  describe('lifecycle', () => {
    it('should handle error state reset', () => {
      const { error, reset } = useMetadata('test-key');
      error.value = { message: 'Test error', type: 'human', severity: 'error' };
      reset();
      expect(error.value).toBeNull();
    });

    it('should handle loading state', () => {
      const { isLoading } = useMetadata('test-key');
      expect(isLoading.value).toBe(false);
    });

    it('should initialize with empty passphrase', () => {
      const { passphrase } = useMetadata('test-key');
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
        $reset: vi.fn(),
      };
      vi.mocked(useMetadataStore).mockReturnValue(storeMock as ReturnType<typeof useMetadataStore>);
    });

    it('should redirect after burn with correct params', async () => {
      const { burn } = useMetadata('test-key');
      await burn();

      expect(routerMock.push).toHaveBeenCalledWith({
        name: 'Metadata link',
        params: { metadataKey: 'test-key' },
        query: expect.objectContaining({
          ts: expect.any(String),
        }),
      });
    });

    it('should include timestamp in redirect query', async () => {
      const { burn } = useMetadata('test-key');
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
        store.record.value = mockMetadataRecord;
        store.details.value = mockMetadataDetails;
        return;
      }),
      record: ref(null),
      details: ref(null),
      isLoading: ref(false),
    };

    beforeEach(() => {
      vi.mocked(useMetadataStore).mockReturnValue(store);
      store.record.value = null;
      store.details.value = null;
      store.isLoading.value = false;
    });

    it('should handle successful metadata fetch', async () => {
      const { fetch, record, details, isLoading } = useMetadata('test-key');

      const promise = fetch();
      expect(isLoading.value).toBe(true);

      await promise;
      expect(store.fetch).toHaveBeenCalledWith('test-key');
      expect(record.value).toEqual(mockMetadataRecord);
      expect(details.value).toEqual(mockMetadataDetails);
      expect(isLoading.value).toBe(false);
    });

    it('should handle fetch errors', async () => {
      // Setup
      const networkError = new Error('Network error');
      store.fetch.mockRejectedValueOnce(networkError);
      const notifications = { show: vi.fn() };
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);

      // Execute
      const { fetch, isLoading, error } = useMetadata('test-key');
      await fetch();

      // Verify
      expect(store.fetch).toHaveBeenCalledWith('test-key');
      expect(isLoading.value).toBe(false);
      expect(notifications.show).not.toHaveBeenCalled();
      expect(error.value).toBeDefined();
      expect(error.value?.type).toBe('technical');
      expect(error.value?.severity).toBe('error');
    });

    it('should handle 404 errors as human-facing', async () => {
      // Setup
      const notFoundError = new AxiosError('Request failed with status 404', 'ERR_NOT_FOUND', undefined, undefined, {
        status: 404,
        data: { message: 'Secret not found or has been burned' },
      } as any);

      store.fetch.mockRejectedValueOnce(notFoundError);
      const notifications = { show: vi.fn() };
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);

      // Execute
      const { fetch, isLoading, error } = useMetadata('test-key');
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
      expect(notifications.show).toHaveBeenCalledWith('Secret not found or has been burned', 'error');
    });
  });

  describe('burning secrets', () => {
    it('should handle successful burn operation', async () => {
      const store = {
        burn: vi.fn().mockResolvedValue(mockBurnedMetadataRecord),
        fetch: vi.fn().mockResolvedValue(mockBurnedMetadataRecord),
        canBurn: ref(true),
        record: ref(mockMetadataRecord),
        details: ref(mockMetadataDetails),
      };
      const notifications = { show: vi.fn() };
      const mockRouter = {
        push: vi.fn().mockResolvedValue(undefined), // Router push returns a promise
      } as unknown as Router;

      vi.mocked(useMetadataStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(mockRouter);

      const { burn, passphrase } = useMetadata('test-key');
      passphrase.value = 'secret123';

      // Wait for all async operations to complete
      await burn();

      // Verify the entire sequence completed
      expect(store.burn).toHaveBeenCalledWith('test-key', 'secret123');

      // expect(notifications.show).toHaveBeenCalledWith('Secret burned successfully', 'success');
      expect(mockRouter.push).toHaveBeenCalledWith({
        name: 'Metadata link',
        params: { metadataKey: 'test-key' },
        query: expect.objectContaining({ ts: expect.any(String) }),
      });
    });

    it('should prevent plop burn attempts', async () => {
      // Setup
      const store = {
        burn: vi.fn(),
        fetch: vi.fn().mockResolvedValue(mockMetadataRecord),
        canBurn: ref(false),
        record: ref(mockMetadataRecord),
      };
      const notifications = { show: vi.fn() };
      const router = { push: vi.fn() };

      vi.mocked(useMetadataStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(router);

      // Execute
      const { burn, error } = useMetadata('test-key');
      await burn();

      // Verify
      expect(store.burn).not.toHaveBeenCalled();
      console.log(error.value);
      console.log(error.value?.original);
      debugger;
      expect(error.value).toMatchObject({
        message: 'Cannot burn this secret',
        type: 'human',
        severity: 'error',
      });
      expect(notifications.show).toHaveBeenCalledWith('Cannot burn this secret', 'error');
    });
  });
});
