// src/tests/apps/workspace/components/forms/PrivacyOptionsBar.spec.ts

//
// Note: Workspace mode toggle tests moved to WorkspaceSecretForm.spec.ts
// as the toggle was relocated to be near the Create Link button.

import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import { afterEach, describe, expect, it, vi } from 'vitest';

// Mock usePrivacyOptions composable
vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: vi.fn(() => ({
    formatDuration: vi.fn((seconds: number) => {
      if (seconds === 3600) return '1 hour';
      if (seconds === 86400) return '1 day';
      if (seconds === 604800) return '7 days';
      return `${seconds}s`;
    }),
    // Must be a computed/ref since TtlSelector accesses .value
    lifetimeOptions: computed(() => [
      { value: 3600, label: '1 hour' },
      { value: 86400, label: '1 day' },
      { value: 604800, label: '7 days' },
    ]),
    state: ref({
      passphraseVisibility: false,
      lifetimeOptions: [],
    }),
    togglePassphraseVisibility: vi.fn(),
  })),
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
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                secret_options: {
                  passphrase: { minimum_length: 6 },
                },
              },
            },
          }),
        ],
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

  // Note: Workspace mode toggle tests removed - toggle moved to WorkspaceSecretForm

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

      // Click to open dropdown (first button is TTL ListboxButton)
      const buttons = wrapper.findAll('button');
      const ttlButton = buttons[0];
      await ttlButton.trigger('click');
      await flushPromises();

      // Headless UI Listbox adds aria-expanded="true" when open
      expect(ttlButton.attributes('aria-expanded')).toBe('true');

      // ListboxOptions should now be visible (has .absolute.bottom-full classes)
      const dropdown = wrapper.find('[role="listbox"]');
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
      expect(ttlButton.attributes('aria-expanded')).toBe('true');

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
