// src/tests/components/PrivacyDefaultsBar.spec.ts

import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createI18n } from 'vue-i18n';
import { ref } from 'vue';
import type { BrandSettings } from '@/schemas/models/domain';

// Mock usePrivacyOptions composable
const mockFormatDuration = vi.fn((seconds: number) => {
  if (seconds === 3600) return '1 hour';
  if (seconds === 86400) return '1 day';
  if (seconds === 604800) return '7 days';
  return `${seconds} seconds`;
});

vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: () => ({
    formatDuration: mockFormatDuration,
    lifetimeOptions: ref([]),
    state: ref({ passphraseVisibility: false, lifetimeOptions: [] }),
  }),
}));

// Mock OIcon component
const OIconStub = {
  name: 'OIcon',
  template: '<span class="o-icon" :data-name="name"></span>',
  props: ['collection', 'name', 'class', 'ariaLabel', 'ariaHidden'],
};

// Mock PrivacyDefaultsModal
const PrivacyDefaultsModalStub = {
  name: 'PrivacyDefaultsModal',
  template: '<div class="privacy-modal" v-if="isOpen"></div>',
  props: ['isOpen', 'brandSettings'],
  emits: ['close', 'save'],
};

// i18n messages for testing
const messages = {
  en: {
    web: {
      domains: {
        privacy_defaults: 'Privacy Defaults',
        privacy_defaults_icon: 'Privacy defaults icon',
        ttl_short: 'TTL',
        passphrase_short: 'Passphrase',
        notify_short: 'Notifications',
        required: 'Required',
        optional: 'Optional',
        enabled: 'Enabled',
        disabled: 'Disabled',
        custom: 'Custom',
        edit_defaults: 'Edit Defaults',
        global_default: 'Global',
      },
    },
  },
};

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages,
});

// Helper to create mount options
function createMountOptions(brandSettings: Partial<BrandSettings> = {}) {
  const defaultSettings: BrandSettings = {
    primary_color: '#dc4a22',
    font_family: 'sans',
    corner_style: 'rounded',
    button_text_light: false,
    allow_public_homepage: false,
    allow_public_api: false,
    default_ttl: undefined,
    passphrase_required: false,
    notify_enabled: false,
    ...brandSettings,
  };

  return {
    props: {
      brandSettings: defaultSettings,
      isLoading: false,
    },
    global: {
      plugins: [i18n],
      stubs: {
        OIcon: OIconStub,
        PrivacyDefaultsModal: PrivacyDefaultsModalStub,
      },
    },
  };
}

