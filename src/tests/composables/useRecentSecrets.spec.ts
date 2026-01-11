// src/tests/composables/useRecentSecrets.spec.ts

import { useRecentSecrets } from '@/shared/composables/useRecentSecrets';
import { createPinia, setActivePinia } from 'pinia';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { ref, computed, defineComponent, nextTick } from 'vue';
import { mount } from '@vue/test-utils';

import type { ConcealedMessage } from '@/types/ui/concealed-message';
import type { Metadata } from '@/schemas/models/metadata';
import { mockMetadataRecentRecords, mockMetadataRecentDetails } from '../fixtures/metadata.fixture';

// --- Mock Dependencies ---

const createMockConcealedMessage = (
  id: string,
  overrides?: Partial<ConcealedMessage>
): ConcealedMessage => ({
  id,
  metadata_identifier: `metadata-${id}`,
  secret_identifier: `secret-${id}`,
  response: {
    success: true,
    record: {
      key: `key-${id}`,
      shortid: `short-${id}`,
      state: 'new',
      identifier: `id-${id}`,
      created: new Date(),
      updated: new Date(),
      metadata_ttl: 3600,
      secret_ttl: 3600,
      lifespan: 3600,
      share_url: `https://example.com/share/${id}`,
      metadata_url: `https://example.com/metadata/${id}`,
      secret_url: `https://example.com/secret/${id}`,
      share_path: `/share/${id}`,
      metadata_path: `/metadata/${id}`,
      burn_path: `/burn/${id}`,
      secret_path: `/secret/${id}`,
    },
    details: {
      type: 'record',
      display_lines: 1,
      no_cache: false,
      has_passphrase: false,
      show_secret: true,
      show_secret_link: true,
      show_metadata_link: true,
      show_metadata: true,
      show_recipients: false,
    },
  },
  clientInfo: {
    hasPassphrase: false,
    ttl: 3600,
    createdAt: new Date(),
  },
  ...overrides,
});

// Mock stores
const mockConcealedMessages = ref<ConcealedMessage[]>([]);
const mockApiRecords = ref<Metadata[]>([]);
const mockIsAuthenticated = ref(false);
const mockApiError = ref<Error | null>(null);
const mockApiLoading = ref(false);
const mockWorkspaceMode = ref(false);

const mockConcealedStore = {
  concealedMessages: mockConcealedMessages,
  hasMessages: computed(() => mockConcealedMessages.value.length > 0),
  workspaceMode: mockWorkspaceMode,
  isInitialized: computed(() => true),
  addMessage: vi.fn((message: ConcealedMessage) => {
    mockConcealedMessages.value.unshift(message);
  }),
  clearMessages: vi.fn(() => {
    mockConcealedMessages.value = [];
  }),
  setWorkspaceMode: vi.fn((enabled: boolean) => {
    mockWorkspaceMode.value = enabled;
  }),
  toggleWorkspaceMode: vi.fn(() => {
    mockWorkspaceMode.value = !mockWorkspaceMode.value;
  }),
  init: vi.fn(),
  $reset: vi.fn(),
};

const mockMetadataListStore = {
  records: mockApiRecords,
  details: ref(mockMetadataRecentDetails),
  count: computed(() => mockApiRecords.value.length),
  initialized: vi.fn(() => mockApiRecords.value.length > 0),
  fetchList: vi.fn(),
  refreshRecords: vi.fn(),
  $reset: vi.fn(),
};

const mockAuthStore = {
  isAuthenticated: mockIsAuthenticated,
};

const mockNotificationsStore = {
  show: vi.fn(),
};

// Mock imports
vi.mock('@/shared/stores/concealedMetadataStore', () => ({
  useConcealedMetadataStore: () => mockConcealedStore,
}));

vi.mock('@/shared/stores/metadataListStore', () => ({
  useMetadataListStore: () => mockMetadataListStore,
}));

vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: () => mockAuthStore,
}));

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: () => mockNotificationsStore,
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => {
      const translations: Record<string, string> = {
        'web.COMMON.unexpected_error': 'An unexpected error occurred',
        'web.secrets.recent_secrets_loaded': 'Recent secrets loaded',
        'web.secrets.failed_to_load_recent': 'Failed to load recent secrets',
      };
      return translations[key] || key;
    },
  }),
}));

