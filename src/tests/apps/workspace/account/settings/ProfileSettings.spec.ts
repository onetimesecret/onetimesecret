// src/tests/apps/workspace/account/settings/ProfileSettings.spec.ts
//
// Tests for ProfileSettings mount-time behavior.

import ProfileSettings from '@/apps/workspace/account/settings/ProfileSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { createTestI18n } from '@tests/setup';

// vue-router stubs
vi.mock('vue-router', () => ({
  useRoute: () => ({ path: '/account/settings/profile' }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Child components mocked away to keep the test focused
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />', props: ['collection', 'name', 'class'] },
}));
vi.mock('@/shared/components/ui/LanguageToggle.vue', () => ({
  default: { name: 'LanguageToggle', template: '<div class="language-toggle" />' },
}));
vi.mock('@/shared/components/ui/ThemeToggle.vue', () => ({
  default: {
    name: 'ThemeToggle',
    template: '<div class="theme-toggle" />',
    props: ['disabled', 'ariaBusy'],
    emits: ['theme-changed'],
  },
}));
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: { name: 'SettingsLayout', template: '<div class="mock-settings-layout"><slot /></div>' },
}));

// useAccount composable
const fetchAccountInfo = vi.fn().mockResolvedValue(undefined);
vi.mock('@/shared/composables/useAccount', () => ({
  useAccount: () => ({
    accountInfo: ref({ email_verified: true, created_at: '2024-01-01T00:00:00Z' }),
    fetchAccountInfo,
  }),
}));

// Bootstrap store — exposes i18n_enabled / has_password via storeToRefs
const bootstrapStore = {
  email: 'user@example.com',
  i18n_enabled: ref(false),
  has_password: ref(true),
};
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => bootstrapStore,
}));

const i18n = createTestI18n();

describe('ProfileSettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    bootstrapStore.has_password.value = true;
    bootstrapStore.i18n_enabled.value = false;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = () =>
    mount(ProfileSettings, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({ createSpy: vi.fn, stubActions: false }),
        ],
      },
    });

  describe('On mount', () => {
    it('fetches account info exactly once', async () => {
      wrapper = mountComponent();
      await flushPromises();

      expect(fetchAccountInfo).toHaveBeenCalledTimes(1);
    });
  });
});
