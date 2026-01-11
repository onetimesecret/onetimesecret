// src/tests/apps/workspace/components/forms/PrivacyOptionsBar.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

// Mock store state
const mockWorkspaceMode = ref(false);
const mockToggleWorkspaceMode = vi.fn(() => {
  mockWorkspaceMode.value = !mockWorkspaceMode.value;
});

// Mock concealedMetadataStore
vi.mock('@/shared/stores/concealedMetadataStore', () => ({
  useConcealedMetadataStore: vi.fn(() => ({
    workspaceMode: mockWorkspaceMode.value,
    toggleWorkspaceMode: mockToggleWorkspaceMode,
  })),
}));

// Mock usePrivacyOptions composable
vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: vi.fn(() => ({
    formatDuration: vi.fn((seconds: number) => {
      if (seconds === 3600) return '1 hour';
      if (seconds === 86400) return '1 day';
      if (seconds === 604800) return '7 days';
      return `${seconds}s`;
    }),
    lifetimeOptions: [
      { value: 3600, label: '1 hour' },
      { value: 86400, label: '1 day' },
      { value: 604800, label: '7 days' },
    ],
  })),
}));

// Mock WindowService
vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn((key: string) => {
      if (key === 'secret_options') {
        return {
          passphrase: { minimum_length: 6 },
        };
      }
      return null;
    }),
  },
}));

// Mock vue-i18n
vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

// Stub OIcon component
const OIconStub = {
  name: 'OIcon',
  template: '<span class="icon-stub"></span>',
  props: ['collection', 'name'],
};

