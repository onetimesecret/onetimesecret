// tests/unit/vue/composables/useMetadata.spec.ts
import {
    mockBurnedMetadataDetails,
    mockBurnedMetadataRecord,
    mockMetadataDetails,
    mockMetadataRecord
} from '@/../tests/unit/vue/fixtures/metadata';
import { useMetadata } from '@/composables/useMetadata';
import type { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

vi.mock('@/stores/metadataStore', () => ({
  useMetadataStore: vi.fn(),
}));

vi.mock('@/stores/notificationsStore', () => ({
  useNotificationsStore: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRouter: vi.fn(),
}));

interface MockStore {
  fetchOne: vi.Mock;
  burn: vi.Mock;
  canBurn: boolean;
  currentRecord: Metadata | null;
  currentDetails: MetadataDetails | null;
  isLoading: boolean;
  error: Error | null;
}

describe('useMetadata', () => {
  let mockStore: MockStore;
  let mockNotifications: { show: vi.Mock };
  let mockRouter: { push: vi.Mock };

  beforeEach(() => {
    setActivePinia(createPinia());

    mockStore = {
      fetchOne: vi.fn(),
      burn: vi.fn(),
      canBurn: true,
      currentRecord: null,
      currentDetails: null,
      isLoading: false,
      error: null,
    };

    // Mock store with refs to match composable behavior
    (useMetadataStore as any).mockReturnValue({
      ...mockStore,
      currentRecord: ref(mockStore.currentRecord),
      currentDetails: ref(mockStore.currentDetails),
      isLoading: ref(mockStore.isLoading),
      error: ref(mockStore.error),
    });

    mockNotifications = {
      show: vi.fn(),
    };

    mockRouter = {
      push: vi.fn(),
    };

    (useNotificationsStore as any).mockReturnValue(mockNotifications);
    (useRouter as any).mockReturnValue(mockRouter);
  });

  describe('initialization', () => {
    it('provides default state values', () => {
      const { record, details, isLoading, error, passphrase, canBurn } =
        useMetadata('test-key');

      expect(record.value).toBeNull();
      expect(details.value).toBeNull();
      expect(isLoading.value).toBe(false);
      expect(error.value).toBeNull();
      expect(passphrase.value).toBe('');
      expect(canBurn.value).toBe(true);
    });
  });

  describe('fetch operations', () => {
    it('successfully fetches metadata', async () => {
      const { fetch, record, details } = useMetadata('test-key');

      mockStore.fetchOne.mockImplementationOnce(async () => {
        (useMetadataStore as any).mockReturnValue({
          ...mockStore,
          currentRecord: ref(mockMetadataRecord),
          currentDetails: ref(mockMetadataDetails),
          isLoading: ref(false),
          error: ref(null),
        });
      });

      await fetch();

      expect(mockStore.fetchOne).toHaveBeenCalledWith('test-key');
      expect(record.value).toEqual(mockMetadataRecord);
      expect(details.value).toEqual(mockMetadataDetails);
    });

    it('handles fetch errors', async () => {
      const testError = new Error('Fetch failed');
      const { fetch, error } = useMetadata('test-key');

      mockStore.fetchOne.mockRejectedValueOnce(testError);
      await fetch();

      expect(error.value).toBeDefined();
      expect(mockStore.fetchOne).toHaveBeenCalledWith('test-key');
    });
  });

  describe('burn operations', () => {
    it('successfully burns metadata', async () => {
      const { burn, record, details, passphrase } = useMetadata('test-key');

      mockStore.burn.mockImplementationOnce(async () => {
        (useMetadataStore as any).mockReturnValue({
          ...mockStore,
          currentRecord: ref(mockBurnedMetadataRecord),
          currentDetails: ref(mockBurnedMetadataDetails),
          isLoading: ref(false),
          error: ref(null),
        });
      });

      passphrase.value = 'test-pass';
      await burn();

      expect(mockStore.burn).toHaveBeenCalledWith('test-key', 'test-pass');
      expect(mockNotifications.show).toHaveBeenCalledWith(
        'Secret burned successfully',
        'success'
      );
      expect(record.value).toEqual(mockBurnedMetadataRecord);
      expect(details.value).toEqual(mockBurnedMetadataDetails);
      expect(mockRouter.push).toHaveBeenCalled();
    });

    it('prevents burning when canBurn is false', async () => {
      // Set canBurn to false in the store
      (useMetadataStore as any).mockReturnValue({
        ...mockStore,
        canBurn: false,
        currentRecord: ref(null),
        currentDetails: ref(null),
        isLoading: ref(false),
        error: ref(null),
      });

      const { burn, canBurn } = useMetadata('test-key');
      await burn();

      expect(canBurn.value).toBe(false);
      expect(mockStore.burn).not.toHaveBeenCalled();
    });
  });

  describe('loading states', () => {
    it('tracks loading state during operations', async () => {
      const { fetch, isLoading } = useMetadata('test-key');

      mockStore.fetchOne.mockImplementationOnce(async () => {
        (useMetadataStore as any).mockReturnValue({
          ...mockStore,
          isLoading: ref(true),
        });
        await new Promise(resolve => setTimeout(resolve, 0));
        (useMetadataStore as any).mockReturnValue({
          ...mockStore,
          isLoading: ref(false),
        });
      });

      const fetchPromise = fetch();
      expect(isLoading.value).toBe(true);
      await fetchPromise;
      expect(isLoading.value).toBe(false);
    });
  });
});
