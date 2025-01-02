import { useMetadata } from '@/composables/useMetadata';
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { useRouter } from 'vue-router';

import {
  mockBurnedMetadataRecord,
  mockMetadataDetails,
  mockMetadataRecord,
} from '../fixtures/metadata';

vi.mock('@/stores/metadataStore');
vi.mock('@/stores/notificationsStore');
vi.mock('vue-router');

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

  describe('fetching metadata', () => {
    const store = {
      fetch: vi.fn().mockResolvedValue(mockMetadataRecord),
      record: ref(null),
      details: ref(mockMetadataDetails),
      isLoading: ref(false),
    };

    beforeEach(() => {
      vi.mocked(useMetadataStore).mockReturnValue(store);
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
      store.fetch.mockRejectedValueOnce(new Error('Network error'));
      const notifications = { show: vi.fn() };
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);

      const { fetch } = useMetadata('test-key');
      await fetch();

      expect(notifications.show).toHaveBeenCalledWith('Network error', 'error');
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
      const router = { push: vi.fn() };

      vi.mocked(useMetadataStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(router);

      const { burn, passphrase } = useMetadata('test-key');
      passphrase.value = 'secret123';

      await burn();

      expect(store.burn).toHaveBeenCalledWith('test-key', 'secret123');
      expect(notifications.show).toHaveBeenCalledWith(
        'Secret burned successfully',
        'success'
      );
      expect(router.push).toHaveBeenCalled();
    });

    it('should prevent plop burn attempts', async () => {
      const store = {
        burn: vi.fn(),
        fetch: vi.fn().mockResolvedValue(mockMetadataRecord),
        canBurn: ref(false),
        record: ref(mockMetadataRecord),
      };
      const notifications = { show: vi.fn() };
      const router = { push: vi.fn() }; // Add router mock

      vi.mocked(useMetadataStore).mockReturnValue(store);
      vi.mocked(useNotificationsStore).mockReturnValue(notifications);
      vi.mocked(useRouter).mockReturnValue(router); // Mock useRouter
      const { fetch, record, details, isLoading, canBurn } = useMetadata('test-key');

      const { burn } = useMetadata('test-key');
      await burn();

      expect(store.burn).not.toHaveBeenCalled();
    });
  });
});
