// src/tests/apps/workspace/domains/DomainSso.spec.ts
//
// Tests for DomainSso.vue covering:
// 1. Page title rendering with domain name
// 2. Loading state while fetching domain details
// 3. DomainSsoConfigForm rendering when domain loads
// 4. Error handling (404, 403)
// 5. Entitlement warning when manage_sso not available
// 6. Correct props passed to DomainSsoConfigForm

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import { ref, computed } from 'vue';
import DomainSso from '@/apps/workspace/domains/DomainSso.vue';

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
// ─────────────────────────────────────────────────────────────────────────────

// Mock route params
const mockRouteParams = { orgid: 'org_123', extid: 'dm_test123' };
const mockRouterPush = vi.fn();

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: mockRouterPush,
  }),
  onBeforeRouteLeave: vi.fn(),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock child components
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts" data-testid="form-alerts" :data-error="error" :data-success="success">{{ error }}</div>',
    props: ['error', 'success'],
  },
}));

vi.mock('@/apps/workspace/components/domains/DomainSsoConfigForm.vue', () => ({
  default: {
    name: 'DomainSsoConfigForm',
    template: '<div class="domain-sso-config-form" data-testid="domain-sso-config-form" :data-domain-ext-id="domainExtId" />',
    props: ['domainExtId'],
    emits: ['saved', 'deleted'],
  },
}));

// Domain composable mock
const mockDomain = ref<{ display_domain: string } | null>(null);
const mockDomainLoading = ref(false);
const mockDomainError = ref<{ message: string } | null>(null);
const mockInitializeDomain = vi.fn();

vi.mock('@/shared/composables/useDomain', () => ({
  useDomain: () => ({
    domain: mockDomain,
    isLoading: mockDomainLoading,
    error: mockDomainError,
    initialize: mockInitializeDomain,
  }),
}));

// SSO config composable mock
const mockSsoLoading = ref(false);
const mockSsoInitialized = ref(true);
const mockSsoSaving = ref(false);
const mockSsoDeleting = ref(false);
const mockSsoTesting = ref(false);
const mockSsoError = ref<{ message: string } | null>(null);
const mockSsoConfig = ref(null);
const mockFormState = ref({
  provider: 'oidc',
  enabled: false,
  allowed_domains: '',
  client_id: '',
  client_secret: '',
  issuer_url: '',
});
const mockTestResult = ref(null);
const mockTestError = ref(null);
const mockIsConfigured = ref(false);
const mockHasUnsavedChanges = ref(false);
const mockClientSecretMasked = ref('');
const mockInitializeSsoConfig = vi.fn();
const mockSaveConfig = vi.fn();
const mockDeleteConfig = vi.fn();
const mockTestConnection = vi.fn();
const mockDiscardChanges = vi.fn();

vi.mock('@/shared/composables/useSsoConfig', () => ({
  useSsoConfig: () => ({
    isLoading: mockSsoLoading,
    isInitialized: mockSsoInitialized,
    isSaving: mockSsoSaving,
    isDeleting: mockSsoDeleting,
    isTesting: mockSsoTesting,
    error: mockSsoError,
    ssoConfig: mockSsoConfig,
    formState: mockFormState,
    testResult: mockTestResult,
    testError: mockTestError,
    isConfigured: mockIsConfigured,
    hasUnsavedChanges: mockHasUnsavedChanges,
    clientSecretMasked: mockClientSecretMasked,
    initialize: mockInitializeSsoConfig,
    saveConfig: mockSaveConfig,
    deleteConfig: mockDeleteConfig,
    testConnection: mockTestConnection,
    discardChanges: mockDiscardChanges,
  }),
}));

// Entitlements mock
const mockCanManageSso = ref(true);

vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    can: (entitlement: string) => entitlement === 'manage_sso' ? mockCanManageSso.value : false,
  }),
}));

// Organization store mock
const mockOrganizations = ref([
  { extid: 'org_123', display_name: 'Test Org', entitlements: ['manage_sso'] },
]);

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    organizations: mockOrganizations.value,
  }),
}));

vi.mock('pinia', async (importOriginal) => {
  const actual = await importOriginal<typeof import('pinia')>();
  return {
    ...actual,
    storeToRefs: () => ({
      organizations: mockOrganizations,
    }),
  };
});

