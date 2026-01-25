// src/tests/components/DashboardIndex.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { computed } from 'vue';
import { createTestingPinia } from '@pinia/testing';

// Shared mock state that can be mutated per test
interface MockDomainContextState {
  currentContext: {
    domain: string;
    extid: string | undefined;
    displayName: string;
    isCanonical: boolean;
  };
  isContextActive: boolean;
}

const mockDomainContextState: MockDomainContextState = {
  currentContext: {
    domain: 'custom.example.com',
    extid: 'cd123abc',
    displayName: 'custom.example.com',
    isCanonical: false,
  },
  isContextActive: true,
};

// Mock useDomainContext - returns fresh refs that read from shared state
vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: () => ({
    currentContext: computed(() => mockDomainContextState.currentContext),
    isContextActive: computed(() => mockDomainContextState.isContextActive),
    hasMultipleContexts: computed(() => true),
    availableDomains: computed(() => [
      'custom.example.com',
      'onetimesecret.com',
    ]),
    setContext: vi.fn(),
  }),
}));

// Stub child components
const WorkspaceSecretFormStub = {
  name: 'WorkspaceSecretForm',
  template:
    '<div class="workspace-secret-form-stub">Workspace Secret Form</div>',
  setup() {
    return {
      currentTtl: computed(() => 604800),
      currentPassphrase: computed(() => ''),
      isSubmitting: computed(() => false),
      updateTtl: vi.fn(),
      updatePassphrase: vi.fn(),
    };
  },
};

const RecentSecretsTableStub = {
  name: 'RecentSecretsTable',
  template: '<div class="recent-secrets-stub">Recent Secrets</div>',
};

const PrivacyOptionsBarStub = {
  name: 'PrivacyOptionsBar',
  template:
    '<div class="privacy-options-bar-stub" data-testid="privacy-bar">Privacy Options Bar</div>',
  props: ['currentTtl', 'currentPassphrase', 'isSubmitting'],
  emits: ['update:ttl', 'update:passphrase'],
};

const UpgradeBannerStub = {
  name: 'UpgradeBanner',
  template: '<div class="upgrade-banner-stub">Upgrade Banner</div>',
};

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: {} },
});

describe('DashboardIndex', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    // Reset modules to ensure fresh component instance with new mock state
    vi.resetModules();
    // Reset mock state to defaults
    mockDomainContextState.currentContext = {
      domain: 'custom.example.com',
      extid: 'cd123abc',
      displayName: 'custom.example.com',
      isCanonical: false,
    };
    mockDomainContextState.isContextActive = true;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  async function getComponent() {
    // Re-import after resetModules to pick up fresh mock state
    const module = await import(
      '@/apps/workspace/dashboard/DashboardIndex.vue'
    );
    return module.default;
  }

  function createMountOptions() {
    return {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              bootstrap: {
                cust: { feature_flags: { beta: false } },
                secret_options: {
                  default_ttl: 604800,
                  ttl_options: [3600, 86400, 604800],
                  passphrase: { required: false, minimum_length: 6 },
                },
              },
            },
          }),
        ],
        stubs: {
          WorkspaceSecretForm: WorkspaceSecretFormStub,
          RecentSecretsTable: RecentSecretsTableStub,
          PrivacyOptionsBar: PrivacyOptionsBarStub,
          UpgradeBanner: UpgradeBannerStub,
        },
      },
    };
  }

  describe('privacy bar visibility', () => {
    it('shows privacy bar when domain context is active', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find('[data-testid="privacy-bar"]').exists()).toBe(true);
    }, 10000);

    it('hides privacy bar when domain context is not active', async () => {
      mockDomainContextState.isContextActive = false;

      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find('[data-testid="privacy-bar"]').exists()).toBe(false);
    });

    it('shows privacy bar for canonical domain', async () => {
      mockDomainContextState.currentContext = {
        domain: 'onetimesecret.com',
        extid: undefined,
        displayName: 'onetimesecret.com',
        isCanonical: true,
      };

      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      // Privacy bar should be visible for canonical domain too
      expect(wrapper.find('[data-testid="privacy-bar"]').exists()).toBe(true);
    });
  });

  describe('privacy bar props', () => {
    it('passes current TTL to privacy bar', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      const privacyBar = wrapper.findComponent(PrivacyOptionsBarStub);
      // Default TTL from secret_options mock is 604800
      expect(privacyBar.props('currentTtl')).toBe(604800);
    });

    it('passes current passphrase to privacy bar', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      const privacyBar = wrapper.findComponent(PrivacyOptionsBarStub);
      expect(privacyBar.props('currentPassphrase')).toBe('');
    });
  });

  describe('other dashboard components', () => {
    it('always renders WorkspaceSecretForm', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find('.workspace-secret-form-stub').exists()).toBe(true);
    });

    it('always renders UpgradeBanner', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find('.upgrade-banner-stub').exists()).toBe(true);
    });
  });
});
