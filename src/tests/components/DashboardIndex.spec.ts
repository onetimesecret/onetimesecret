// src/tests/components/DashboardIndex.spec.ts

import { mount, flushPromises } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi, afterEach } from 'vitest';
import { computed } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { createTestI18n } from '@tests/setup';

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

// Form state the WorkspaceSecretForm stub exposes, mutable per test
const mockFormState = { displayType: 'text' };
const mockUpdateDisplayType = vi.fn();

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
      currentDisplayType: computed(() => mockFormState.displayType),
      updateTtl: vi.fn(),
      updatePassphrase: vi.fn(),
      updateDisplayType: mockUpdateDisplayType,
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
    '<div class="privacy-options-bar-stub" data-testid="privacy-bar">Privacy Options Bar<slot name="trailing" /></div>',
  props: ['currentTtl', 'currentPassphrase', 'isSubmitting'],
  emits: ['update:ttl', 'update:passphrase'],
};

const UpgradeBannerStub = {
  name: 'UpgradeBanner',
  template: '<div class="upgrade-banner-stub">Upgrade Banner</div>',
};

// i18n setup
const i18n = createTestI18n();

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
    mockFormState.displayType = 'text';
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

    it('shows privacy bar even when domain context is not active', async () => {
      mockDomainContextState.isContextActive = false;

      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      // Privacy bar is always rendered (controls TTL/passphrase for all users)
      expect(wrapper.find('[data-testid="privacy-bar"]').exists()).toBe(true);
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

  describe('Markdown toggle', () => {
    const TOGGLE = '[data-testid="secret-markdown-toggle"]';

    it('renders in the privacy bar row, not inside the form', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find(`[data-testid="privacy-bar"] ${TOGGLE}`).exists()).toBe(true);
    });

    it("reflects the form's display type", async () => {
      mockFormState.displayType = 'markdown';
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();

      expect(wrapper.find(TOGGLE).attributes('aria-checked')).toBe('true');
    });

    it('updates the form when toggled', async () => {
      const DashboardIndex = await getComponent();
      const wrapper = mount(DashboardIndex, createMountOptions());

      await flushPromises();
      await wrapper.find(TOGGLE).trigger('click');

      expect(mockUpdateDisplayType).toHaveBeenCalledWith('markdown');
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