describe('PrivacyDefaultsBar', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // Dynamically import component after mocks are set up
  async function getComponent() {
    const module = await import(
      '@/apps/workspace/components/domains/PrivacyDefaultsBar.vue'
    );
    return module.default;
  }

  describe('TTL chip display', () => {
    it('shows global default when no TTL is set', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: undefined,
      }));

      const ttlChip = wrapper.text();
      expect(ttlChip).toContain('TTL');
      expect(ttlChip).toContain('Global');
    });

    it('shows formatted duration when TTL is set', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: 3600,
      }));

      expect(mockFormatDuration).toHaveBeenCalledWith(3600);
      expect(wrapper.text()).toContain('1 hour');
    });

    it('renders TTL chip with correct content when TTL is set', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: 86400,
      }));

      // Verify TTL chip renders with formatted duration
      const html = wrapper.html();
      expect(html).toContain('TTL');
      expect(html).toContain('1 day');
    });

    it('renders TTL chip with global default when TTL is not set', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: undefined,
      }));

      // Verify TTL chip renders with global default text
      const html = wrapper.html();
      expect(html).toContain('TTL');
      expect(html).toContain('Global');
    });
  });

  describe('passphrase chip display', () => {
    it('shows "Required" when passphrase is required', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        passphrase_required: true,
      }));

      expect(wrapper.text()).toContain('Passphrase');
      expect(wrapper.text()).toContain('Required');
    });

    it('shows "Optional" when passphrase is not required', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        passphrase_required: false,
      }));

      expect(wrapper.text()).toContain('Passphrase');
      expect(wrapper.text()).toContain('Optional');
    });

    it('renders passphrase chip with required content', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        passphrase_required: true,
      }));

      // Verify passphrase chip renders with Required text
      const html = wrapper.html();
      expect(html).toContain('Passphrase');
      expect(html).toContain('Required');
    });
  });

  describe('notify chip display', () => {
    it('shows "Enabled" when notifications are enabled', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        notify_enabled: true,
      }));

      expect(wrapper.text()).toContain('Notifications');
      expect(wrapper.text()).toContain('Enabled');
    });

    it('shows "Disabled" when notifications are disabled', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        notify_enabled: false,
      }));

      expect(wrapper.text()).toContain('Notifications');
      expect(wrapper.text()).toContain('Disabled');
    });
  });

  describe('custom settings indicator', () => {
    it('shows "Custom" badge when TTL is set', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: 3600,
      }));

      expect(wrapper.text()).toContain('Custom');
    });

    it('shows "Custom" badge when passphrase is required', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        passphrase_required: true,
      }));

      expect(wrapper.text()).toContain('Custom');
    });

    it('shows "Custom" badge when notifications are enabled', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        notify_enabled: true,
      }));

      expect(wrapper.text()).toContain('Custom');
    });

    it('does not show "Custom" badge when all defaults are used', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions({
        default_ttl: null,
        passphrase_required: false,
        notify_enabled: false,
      }));

      expect(wrapper.text()).not.toContain('Custom');
    });
  });

  describe('loading state', () => {
    it('shows skeleton loaders when loading', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, {
        ...createMountOptions(),
        props: {
          brandSettings: {
            primary_color: '#dc4a22',
            default_ttl: undefined,
            passphrase_required: false,
            notify_enabled: false,
          },
          isLoading: true,
        },
      });

      const skeletons = wrapper.findAll('.animate-pulse');
      expect(skeletons.length).toBe(3);
    });

    it('hides chips when loading', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, {
        ...createMountOptions(),
        props: {
          brandSettings: {
            primary_color: '#dc4a22',
            default_ttl: 3600,
            passphrase_required: true,
            notify_enabled: true,
          },
          isLoading: true,
        },
      });

      expect(wrapper.text()).not.toContain('1 hour');
      expect(wrapper.text()).not.toContain('Required');
      expect(wrapper.text()).not.toContain('Enabled');
    });

    it('disables edit button when loading', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, {
        ...createMountOptions(),
        props: {
          brandSettings: {
            primary_color: '#dc4a22',
          },
          isLoading: true,
        },
      });

      const button = wrapper.find('button');
      expect(button.attributes('disabled')).toBeDefined();
    });
  });

  describe('edit button interaction', () => {
    it('opens modal when edit button is clicked', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions());

      expect(wrapper.find('.privacy-modal').exists()).toBe(false);

      await wrapper.find('button').trigger('click');

      expect(wrapper.find('.privacy-modal').exists()).toBe(true);
    });

    it('displays edit button text correctly', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions());

      // Find button with type="button" (the edit button)
      const buttons = wrapper.findAll('button[type="button"]');
      const editButton = buttons.find((b) => b.text().includes('Edit'));
      expect(editButton).toBeDefined();
      expect(editButton?.text()).toContain('Edit Defaults');
    });
  });

  describe('update event emission', () => {
    it('emits update event when modal saves', async () => {
      const PrivacyDefaultsBar = await getComponent();
      const wrapper = mount(PrivacyDefaultsBar, createMountOptions());

      // Open modal
      await wrapper.find('button').trigger('click');

      // Simulate modal save
      const modal = wrapper.findComponent(PrivacyDefaultsModalStub);
      const newSettings = { default_ttl: 7200 };
      modal.vm.$emit('save', newSettings);

      expect(wrapper.emitted('update')).toBeTruthy();
      expect(wrapper.emitted('update')?.[0]).toEqual([newSettings]);
    });
  });
});