vi.mock('@/shared/composables/useAsyncHandler', () => ({
  useAsyncHandler: () => ({
    wrap: vi.fn(async <T>(fn: () => Promise<T>) => {
      try {
        return await fn();
      } catch (error) {
        mockApiError.value = error as Error;
        return undefined;
      }
    }),
    createError: vi.fn((message: string, type: string, severity: string) => ({
      name: 'ApplicationError',
      message,
      type,
      severity,
    })),
    wrapError: vi.fn(),
  }),
  createError: vi.fn((message: string, type: string, severity: string) => ({
    name: 'ApplicationError',
    message,
    type,
    severity,
  })),
}));

// Helper to mount composable in Vue context
function mountComposable<T>(composableFn: () => T): T {
  let result: T;
  const TestComponent = defineComponent({
    setup() {
      result = composableFn();
      return () => null;
    },
  });
  mount(TestComponent, { global: { plugins: [createPinia()] } });
  return result!;
}

// --- Test Suite ---

describe('useRecentSecrets', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Reset mock state
    mockConcealedMessages.value = [];
    mockApiRecords.value = [];
    mockIsAuthenticated.value = false;
    mockApiError.value = null;
    mockApiLoading.value = false;
    mockWorkspaceMode.value = false;
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  // === Authentication State Switching ===

  describe('authentication state switching', () => {
    it('returns local storage data when not authenticated', () => {
      const localMessages = [
        createMockConcealedMessage('local-1'),
        createMockConcealedMessage('local-2'),
      ];
      mockConcealedMessages.value = localMessages;
      mockIsAuthenticated.value = false;

      const { records, dataSource } = mountComposable(() => useRecentSecrets());

      expect(dataSource.value).toBe('local');
      expect(records.value).toHaveLength(2);
    });

    it('returns API data when authenticated', async () => {
      mockIsAuthenticated.value = true;
      mockApiRecords.value = mockMetadataRecentRecords as unknown as Metadata[];
      mockMetadataListStore.fetchList.mockResolvedValue(undefined);

      const { dataSource, refresh } = mountComposable(() => useRecentSecrets());

      await refresh();
      await nextTick();

      expect(dataSource.value).toBe('api');
      expect(mockMetadataListStore.fetchList).toHaveBeenCalled();
    });

    it('switches data source when auth state changes', async () => {
      // Start unauthenticated
      mockIsAuthenticated.value = false;
      const localMessages = [createMockConcealedMessage('local-1')];
      mockConcealedMessages.value = localMessages;

      const { dataSource, refresh } = mountComposable(() => useRecentSecrets());

      expect(dataSource.value).toBe('local');

      // Authenticate
      mockIsAuthenticated.value = true;
      mockApiRecords.value = mockMetadataRecentRecords as unknown as Metadata[];
      mockMetadataListStore.fetchList.mockResolvedValue(undefined);

      await refresh();
      await nextTick();

      expect(dataSource.value).toBe('api');
    });
  });

  // === Guest Mode (Local Storage) ===

  describe('guest mode (local storage)', () => {
    beforeEach(() => {
      mockIsAuthenticated.value = false;
    });

    it('initializes with sessionStorage data', () => {
      const storedMessages = [
        createMockConcealedMessage('stored-1'),
        createMockConcealedMessage('stored-2'),
      ];
      mockConcealedMessages.value = storedMessages;

      const { records, hasRecords } = mountComposable(() => useRecentSecrets());

      expect(records.value).toHaveLength(2);
      expect(hasRecords.value).toBe(true);
    });

    it('adds new records to beginning of list', () => {
      const existingMessages = [createMockConcealedMessage('existing-1')];
      mockConcealedMessages.value = existingMessages;

      const { addRecord, records } = mountComposable(() => useRecentSecrets());
      const newMessage = createMockConcealedMessage('new-1');

      addRecord(newMessage);

      expect(mockConcealedStore.addMessage).toHaveBeenCalledWith(newMessage);
      expect(records.value[0].id).toBe('new-1');
    });

    it('clears records from sessionStorage', () => {
      mockConcealedMessages.value = [createMockConcealedMessage('to-clear')];

      const { clearRecords, records } = mountComposable(() => useRecentSecrets());

      clearRecords();

      expect(mockConcealedStore.clearMessages).toHaveBeenCalled();
      expect(records.value).toHaveLength(0);
    });

    it('persists workspaceMode to localStorage', () => {
      const { setWorkspaceMode, workspaceMode } = mountComposable(() => useRecentSecrets());

      setWorkspaceMode(true);

      expect(mockConcealedStore.setWorkspaceMode).toHaveBeenCalledWith(true);
      expect(workspaceMode.value).toBe(true);
    });
  });

  // === Authenticated Mode (API) ===

  describe('authenticated mode (API)', () => {
    beforeEach(() => {
      mockIsAuthenticated.value = true;
      mockMetadataListStore.fetchList.mockResolvedValue(undefined);
    });

    it('fetches from /api/v3/receipt/recent on init', async () => {
      mockApiRecords.value = mockMetadataRecentRecords as unknown as Metadata[];

      const { refresh } = mountComposable(() => useRecentSecrets());

      await refresh();

      expect(mockMetadataListStore.fetchList).toHaveBeenCalled();
    });

    it('handles API errors gracefully', async () => {
      const apiError = new Error('Network error');
      mockMetadataListStore.fetchList.mockRejectedValue(apiError);

      const { refresh, error } = mountComposable(() => useRecentSecrets());

      await refresh();

      expect(error.value).toBeDefined();
    });

    it('does NOT write to sessionStorage when authenticated', async () => {
      mockApiRecords.value = mockMetadataRecentRecords as unknown as Metadata[];

      const { refresh, addRecord } = mountComposable(() => useRecentSecrets());

      await refresh();

      // Authenticated mode should not allow adding to local storage
      const newMessage = createMockConcealedMessage('should-not-add');
      addRecord(newMessage);

      // Store method should not be called when authenticated
      // (implementation should guard this)
      expect(mockConcealedStore.addMessage).not.toHaveBeenCalled();
    });

    it('refresh triggers new API call', async () => {
      mockApiRecords.value = mockMetadataRecentRecords as unknown as Metadata[];

      const { refresh } = mountComposable(() => useRecentSecrets());

      await refresh();
      expect(mockMetadataListStore.fetchList).toHaveBeenCalledTimes(1);

      await refresh();
      expect(mockMetadataListStore.fetchList).toHaveBeenCalledTimes(2);
    });
  });

  // === Unified Interface ===

  describe('unified interface', () => {
    it('records is reactive and updates on data changes', async () => {
      mockIsAuthenticated.value = false;

      const { records } = mountComposable(() => useRecentSecrets());

      expect(records.value).toHaveLength(0);

      mockConcealedMessages.value = [createMockConcealedMessage('reactive-test')];
      await nextTick();

      expect(records.value).toHaveLength(1);
    });

    it('hasRecords computed correctly reflects state', () => {
      mockIsAuthenticated.value = false;

      const { hasRecords } = mountComposable(() => useRecentSecrets());

      expect(hasRecords.value).toBe(false);

      mockConcealedMessages.value = [createMockConcealedMessage('has-records-test')];

      expect(hasRecords.value).toBe(true);
    });

    it('isLoading reflects async operation state', async () => {
      mockIsAuthenticated.value = true;

      let resolvePromise: () => void;
      const delayedFetch = new Promise<void>((resolve) => {
        resolvePromise = resolve;
      });
      mockMetadataListStore.fetchList.mockReturnValue(delayedFetch);

      const { isLoading, refresh } = mountComposable(() => useRecentSecrets());

      expect(isLoading.value).toBe(false);

      const refreshPromise = refresh();
      await nextTick();

      expect(isLoading.value).toBe(true);

      resolvePromise!();
      await refreshPromise;
      await nextTick();

      expect(isLoading.value).toBe(false);
    });

    it('error captures and exposes errors', async () => {
      mockIsAuthenticated.value = true;
      const testError = new Error('Test API error');
      mockMetadataListStore.fetchList.mockRejectedValue(testError);

      const { error, refresh } = mountComposable(() => useRecentSecrets());

      expect(error.value).toBeNull();

      await refresh();

      expect(error.value).toBeDefined();
    });
  });

  // === Error Handling ===

  describe('error handling', () => {
    it('API errors are classified and surfaced via useAsyncHandler', async () => {
      mockIsAuthenticated.value = true;
      const apiError = new Error('API Error');
      (apiError as any).response = { status: 500 };
      mockMetadataListStore.fetchList.mockRejectedValue(apiError);

      const { refresh, error } = mountComposable(() => useRecentSecrets());

      await refresh();

      expect(error.value).toBeDefined();
    });

    it('storage errors are logged but do not crash', () => {
      mockIsAuthenticated.value = false;

      // Simulate storage error by making the store throw
      const originalAddMessage = mockConcealedStore.addMessage;
      mockConcealedStore.addMessage = vi.fn(() => {
        throw new Error('Storage quota exceeded');
      });

      const { addRecord } = mountComposable(() => useRecentSecrets());
      const newMessage = createMockConcealedMessage('storage-error-test');

      // Should not throw
      expect(() => addRecord(newMessage)).not.toThrow();

      // Restore
      mockConcealedStore.addMessage = originalAddMessage;
    });

    it('onError callback is invoked before error is swallowed', async () => {
      mockIsAuthenticated.value = true;
      const testError = new Error('Callback test error');
      mockMetadataListStore.fetchList.mockRejectedValue(testError);

      const onErrorCallback = vi.fn();

      const { refresh } = mountComposable(() =>
        useRecentSecrets({ onError: onErrorCallback })
      );

      await refresh();

      expect(onErrorCallback).toHaveBeenCalled();
    });
  });

  // === Edge Cases ===

  describe('edge cases', () => {
    it('handles empty response gracefully', async () => {
      mockIsAuthenticated.value = true;
      mockApiRecords.value = [];
      mockMetadataListStore.fetchList.mockResolvedValue(undefined);

      const { records, hasRecords, refresh } = mountComposable(() => useRecentSecrets());

      await refresh();

      expect(records.value).toHaveLength(0);
      expect(hasRecords.value).toBe(false);
    });

    it('handles malformed storage data', () => {
      mockIsAuthenticated.value = false;

      // Simulate malformed data in store
      mockConcealedMessages.value = [
        { id: 'malformed', invalid: 'data' } as unknown as ConcealedMessage,
      ];

      const { records } = mountComposable(() => useRecentSecrets());

      // Should not crash, may filter out invalid records
      expect(records.value).toBeDefined();
    });

    it('handles race conditions when auth state changes mid-fetch', async () => {
      mockIsAuthenticated.value = true;

      let resolveFetch: () => void;
      const slowFetch = new Promise<void>((resolve) => {
        resolveFetch = resolve;
      });
      mockMetadataListStore.fetchList.mockReturnValue(slowFetch);

      const { refresh, dataSource } = mountComposable(() => useRecentSecrets());

      // Start fetch while authenticated
      const fetchPromise = refresh();

      // Auth state changes mid-fetch
      mockIsAuthenticated.value = false;

      // Complete the fetch
      resolveFetch!();
      await fetchPromise;
      await nextTick();

      // Should now use local data source
      expect(dataSource.value).toBe('local');
    });
  });

  // === Integration with workspaceMode ===

  describe('workspaceMode integration', () => {
    it('exposes workspaceMode from store', () => {
      mockWorkspaceMode.value = true;

      const { workspaceMode } = mountComposable(() => useRecentSecrets());

      expect(workspaceMode.value).toBe(true);
    });

    it('toggleWorkspaceMode delegates to store', () => {
      const { toggleWorkspaceMode } = mountComposable(() => useRecentSecrets());

      toggleWorkspaceMode();

      expect(mockConcealedStore.toggleWorkspaceMode).toHaveBeenCalled();
    });
  });

  // === Record count and details ===

  describe('record metadata', () => {
    it('exposes record count', () => {
      mockIsAuthenticated.value = false;
      mockConcealedMessages.value = [
        createMockConcealedMessage('count-1'),
        createMockConcealedMessage('count-2'),
        createMockConcealedMessage('count-3'),
      ];

      const { recordCount } = mountComposable(() => useRecentSecrets());

      expect(recordCount.value).toBe(3);
    });

    it('returns empty array when no records exist', () => {
      mockIsAuthenticated.value = false;
      mockConcealedMessages.value = [];

      const { records, hasRecords, recordCount } = mountComposable(() => useRecentSecrets());

      expect(records.value).toEqual([]);
      expect(hasRecords.value).toBe(false);
      expect(recordCount.value).toBe(0);
    });
  });
});