describe('PrivacyOptionsBar', () => {
  beforeEach(() => {
    mockWorkspaceMode.value = false;
    mockToggleWorkspaceMode.mockClear();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  async function mountComponent(props = {}) {
    const { default: PrivacyOptionsBar } =
      await import('@/apps/workspace/components/forms/PrivacyOptionsBar.vue');

    return mount(PrivacyOptionsBar, {
      props: {
        currentTtl: 604800,
        currentPassphrase: '',
        ...props,
      },
      global: {
        plugins: [createTestingPinia({ createSpy: vi.fn })],
        stubs: {
          OIcon: OIconStub,
          Teleport: true,
        },
        mocks: {
          $t: (key: string) => key,
        },
      },
    });
  }

  describe('workspace mode toggle chip', () => {
    it('renders the workspace mode toggle button', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Find button containing the workspace mode translation key
      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      expect(workspaceModeButton?.exists()).toBe(true);
    });

    it('calls toggleWorkspaceMode when workspace mode button is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Find the workspace mode button (last button in the chips)
      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      expect(workspaceModeButton?.exists()).toBe(true);
      await workspaceModeButton?.trigger('click');

      expect(mockToggleWorkspaceMode).toHaveBeenCalledOnce();
    });

    it('has correct title attribute for accessibility', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      expect(workspaceModeButton?.attributes('title')).toBe(
        'web.secrets.workspace_mode_description'
      );
    });

    it('is disabled when isSubmitting is true', async () => {
      const wrapper = await mountComponent({ isSubmitting: true });
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      expect(workspaceModeButton?.attributes('disabled')).toBeDefined();
    });

    it('is enabled when isSubmitting is false', async () => {
      const wrapper = await mountComponent({ isSubmitting: false });
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      expect(workspaceModeButton?.attributes('disabled')).toBeUndefined();
    });
  });

  describe('workspace mode styling', () => {
    it('applies inactive styling when workspace mode is off', async () => {
      mockWorkspaceMode.value = false;
      const wrapper = await mountComponent();
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      // When workspaceMode is false, should have gray styling
      expect(workspaceModeButton?.classes()).toContain('bg-gray-50');
    });

    it('applies active styling when workspace mode is on', async () => {
      // Need to re-import with updated mock
      vi.resetModules();

      // Update mock to return true for workspaceMode
      vi.doMock('@/shared/stores/concealedMetadataStore', () => ({
        useConcealedMetadataStore: vi.fn(() => ({
          workspaceMode: true,
          toggleWorkspaceMode: mockToggleWorkspaceMode,
        })),
      }));

      const { default: PrivacyOptionsBar } =
        await import('@/apps/workspace/components/forms/PrivacyOptionsBar.vue');

      const wrapper = mount(PrivacyOptionsBar, {
        props: {
          currentTtl: 604800,
          currentPassphrase: '',
        },
        global: {
          plugins: [createTestingPinia({ createSpy: vi.fn })],
          stubs: {
            OIcon: OIconStub,
            Teleport: true,
          },
          mocks: {
            $t: (key: string) => key,
          },
        },
      });

      await flushPromises();

      const buttons = wrapper.findAll('button');
      const workspaceModeButton = buttons.find((btn) =>
        btn.text().includes('web.secrets.workspace_mode')
      );

      // When workspaceMode is true, should have brand styling
      expect(workspaceModeButton?.classes()).toContain('bg-brand-50');
    });
  });

  describe('TTL dropdown', () => {
    it('displays the formatted TTL value', async () => {
      const wrapper = await mountComponent({ currentTtl: 604800 });
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const ttlButton = buttons[0]; // First button is TTL

      expect(ttlButton.text()).toContain('7 days');
    });

    it('opens dropdown when TTL chip is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Initially dropdown should not be visible
      expect(wrapper.find('.absolute.left-0.top-full').exists()).toBe(false);

      // Click to open dropdown
      const buttons = wrapper.findAll('button');
      const ttlButton = buttons[0];
      await ttlButton.trigger('click');
      await flushPromises();

      // Dropdown should now be visible (the v-if renders it)
      const dropdown = wrapper.find('.origin-top-left.rounded-md');
      expect(dropdown.exists()).toBe(true);
    });

    it('closes TTL dropdown when passphrase chip is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const ttlButton = buttons[0];
      const passphraseButton = buttons.find((btn) =>
        btn.text().includes('web.COMMON.secret_passphrase')
      );

      // Open TTL dropdown
      await ttlButton.trigger('click');
      await flushPromises();
      expect(wrapper.find('.origin-top-left.rounded-md').exists()).toBe(true);

      // Click passphrase to close TTL and open passphrase
      await passphraseButton?.trigger('click');
      await flushPromises();

      // TTL dropdown should be closed (passphrase input opens instead)
      const input = wrapper.find('input[type="password"]');
      expect(input.exists()).toBe(true);
    });
  });

  describe('passphrase chip', () => {
    it('displays passphrase label', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      const buttons = wrapper.findAll('button');
      const passphraseButton = buttons.find((btn) =>
        btn.text().includes('web.COMMON.secret_passphrase')
      );

      expect(passphraseButton?.exists()).toBe(true);
    });

    it('opens passphrase input when passphrase chip is clicked', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Click passphrase chip to open input
      const buttons = wrapper.findAll('button');
      const passphraseButton = buttons.find((btn) =>
        btn.text().includes('web.COMMON.secret_passphrase')
      );
      await passphraseButton?.trigger('click');
      await flushPromises();

      // Input should now be visible
      const input = wrapper.find('input[type="password"]');
      expect(input.exists()).toBe(true);
    });

    it('shows passphrase visibility toggle button', async () => {
      const wrapper = await mountComponent();
      await flushPromises();

      // Open passphrase input
      const buttons = wrapper.findAll('button');
      const passphraseButton = buttons.find((btn) =>
        btn.text().includes('web.COMMON.secret_passphrase')
      );
      await passphraseButton?.trigger('click');
      await flushPromises();

      // Find the visibility toggle button (it has eye icon)
      const toggleButton = wrapper.find('[aria-label="Show passphrase"]');
      expect(toggleButton.exists()).toBe(true);
    });
  });
});
