// src/tests/apps/secret/components/RecentSecretsTable.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ref } from 'vue';
import { createTestingPinia } from '@pinia/testing';

// Mock store state
const mockWorkspaceMode = ref(false);
const mockHasMessages = ref(true);
const mockConcealedMessages = ref([
  {
    id: 'msg-1',
    secret_identifier: 'abc123',
    secretLink: 'https://example.com/secret/abc123',
    metadataLink: 'https://example.com/private/abc123',
    clientInfo: {
      createdAt: new Date(),
      ttl: 604800,
      hasPassphrase: false,
    },
    response: {
      record: {
        metadata: {
          secret_ttl: 604800,
          share_domain: 'example.com',
        },
      },
    },
  },
]);

const mockToggleWorkspaceMode = vi.fn(() => {
  mockWorkspaceMode.value = !mockWorkspaceMode.value;
});

const mockClearMessages = vi.fn(() => {
  mockConcealedMessages.value = [];
  mockHasMessages.value = false;
});

const mockInit = vi.fn();

// Mock concealedMetadataStore
vi.mock('@/shared/stores/concealedMetadataStore', () => ({
  useConcealedMetadataStore: vi.fn(() => ({
    workspaceMode: mockWorkspaceMode.value,
    hasMessages: mockHasMessages.value,
    concealedMessages: mockConcealedMessages.value,
    isInitialized: true,
    toggleWorkspaceMode: mockToggleWorkspaceMode,
    clearMessages: mockClearMessages,
    init: mockInit,
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

// Stub SecretLinksTable component - must be a complete stub to avoid child rendering
const SecretLinksTableStub = {
  name: 'SecretLinksTable',
  template: '<div class="secret-links-table-stub" data-testid="secret-links-table"></div>',
  props: ['concealedMessages', 'ariaLabelledby'],
};

describe('RecentSecretsTable', () => {
  beforeEach(() => {
    mockWorkspaceMode.value = false;
    mockHasMessages.value = true;
    mockConcealedMessages.value = [
      {
        id: 'msg-1',
        secret_identifier: 'abc123',
        secretLink: 'https://example.com/secret/abc123',
        metadataLink: 'https://example.com/private/abc123',
        clientInfo: {
          createdAt: new Date(),
          ttl: 604800,
          hasPassphrase: false,
        },
        response: {
          record: {
            metadata: {
              secret_ttl: 604800,
              share_domain: 'example.com',
            },
          },
        },
      },
    ];
    mockToggleWorkspaceMode.mockClear();
    mockClearMessages.mockClear();
    mockInit.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  async function mountComponent(props = {}) {
    // Reset modules to get fresh component with current mock state
    vi.resetModules();

    // Re-mock with current state values
    vi.doMock('@/shared/stores/concealedMetadataStore', () => ({
      useConcealedMetadataStore: vi.fn(() => ({
        workspaceMode: mockWorkspaceMode.value,
        hasMessages: mockHasMessages.value,
        concealedMessages: mockConcealedMessages.value,
        isInitialized: true,
        toggleWorkspaceMode: mockToggleWorkspaceMode,
        clearMessages: mockClearMessages,
        init: mockInit,
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

  describe('showWorkspaceModeToggle prop', () => {
    it('defaults to true', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Checkbox should be visible by default
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

      // The workspace mode label should not exist when toggle is hidden
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

    it('shows items count when messages exist', async () => {
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

    it('calls clearMessages when dismiss button is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const dismissButton = wrapper.find('button[type="button"]');
      await dismissButton.trigger('click');

      expect(mockClearMessages).toHaveBeenCalledOnce();
    });

    it('renders child table within the region container', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // The region should contain the SecretLinksTable (stubbed or real)
      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
      // Region should have children (the table component)
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
    it('hides header controls when no messages exist', async () => {
      mockHasMessages.value = false;
      mockConcealedMessages.value = [];

      const wrapper = await mountComponent();
      await flushPromises();

      // Header section with controls should not exist
      const heading = wrapper.find('h2');
      expect(heading.exists()).toBe(false);
    });

    it('still renders the table container when empty', async () => {
      mockHasMessages.value = false;
      mockConcealedMessages.value = [];

      const wrapper = await mountComponent();
      await flushPromises();

      // The table region should still exist
      const region = wrapper.find('[role="region"]');
      expect(region.exists()).toBe(true);
    });
  });
});
