// src/tests/apps/secret/components/RecentSecretsTable.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref, computed } from 'vue';
import { createTestingPinia } from '@pinia/testing';

import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import type { ConcealedMessage } from '@/types/ui/concealed-message';

// Create mock ConcealedMessage for testing
const createMockConcealedMessage = (id: string): ConcealedMessage => ({
  id,
  receipt_identifier: `metadata-${id}`,
  secret_identifier: `secret-${id}`,
  secretLink: `https://example.com/secret/${id}`,
  metadataLink: `https://example.com/private/${id}`,
  clientInfo: {
    createdAt: new Date(),
    ttl: 604800,
    hasPassphrase: false,
  },
  response: {
    success: true,
    record: {
      key: `key-${id}`,
      shortid: `short-${id}`,
      state: 'new',
      identifier: `id-${id}`,
      created: new Date(),
      updated: new Date(),
      metadata: {
        secret_ttl: 604800,
        share_domain: 'example.com',
        identifier: `metadata-${id}`,
      },
      secret: {
        secret_ttl: 604800,
        identifier: `secret-${id}`,
      },
    },
  },
});

// Create mock RecentSecretRecord from ConcealedMessage
const createMockRecord = (id: string): RecentSecretRecord => {
  const message = createMockConcealedMessage(id);
  return {
    id,
    extid: `metadata-${id}`,
    shortid: `short-${id}`,
    secretExtid: `secret-${id}`,
    hasPassphrase: false,
    ttl: 604800,
    createdAt: new Date(),
    shareDomain: 'example.com',
    isViewed: false,
    isReceived: false,
    isBurned: false,
    isExpired: false,
    source: 'local',
    originalRecord: message,
  };
};

// Mock state refs
const mockRecords = ref<RecentSecretRecord[]>([createMockRecord('msg-1')]);
const mockHasRecords = computed(() => mockRecords.value.length > 0);
const mockWorkspaceMode = ref(false);
const mockIsLoading = ref(false);
const mockError = ref(null);
const mockIsAuthenticated = ref(false);

const mockToggleWorkspaceMode = vi.fn(() => {
  mockWorkspaceMode.value = !mockWorkspaceMode.value;
});

const mockClear = vi.fn(() => {
  mockRecords.value = [];
});

const mockFetch = vi.fn();

// Mock useRecentSecrets composable
vi.mock('@/shared/composables/useRecentSecrets', () => ({
  useRecentSecrets: vi.fn(() => ({
    records: mockRecords,
    hasRecords: mockHasRecords,
    workspaceMode: mockWorkspaceMode,
    isLoading: mockIsLoading,
    error: mockError,
    isAuthenticated: mockIsAuthenticated,
    toggleWorkspaceMode: mockToggleWorkspaceMode,
    clear: mockClear,
    fetch: mockFetch,
  })),
}));

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string, params?: Record<string, unknown>) => {
      if (params) {
        return `${key} ${JSON.stringify(params)}`;
      }
      return key;
    }),
  })),
}));

// Stub SecretLinksTable component
const SecretLinksTableStub = {
  name: 'SecretLinksTable',
  template: '<div class="secret-links-table-stub" data-testid="secret-links-table"></div>',
  props: ['concealedMessages', 'ariaLabelledby'],
};