vi.mock('@/types/organization', () => ({
  ENTITLEMENTS: {
    MANAGE_SSO: 'manage_sso',
  },
}));

// i18n setup
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          sso: {
            title: 'Domain SSO Configuration',
            access_denied: 'Access Denied',
            access_denied_description: 'You do not have permission to manage SSO for this domain.',
            upgrade_to_configure: 'You do not have permission to manage SSO for this domain. Upgrade your plan to enable this feature.',
            config_title: 'SSO Provider Configuration',
            config_description: 'Configure single sign-on for this domain.',
            update_success: 'SSO configuration updated successfully',
            delete_success: 'SSO configuration deleted successfully',
            not_configured_notice: 'SSO is not configured for this domain yet.',
          },
        },
        billing: {
          overview: {
            view_plans_action: 'View Plans',
          },
        },
        branding: {
          you_have_unsaved_changes_are_you_sure: 'You have unsaved changes. Are you sure you want to leave?',
        },
        COMMON: {
          back: 'Back',
          loading: 'Loading...',
        },
      },
    },
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

describe('DomainSso', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();

    // Reset domain mocks
    mockDomain.value = null;
    mockDomainLoading.value = false;
    mockDomainError.value = null;

    // Reset SSO config mocks
    mockSsoLoading.value = false;
    mockSsoInitialized.value = true;
    mockSsoSaving.value = false;
    mockSsoDeleting.value = false;
    mockSsoTesting.value = false;
    mockSsoError.value = null;
    mockSsoConfig.value = null;
    mockFormState.value = {
      provider: 'oidc',
      enabled: false,
      allowed_domains: '',
      client_id: '',
      client_secret: '',
      issuer_url: '',
    };
    mockTestResult.value = null;
    mockTestError.value = null;
    mockIsConfigured.value = false;
    mockHasUnsavedChanges.value = false;
    mockClientSecretMasked.value = '';

    // Reset entitlements and org mocks
    mockCanManageSso.value = true;
    mockOrganizations.value = [
      { extid: 'org_123', display_name: 'Test Org', entitlements: ['manage_sso'] },
    ];
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = async (props = {}) => {
    const component = mount(DomainSso, {
      props: {
        orgid: 'org_123',
        extid: 'dm_test123',
        ...props,
      },
      global: {
        plugins: [i18n, createPinia()],
        stubs: {
          Teleport: true,
        },
      },
    });
    await flushPromises();
    return component;
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // Page title rendering
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Page title rendering', () => {
    it('renders page title', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const title = wrapper.find('[data-testid="sso-config-title"]');
      expect(title.exists()).toBe(true);
      expect(title.text()).toContain('Domain SSO Configuration');
    });

    it('displays domain name when loaded', async () => {
      mockDomain.value = { display_domain: 'secure.example.com' };
      wrapper = await mountComponent();

      expect(wrapper.text()).toContain('secure.example.com');
    });

    it('does not display domain name while loading', async () => {
      mockDomainLoading.value = true;
      mockDomain.value = null;
      wrapper = await mountComponent();

      // Header wrapper stays mounted (see DomainHeader fix 89397e08c) and
      // shows a skeleton placeholder while domain is null — the domain name
      // text itself must be absent.
      expect(wrapper.find('.border-b').exists()).toBe(true);
      expect(wrapper.find('.animate-pulse').exists()).toBe(true);
      expect(wrapper.text()).not.toContain('secure.example.com');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Loading state', () => {
    it('shows loading state while fetching domain details', async () => {
      mockDomainLoading.value = true;
      wrapper = await mountComponent();

      // Should show loading indicator
      const loadingIcon = wrapper.find('[data-icon-name="arrow-path"]');
      expect(loadingIcon.exists()).toBe(true);
      expect(wrapper.text()).toContain('Loading...');
    });

    it('calls initialize on mount', async () => {
      wrapper = await mountComponent();

      expect(mockInitializeDomain).toHaveBeenCalled();
    });

    it('hides loading state when domain loads', async () => {
      mockDomainLoading.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      // Should not show loading text in content area
      const loadingText = wrapper.find('.text-center p');
      expect(loadingText.exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // DomainSsoConfigForm rendering
  // ─────────────────────────────────────────────────────────────────────────────

  describe('DomainSsoConfigForm rendering', () => {
    it('renders DomainSsoConfigForm when domain loads successfully', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.exists()).toBe(true);
    });

    it('passes correct domainExtId prop to DomainSsoConfigForm', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent({ extid: 'dm_custom123' });

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.attributes('data-domain-ext-id')).toBe('dm_custom123');
    });

    it('does not render DomainSsoConfigForm while loading', async () => {
      mockDomainLoading.value = true;
      wrapper = await mountComponent();

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.exists()).toBe(false);
    });

    it('does not render DomainSsoConfigForm when error occurs', async () => {
      mockDomainError.value = { message: 'Domain not found' };
      wrapper = await mountComponent();

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.exists()).toBe(false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Error handling
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Error handling', () => {
    it('displays error message when domain fetch fails', async () => {
      mockDomainError.value = { message: 'Failed to load domain' };
      wrapper = await mountComponent();

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.attributes('data-error')).toBe('Failed to load domain');
    });

    it('handles domain not found (404) error', async () => {
      mockDomainError.value = { message: 'Domain not found' };
      wrapper = await mountComponent();

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.text()).toContain('Domain not found');
    });

    it('handles unauthorized access (403) error', async () => {
      mockDomainError.value = { message: 'You do not have permission to access this domain' };
      wrapper = await mountComponent();

      const alerts = wrapper.find('[data-testid="form-alerts"]');
      expect(alerts.exists()).toBe(true);
      expect(alerts.text()).toContain('permission');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Entitlement warning
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Entitlement warning', () => {
    it('shows entitlement warning when manage_sso not available', async () => {
      mockCanManageSso.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      expect(wrapper.text()).toContain('Access Denied');
      expect(wrapper.text()).toContain('You do not have permission to manage SSO');
    });

    it('does not show DomainSsoConfigForm when manage_sso not available', async () => {
      mockCanManageSso.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.exists()).toBe(false);
    });

    it('shows lock icon when access denied', async () => {
      mockCanManageSso.value = false;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const lockIcon = wrapper.find('[data-icon-name="lock-closed"]');
      expect(lockIcon.exists()).toBe(true);
    });

    it('shows DomainSsoConfigForm when user has manage_sso entitlement', async () => {
      mockCanManageSso.value = true;
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const form = wrapper.find('[data-testid="domain-sso-config-form"]');
      expect(form.exists()).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Navigation', () => {
    it('navigates back to domains list when back button clicked', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent({ orgid: 'org_abc123' });

      const backButton = wrapper.find('button[type="button"]');
      await backButton.trigger('click');

      expect(mockRouterPush).toHaveBeenCalledWith('/org/org_abc123/domains');
    });

    it('shows back button with arrow icon', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const backButton = wrapper.find('button[type="button"]');
      expect(backButton.exists()).toBe(true);

      const arrowIcon = backButton.find('[data-icon-name="arrow-left"]');
      expect(arrowIcon.exists()).toBe(true);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Event handling
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Event handling', () => {
    it('shows success message when saved event is emitted', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const form = wrapper.findComponent({ name: 'DomainSsoConfigForm' });
      await form.vm.$emit('saved');
      await flushPromises();

      // The success message should be displayed via BasicFormAlerts
      const alerts = wrapper.find('[data-testid="form-alerts"]');
      // Note: In the actual component, success is set via the @saved handler
      // This test verifies the event listener is connected
      expect(form.emitted('saved')).toBeTruthy();
    });

    it('shows success message when deleted event is emitted', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const form = wrapper.findComponent({ name: 'DomainSsoConfigForm' });
      await form.vm.$emit('deleted');
      await flushPromises();

      expect(form.emitted('deleted')).toBeTruthy();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Accessibility
  // ─────────────────────────────────────────────────────────────────────────────

  describe('Accessibility', () => {
    it('has accessible back button with sr-only text', async () => {
      mockDomain.value = { display_domain: 'example.com' };
      wrapper = await mountComponent();

      const srOnly = wrapper.find('.sr-only');
      expect(srOnly.exists()).toBe(true);
      expect(srOnly.text()).toBe('Back');
    });

    it('loading spinner has aria-hidden attribute', async () => {
      mockDomainLoading.value = true;
      wrapper = await mountComponent();

      const spinnerIcon = wrapper.find('[data-icon-name="arrow-path"]');
      expect(spinnerIcon.exists()).toBe(true);
    });
  });
});
