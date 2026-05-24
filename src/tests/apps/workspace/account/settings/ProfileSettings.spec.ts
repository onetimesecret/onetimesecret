// src/tests/apps/workspace/account/settings/ProfileSettings.spec.ts
//
// Tests for ProfileSettings entitlements refresh behavior.
//
// Mount-time: entitlements load once for the default org.
// Org-switch (contract): when defaultOrg.extid changes, the component
// must call organizationStore.fetchEntitlements with the new extid.
// Standalone mode (billing disabled): no fetch is attempted.

import ProfileSettings from '@/apps/workspace/account/settings/ProfileSettings.vue';
import { createTestingPinia } from '@pinia/testing';
import { flushPromises, mount, VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';
import { createI18n } from 'vue-i18n';

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

// Child components mocked away to keep the test focused on watcher behavior
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

// Organizations are exposed via storeToRefs(organizationStore), so the
// store mock returns a ref that we can mutate per test.
const orgsRef = ref<Array<{ extid: string; is_default: boolean; entitlements?: string[] }>>([]);
const fetchOrganizations = vi.fn().mockResolvedValue(undefined);
const fetchEntitlements = vi.fn().mockResolvedValue(undefined);

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: orgsRef,
    fetchOrganizations,
    fetchEntitlements,
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

// Entitlements composable — drives isStandaloneMode and initDefinitions
const isStandaloneModeRef = ref(false);
const initDefinitions = vi.fn().mockResolvedValue(undefined);
vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    entitlements: ref([]),
    formatEntitlement: (k: string) => k,
    isStandaloneMode: isStandaloneModeRef,
    initDefinitions,
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
  missingWarn: false,
  fallbackWarn: false,
});

describe('ProfileSettings', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    orgsRef.value = [
      { extid: 'org_a', is_default: true, entitlements: [] },
    ];
    isStandaloneModeRef.value = false;
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
    it('fetches entitlements for the default org exactly once', async () => {
      wrapper = mountComponent();
      await flushPromises();

      expect(fetchEntitlements).toHaveBeenCalledTimes(1);
      expect(fetchEntitlements).toHaveBeenCalledWith('org_a');
    });
  });

  describe('Org switch (contract)', () => {
    it('refetches entitlements when defaultOrg.extid changes to a different org', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(fetchEntitlements).toHaveBeenCalledTimes(1);
      expect(fetchEntitlements).toHaveBeenLastCalledWith('org_a');

      // Switch the default org to a different organization
      orgsRef.value = [
        { extid: 'org_a', is_default: false, entitlements: [] },
        { extid: 'org_b', is_default: true, entitlements: [] },
      ];
      await nextTick();
      await flushPromises();

      expect(fetchEntitlements).toHaveBeenCalledTimes(2);
      expect(fetchEntitlements).toHaveBeenLastCalledWith('org_b');
    });

    it('does not refetch when defaultOrg object identity changes but extid stays the same', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(fetchEntitlements).toHaveBeenCalledTimes(1);

      // Replace the org object but keep the same extid
      orgsRef.value = [
        { extid: 'org_a', is_default: true, entitlements: [] },
      ];
      await nextTick();
      await flushPromises();

      expect(fetchEntitlements).toHaveBeenCalledTimes(1);
    });
  });

  describe('Standalone mode', () => {
    it('does not call fetchEntitlements on org switch when in standalone mode', async () => {
      isStandaloneModeRef.value = true;
      wrapper = mountComponent();
      await flushPromises();

      // Reset to isolate the watcher behavior from mount-time calls
      fetchEntitlements.mockClear();

      orgsRef.value = [
        { extid: 'org_a', is_default: false, entitlements: [] },
        { extid: 'org_b', is_default: true, entitlements: [] },
      ];
      await nextTick();
      await flushPromises();

      expect(fetchEntitlements).not.toHaveBeenCalled();
    });
  });
});