describe('RecentSecretsTable', () => {
  beforeEach(() => {
    mockRecords.value = [createMockRecord('msg-1')];
    mockWorkspaceMode.value = false;
    mockIsLoading.value = false;
    mockError.value = null;
    mockIsAuthenticated.value = false;
    mockToggleWorkspaceMode.mockClear();
    mockClear.mockClear();
    mockFetch.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  async function mountComponent(props = {}) {
    vi.resetModules();

    // Re-mock with current state
    vi.doMock('@/shared/composables/useRecentSecrets', () => ({
      useRecentSecrets: vi.fn(() => ({
        records: mockRecords,
        hasRecords: mockHasRecords,
        workspaceMode: mockWorkspaceMode,
        isLoading: mockIsLoading,
        error: mockError,
        isAuthenticated: mockIsAuthenticated,
        toggleWorkspaceMode: mockToggleWorkspaceMode,
        clear: mockClear,
        fetch: mockFetch,
      })),
    }));

    const { default: RecentSecretsTable } = await import(
      '@/apps/secret/components/RecentSecretsTable.vue'
    );

    return mount(RecentSecretsTable, {
      props: {
        ...props,
      },
      global: {
        plugins: [createTestingPinia({ createSpy: vi.fn })],
        stubs: {
          SecretLinksTable: SecretLinksTableStub,
        },
        mocks: {
          $t: (key: string) => key,
        },
      },
    });
  }

  describe('initialization', () => {
    it('calls fetch on mount', async () => {
      await mountComponent();
      await flushPromises();

      expect(mockFetch).toHaveBeenCalledOnce();
    });
  });

  describe('showWorkspaceModeToggle prop', () => {
    it('defaults to true', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const checkbox = wrapper.find('input[type="checkbox"]');
      expect(checkbox.exists()).toBe(true);
    });

    it('shows checkbox when showWorkspaceModeToggle is true', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: true });
      await flushPromises();

      const checkbox = wrapper.find('input[type="checkbox"]');
      expect(checkbox.exists()).toBe(true);
    });

    it('hides checkbox when showWorkspaceModeToggle is false', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: false });
      await flushPromises();

      const checkbox = wrapper.find('input[type="checkbox"]');
      expect(checkbox.exists()).toBe(false);
    });

    it('hides workspace mode controls when showWorkspaceModeToggle is false', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: false });
      await flushPromises();

      const labels = wrapper.findAll('label');
      const workspaceModeLabel = labels.find((l) =>
        l.text().includes('web.secrets.workspace_mode')
      );
      expect(workspaceModeLabel).toBeUndefined();
    });

    it('shows the workspace mode label when toggle is visible', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: true });
      await flushPromises();

      const label = wrapper.find('label');
      expect(label.exists()).toBe(true);
      expect(label.text()).toContain('web.secrets.workspace_mode');
    });
  });

  describe('checkbox functionality', () => {
    it('calls toggleWorkspaceMode when checkbox is changed', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: true });
      await flushPromises();

      const checkbox = wrapper.find('input[type="checkbox"]');
      expect(checkbox.exists()).toBe(true);

      await checkbox.trigger('change');

      expect(mockToggleWorkspaceMode).toHaveBeenCalledOnce();
    });

    it('has title attribute for accessibility on label', async () => {
      const wrapper = await mountComponent({ showWorkspaceModeToggle: true });
      await flushPromises();

      const label = wrapper.find('label');
      expect(label.attributes('title')).toBe(
        'web.secrets.workspace_mode_description'
      );
    });

    it('checkbox reflects false workspaceMode state', async () => {
      mockWorkspaceMode.value = false;
      const wrapper = await mountComponent({ showWorkspaceModeToggle: true });
      await flushPromises();

      const checkbox = wrapper.find('input[type="checkbox"]');
      expect((checkbox.element as HTMLInputElement).checked).toBe(false);
    });
  });

  describe('section rendering', () => {
    it('renders section with proper aria-labelledby', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const section = wrapper.find('section');
      expect(section.exists()).toBe(true);
      expect(section.attributes('aria-labelledby')).toBe('recent-secrets-heading');
    });

    it('renders heading with correct text', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const heading = wrapper.find('h2');
      expect(heading.exists()).toBe(true);
      expect(heading.text()).toContain('web.COMMON.recent');
    });

    it('shows items count when records exist', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const html = wrapper.html();
      expect(html).toContain('web.LABELS.items_count');
    });

    it('renders dismiss button', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const dismissButton = wrapper.find('button[type="button"]');
      expect(dismissButton.exists()).toBe(true);
    });

    it('calls clear when dismiss button is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const dismissButton = wrapper.find('button[type="button"]');
      await dismissButton.trigger('click');

      expect(mockClear).toHaveBeenCalledOnce();
    });

    it('renders child table within the region container', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
      expect(region.element.children.length).toBeGreaterThan(0);
    });

    it('renders region with aria-live for accessibility', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
      expect(region.attributes('aria-live')).toBe('polite');
    });
  });

  describe('empty state', () => {
    it('hides header controls when no records exist', async () => {
      mockRecords.value = [];

      const wrapper = await mountComponent();
      await flushPromises();

      const heading = wrapper.find('h2');
      expect(heading.exists()).toBe(false);
    });

    it('still renders the table container when empty', async () => {
      mockRecords.value = [];

      const wrapper = await mountComponent();
      await flushPromises();

      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
    });
  });

  describe('data source filtering', () => {
    it('handles mixed source records without crashing', async () => {
      // Add API source record
      const apiRecord: RecentSecretRecord = {
        id: 'api-1',
        extid: 'api-metadata-1',
        shortid: 'api-short-1',
        secretExtid: 'api-secret-1',
        hasPassphrase: true,
        ttl: 3600,
        createdAt: new Date(),
        shareDomain: 'api.example.com',
        isViewed: true,
        isReceived: false,
        isBurned: false,
        isExpired: false,
        source: 'api',
        originalRecord: {} as ConcealedMessage, // API records have MetadataRecords
      };

      mockRecords.value = [createMockRecord('local-1'), apiRecord];

      const wrapper = await mountComponent();
      await flushPromises();

      // Verify component renders without error with mixed sources
      // The SecretLinksTable stub is inside the region container
      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
      expect(region.element.children.length).toBeGreaterThan(0);
    });
  });
});
